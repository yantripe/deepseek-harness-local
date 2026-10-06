# Starts `ollama serve` with an explicit, minimal environment: local models only, loopback only.
$ErrorActionPreference = 'Stop'
$psi = [System.Diagnostics.ProcessStartInfo]::new("$env:SystemRoot\System32\cmd.exe")
$psi.Arguments = '/d /c ""C:\dsh\ollama\ollama.exe" serve >> C:\dsh\logs\ollama.log 2>&1"'
$psi.WorkingDirectory = 'C:\dsh\ollama'
$psi.UseShellExecute = $false
$psi.EnvironmentVariables.Clear()
foreach ($name in 'SystemRoot', 'SystemDrive', 'windir', 'ComSpec', 'PATHEXT', 'USERPROFILE', 'USERNAME', 'APPDATA',
  'LOCALAPPDATA', 'ProgramData', 'ProgramFiles', 'TEMP', 'TMP', 'PROCESSOR_ARCHITECTURE', 'NUMBER_OF_PROCESSORS', 'OS') {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ($null -ne $value) { $psi.EnvironmentVariables[$name] = $value }
}
$psi.EnvironmentVariables['PATH'] = "C:\dsh\ollama;$env:SystemRoot\System32;$env:SystemRoot"
$psi.EnvironmentVariables['OLLAMA_MODELS'] = 'C:\dsh\ollama-models'
$psi.EnvironmentVariables['OLLAMA_NO_CLOUD'] = '1'
$psi.EnvironmentVariables['OLLAMA_HOST'] = '127.0.0.1:11434'
$psi.EnvironmentVariables['OLLAMA_CONTEXT_LENGTH'] = '16384'
Add-Content -Encoding utf8 C:\dsh\logs\ollama.log "=== $(Get-Date -Format s) start"
$process = [System.Diagnostics.Process]::Start($psi)
$process.WaitForExit()
exit $process.ExitCode
