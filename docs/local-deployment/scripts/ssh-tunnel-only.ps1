# Server, Administrator: OpenSSH Server for tunnel-only remote access to the UI.
# Employees log in with a key, get NO shell and may forward only to 127.0.0.1:3080.
param([Parameter(Mandatory)] [string] $ZipPath, [Parameter(Mandatory)] [string] $ClientPublicKey, [string] $User = 'regular')
$ErrorActionPreference = 'Stop'
# Guest Additions sessions carry an unusable TEMP; install-sshd.ps1 compiles a helper type through it.
$env:TEMP = $env:TMP = "$env:SystemRoot\Temp"
$dir = 'C:\Program Files\OpenSSH'
if (-not (Test-Path "$dir\sshd.exe")) {
  Expand-Archive $ZipPath 'C:\Program Files' -Force
  Rename-Item 'C:\Program Files\OpenSSH-Win64' 'OpenSSH'
}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\install-sshd.ps1" 2>&1 | Select-Object -Last 3
New-Item -ItemType Directory -Force C:\ProgramData\ssh | Out-Null
New-Item -ItemType Directory -Force C:\ProgramData\ssh\authorized_keys | Out-Null
& "$dir\ssh-keygen.exe" -A 2>&1 | Out-Null
Get-ChildItem C:\ProgramData\ssh\ssh_host_* | ForEach-Object { icacls $_.FullName /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null }
Set-Content -Encoding ascii "C:\ProgramData\ssh\authorized_keys\$User" $ClientPublicKey
icacls C:\ProgramData\ssh\authorized_keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "${User}:(OI)(CI)R" | Out-Null
@"
# DSH round 2: key-only, tunnel-only access to the Harness UI.
AuthorizedKeysFile __PROGRAMDATA__/ssh/authorized_keys/%u
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
AllowUsers $User
AllowTcpForwarding local
PermitOpen 127.0.0.1:3080
PermitTTY no
X11Forwarding no
AllowAgentForwarding no
GatewayPorts no
ForceCommand cmd.exe /c echo tunnel-only
Subsystem sftp none
"@ | Set-Content -Encoding ascii C:\ProgramData\ssh\sshd_config
Set-Service sshd -StartupType Automatic
Restart-Service sshd -ErrorAction SilentlyContinue; Start-Service sshd
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize | Out-String
Get-NetTCPConnection -State Listen -LocalPort 22 | ForEach-Object { "sshd listens on $($_.LocalAddress):22" }
& "$dir\sshd.exe" -T 2>&1 | Select-String -Pattern '^(passwordauthentication|allowtcpforwarding|permitopen|permittty|allowusers|forcecommand) '
