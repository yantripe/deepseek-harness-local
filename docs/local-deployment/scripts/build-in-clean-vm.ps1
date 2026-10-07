# Round 2, clean build VM (internet via NAT, all traffic captured on the host).
# Installs Node.js (hash-checked against nodejs.org SHASUMS256) and pnpm, builds the cleaned
# Harness at the same path it will have on the server (C:\dsh\harness: pnpm junctions are
# absolute), runs the dependency audit and the tests for every changed package, and writes a
# SHA-256 manifest of the whole build so the test VM can prove it runs the very same files.
param(
  [Parameter(Mandatory)] [string] $SourceZip,
  [Parameter(Mandatory)] [string] $Commit,
  [string] $NodeLine = 'latest-v24.x',
  [switch] $Resume,  # continue after a completed install (skip Node download, unpack and install)
  [switch] $UpdateMarkdownFixtures  # re-record the markdown DOM parity corpus (intentional image change)
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$out = 'C:\b\out'
New-Item -ItemType Directory -Force C:\b, $out | Out-Null
function Step($name) { "`n=== $(Get-Date -Format HH:mm:ss) $name" }

if ($Resume) {
  $nodeDir = (Get-ChildItem C:\b -Directory -Filter 'node-v*-win-x64' | Select-Object -First 1).FullName
  $env:Path = "$nodeDir;$env:Path"; $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'; $env:COREPACK_HOME = 'C:\b\corepack'
  $env:DSH_CLIENT_COMMIT_HASH = $Commit; $env:npm_config_store_dir = 'C:\b\pnpm-store'
  Set-Location C:\dsh\harness
} else {
Step 'Node.js'
$base = "https://nodejs.org/dist/$NodeLine"
$sums = (Invoke-WebRequest -UseBasicParsing "$base/SHASUMS256.txt").Content -split "`n"
$line = $sums | Where-Object { $_ -match 'node-v[\d.]+-win-x64\.zip$' } | Select-Object -First 1
$hash, $file = $line -split '\s+'
Invoke-WebRequest -UseBasicParsing "$base/$file" -OutFile "C:\b\$file"
$actual = (Get-FileHash "C:\b\$file" -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $hash) { throw "node zip hash mismatch: $actual vs $hash" }
"node archive $file sha256 $actual (matches SHASUMS256.txt)"
Expand-Archive "C:\b\$file" C:\b -Force
$nodeDir = "C:\b\$($file -replace '\.zip$', '')"
$env:Path = "$nodeDir;C:\b\npm-global;$env:Path"
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$env:COREPACK_HOME = 'C:\b\corepack'
& "$nodeDir\corepack.cmd" enable --install-directory $nodeDir
& node --version
& pnpm --version

Step 'Source'
# rmdir removes pnpm junctions without following them into their targets
if (Test-Path C:\dsh\harness) { & cmd /d /c 'rmdir /s /q C:\dsh\harness' }
New-Item -ItemType Directory -Force C:\dsh | Out-Null
Expand-Archive $SourceZip C:\dsh\harness -Force
$env:DSH_CLIENT_COMMIT_HASH = $Commit
Set-Location C:\dsh\harness

Step 'pnpm install (lockfile refreshed for the security overrides)'
$env:npm_config_store_dir = 'C:\b\pnpm-store'
& pnpm install --no-frozen-lockfile 2>&1 | Tee-Object "$out\pnpm-install.log" | Select-Object -Last 15
if ($LASTEXITCODE -ne 0) { throw "pnpm install failed ($LASTEXITCODE)" }
Copy-Item pnpm-lock.yaml "$out\pnpm-lock.yaml"
}
# Native tools write progress to stderr; only their exit codes decide success.
$ErrorActionPreference = 'Continue'

Step 'Dependency audit'
& cmd /d /c "pnpm audit --prod --json > $out\pnpm-audit-prod.json"
& cmd /d /c "pnpm audit --json > $out\pnpm-audit-all.json"
& node -e "for (const f of ['prod','all']) { const j=require('C:/b/out/pnpm-audit-'+f+'.json'); console.log(f, JSON.stringify(j.metadata?.vulnerabilities)) }"

Step 'Build'
# The type-check of all packages needs more than node's default heap on a small VM (6 GB RAM recommended).
$env:NODE_OPTIONS = '--max-old-space-size=4096'
& pnpm run build 2>&1 | Tee-Object "$out\build.log" | Select-Object -Last 15
$buildExit = $LASTEXITCODE
Remove-Item Env:\NODE_OPTIONS
if ($buildExit -ne 0) { throw "build failed ($buildExit)" }

if ($UpdateMarkdownFixtures) {
  Step 'Re-record markdown DOM parity fixtures (cross-origin images now render as alt text)'
  & pnpm exec vitest run -u packages/client/ui-primitives/tests/markdown-dom-parity.client.spec.tsx 2>&1 | Select-Object -Last 6
  New-Item -ItemType Directory -Force "$out\fixtures" | Out-Null
  Copy-Item packages\client\ui-primitives\tests\fixtures\markdown-dom\* "$out\fixtures" -Force
}

Step 'Tests for the changed packages'
$specs = @(
  'packages/subprocess/subprocess/tests',
  'packages/llm/llm-deepseek/tests/adapter.spec.ts',
  'packages/client/connection/tests',
  'packages/fs/fs-local/tests',
  'packages/host/webserver/tests',
  'packages/client/ui-primitives/tests',
  'packages/bundle/base/tests',
  'packages/bundle/web-app/tests'
)
& pnpm exec vitest run @specs 2>&1 | Tee-Object "$out\tests.log" | Select-Object -Last 40
"vitest exit $LASTEXITCODE"

Step 'Manifest (build tree without node_modules) and transfer archives'
& node C:\b\hash-tree.mjs C:\dsh\harness "$out\manifest.sha256" --skip-node-modules
"manifest sha256 $((Get-FileHash "$out\manifest.sha256").Hash)"
$x = 'C:\b\xfer'; New-Item -ItemType Directory -Force $x | Out-Null
Get-ChildItem $x -File -Exclude 'OpenSSH-Win64.zip' | Remove-Item -Force
if (Test-Path C:\b\node) { & cmd /d /c 'rmdir /s /q C:\b\node' }
Copy-Item -Recurse -Force $nodeDir C:\b\node
& tar -cf "$x\harness-build.tar" -C C:\dsh --exclude node_modules harness
$storeRoot = Split-Path (((& pnpm store path) | Select-Object -Last 1).Trim()) -Parent
"pnpm store: $storeRoot"
# Windows tar cannot pack the pnpm store, and ZipFile.CreateFromDirectory stops at the first dangling
# v11\projects link (leaving an incomplete zip). Pack file by file and skip links (not needed offline).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open("$x\pnpm-store.zip", 'Create'); $packed = 0; $skipped = 0
$stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($storeRoot)
while ($stack.Count) {
  $d = $stack.Pop()
  try { $entries = [IO.Directory]::GetFileSystemEntries($d) } catch { $skipped++; continue }
  foreach ($p in $entries) {
    $attr = [IO.File]::GetAttributes($p)
    if ($attr -band [IO.FileAttributes]::ReparsePoint) { $skipped++; continue }
    if ($attr -band [IO.FileAttributes]::Directory) { $stack.Push($p); continue }
    try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $p, $p.Substring($storeRoot.Length + 1).Replace('\', '/'), 'Fastest'); $packed++ } catch { $skipped++ }
  }
}
$zip.Dispose(); "pnpm store zip: $packed files, $skipped links skipped"
& tar -cf "$x\node.tar" -C C:\b node corepack
Copy-Item "$out\*" $x -Force
Get-ChildItem $x | ForEach-Object { '{0,-24} {1,12:N0}  {2}' -f $_.Name, $_.Length, (Get-FileHash $_.FullName).Hash } | Tee-Object "$x\SHA256SUMS.txt"
