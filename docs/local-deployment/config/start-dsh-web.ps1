# Starts `dsh web` for the service account with an explicit, minimal environment.
# Nothing from the account's or the machine's environment is inherited except what is listed
# here, so a stray variable (proxy, cloud key, NODE_OPTIONS, ...) cannot change Harness behavior.
# The launch link with its one-time token goes to C:\dsh\logs\dsh-web.log, readable only by the
# service account and administrators (see the installation instruction, ACL step).
$ErrorActionPreference = 'Stop'
# cmd.exe only redirects the output into the log; it receives (and passes on) the explicit environment.
$psi = [System.Diagnostics.ProcessStartInfo]::new("$env:SystemRoot\System32\cmd.exe")
$psi.Arguments = '/d /c ""C:\dsh\node\node.exe" C:\dsh\harness\apps\cli\lib\bin.js web --no-open >> C:\dsh\logs\dsh-web.log 2>&1"'
$psi.WorkingDirectory = 'C:\dsh\work'
$psi.UseShellExecute = $false
$psi.EnvironmentVariables.Clear()
$keep = 'SystemRoot', 'SystemDrive', 'windir', 'ComSpec', 'PATHEXT', 'USERPROFILE', 'USERNAME', 'USERDOMAIN',
  'APPDATA', 'LOCALAPPDATA', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432',
  'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432', 'PSModulePath', 'TEMP', 'TMP',
  'PROCESSOR_ARCHITECTURE', 'NUMBER_OF_PROCESSORS', 'OS', 'COMPUTERNAME', 'PUBLIC', 'ALLUSERSPROFILE',
  'HOMEDRIVE', 'HOMEPATH'
foreach ($name in $keep) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ($null -ne $value) { $psi.EnvironmentVariables[$name] = $value }
}
$psi.EnvironmentVariables['PATH'] = "C:\dsh\node;$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$psi.EnvironmentVariables['DSH_HOME'] = 'C:\dsh\home'
$psi.EnvironmentVariables['DSH_PROTECTED_PATHS'] = 'C:\dsh\logs;C:\dsh\bin'
# Ollama ignores the key; the adapter only requires a non-empty value. Not a secret.
$psi.EnvironmentVariables['DEEPSEEK_API_KEY'] = 'local-ollama'
$psi.EnvironmentVariables['NODE_ENV'] = 'production'

Add-Content -Encoding utf8 C:\dsh\logs\dsh-web.log "=== $(Get-Date -Format s) start; environment: $(($psi.EnvironmentVariables.Keys | Sort-Object) -join ',')"
$process = [System.Diagnostics.Process]::Start($psi)
$process.WaitForExit()
Add-Content -Encoding utf8 C:\dsh\logs\dsh-web.log "=== $(Get-Date -Format s) exit $($process.ExitCode)"
exit $process.ExitCode
