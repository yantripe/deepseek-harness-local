# Windows server hardening for a local DeepSeek Harness install (run as Administrator).
# Prerequisites: the build is installed in C:\dsh\harness and Node in C:\dsh\node (see
# WINDOWS_SERVER_RU.md, steps 1-3), Ollama in C:\dsh\ollama, models in C:\dsh\ollama-models,
# and the local service account `dshsvc` exists with the "Log on as a batch job" right.
# What it does: ACLs, integrity labels, firewall, explicit-environment scheduled tasks.
param(
  [Parameter(Mandatory)] [string] $AdminSubnet,          # e.g. 10.0.5.0/24 — the only source allowed to SSH in
  [switch] $SkipServices
)
$ErrorActionPreference = 'Stop'
# Guest/remote sessions can carry an unusable TEMP; Add-Type compiles through it.
$env:TEMP = $env:TMP = "$env:SystemRoot\Temp"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
function Step($name) { "`n=== $(Get-Date -Format HH:mm:ss) $name" }

Step 'Folders and configuration'
New-Item -ItemType Directory -Force C:\dsh\home, C:\dsh\logs, C:\dsh\bin, C:\dsh\work | Out-Null
if (-not (Test-Path C:\dsh\home\cordis.patch.yml)) { Copy-Item "$here\..\config\server-hardening.cordis.patch.yml" C:\dsh\home\cordis.patch.yml }
Copy-Item "$here\..\config\start-dsh-web.ps1", "$here\..\config\start-ollama.ps1" C:\dsh\bin -Force

Step 'ACLs: nothing under C:\dsh for ordinary users; the service reads/executes, writes only its own data'
# No /T: children inherit. (/T with (OI)(CI) grants leaves files with empty ACLs.)
icacls C:\dsh /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' 'dshsvc:(OI)(CI)RX' /C /Q | Out-Null
icacls C:\dsh\work /grant 'dshsvc:(OI)(CI)F' /C /Q | Out-Null   # full control: the sandbox edits the workspace ACL
foreach ($d in 'C:\dsh\home', 'C:\dsh\logs', 'C:\dsh\ollama-models') { icacls $d /grant 'dshsvc:(OI)(CI)M' /C /Q | Out-Null }

Step 'Integrity labels: Medium + No-Read-Up (the agent sandbox runs at Low integrity)'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DshLabel {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl, uint rev, out IntPtr sd, out uint size);
  [DllImport("advapi32.dll", SetLastError=true)]
  static extern bool GetSecurityDescriptorSacl(IntPtr sd, out bool present, out IntPtr sacl, out bool defaulted);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern uint SetNamedSecurityInfo(string name, int type, uint info, IntPtr o, IntPtr g, IntPtr dacl, IntPtr sacl);
  public static void Set(string path, string sddl) {
    IntPtr sd; uint size; bool present, defaulted; IntPtr sacl;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out sd, out size)) throw new System.ComponentModel.Win32Exception();
    if (!GetSecurityDescriptorSacl(sd, out present, out sacl, out defaulted)) throw new System.ComponentModel.Win32Exception();
    uint rc = SetNamedSecurityInfo(path, 1 /*SE_FILE_OBJECT*/, 0x10 /*LABEL_SECURITY_INFORMATION*/, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, sacl);
    if (rc != 0) throw new System.ComponentModel.Win32Exception((int)rc);
  }
}
'@
foreach ($d in 'C:\dsh\home', 'C:\dsh\logs', 'C:\dsh\bin') {
  [DshLabel]::Set($d, 'S:(ML;OICI;NRNW;;;ME)')
  "$d : " + ((icacls $d | Select-String 'NW,NR') -join ' ').Trim()
}

Step 'Firewall: outbound blocked by default; no "block all" rules (a block rule overrides every allow rule)'
Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block `
  -LogBlocked True -LogMaxSizeKilobytes 32767 -LogFileName '%systemroot%\system32\LogFiles\Firewall\pfirewall.log'
Get-NetFirewallRule -DisplayName 'DSH*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'DSH: SSH from admin subnet' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 `
  -RemoteAddress $AdminSubnet -Profile Any | Out-Null
auditpol /set /subcategory:'{0CCE9226-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:'{0CCE9225-69AE-11D9-BED3-505054503030}' /failure:enable | Out-Null
netsh winhttp reset proxy | Out-Null
Get-NetFirewallProfile | ForEach-Object { "$($_.Name): in=$($_.DefaultInboundAction) out=$($_.DefaultOutboundAction)" }

if (-not $SkipServices) {
  Step 'Services: scheduled tasks as dshsvc with an explicit environment'
  $cred = Get-Credential dshsvc
  foreach ($t in @(@{ n = 'DSH-Ollama'; f = 'C:\dsh\bin\start-ollama.ps1' }, @{ n = 'DSH-Web'; f = 'C:\dsh\bin\start-dsh-web.ps1' })) {
    Register-ScheduledTask -TaskName $t.n `
      -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $($t.f)") `
      -Trigger (New-ScheduledTaskTrigger -AtStartup) `
      -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) `
      -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Force | Out-Null
  }
  Start-ScheduledTask DSH-Ollama; Start-Sleep 5; Start-ScheduledTask DSH-Web; Start-Sleep 25
  Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 3080, 11434 } |
    ForEach-Object { '{0}:{1}' -f $_.LocalAddress, $_.LocalPort }
  'Launch link: last "token=" line in C:\dsh\logs\dsh-web.log (readable by administrators only).'
}
