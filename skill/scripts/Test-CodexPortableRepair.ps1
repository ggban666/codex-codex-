param(
  [Parameter(Mandatory = $true)]
  [string]$AppPath,

  [string]$CodexPlusStateDir = "$env:USERPROFILE\.codex-session-delete"
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host "== $Title =="
}

function Test-JsonPost {
  param([string]$Uri)
  try {
    Invoke-RestMethod -Method Post -Uri $Uri -Body "{}" -ContentType "application/json" -TimeoutSec 3
  } catch {
    [pscustomobject]@{ error = $_.Exception.Message }
  }
}

Write-Section "Paths"
$resources = Join-Path $AppPath "resources"
$asar = Join-Path $resources "app.asar"
$unpacked = Join-Path $resources "app.asar.unpacked"
[pscustomobject]@{
  AppPath = $AppPath
  CodexExe = Join-Path $AppPath "Codex.exe"
  AppAsar = $asar
  AppAsarExists = Test-Path -LiteralPath $asar -PathType Leaf
  AppAsarUnpackedExists = Test-Path -LiteralPath $unpacked -PathType Container
} | Format-List

if (Test-Path -LiteralPath $asar -PathType Leaf) {
  Write-Section "ASAR Hash"
  Get-FileHash -Algorithm SHA256 -LiteralPath $asar | Format-List
}

Write-Section "Ports"
Get-NetTCPConnection -LocalPort 57319,57320,57321,9229 -ErrorAction SilentlyContinue |
  Select-Object LocalAddress,LocalPort,State,OwningProcess |
  Sort-Object LocalPort,OwningProcess |
  Format-Table -AutoSize

Write-Section "Codex++ Backend"
Test-JsonPost "http://127.0.0.1:57321/backend/status" | ConvertTo-Json -Depth 8

Write-Section "Codex CDP"
$cdpResults = foreach ($uri in @("http://127.0.0.1:9229/json/version", "http://[::1]:9229/json/version")) {
  try {
    $r = Invoke-RestMethod -Uri $uri -TimeoutSec 3
    [pscustomobject]@{ uri = $uri; status = "ok"; browser = $r.Browser; webSocketDebuggerUrl = $r.webSocketDebuggerUrl }
  } catch {
    [pscustomobject]@{ uri = $uri; status = "error"; error = $_.Exception.Message }
  }
}
$cdpResults | Format-List

Write-Section "Codex++ Log Signals"
$log = Join-Path $CodexPlusStateDir "codex-plus.log"
if (Test-Path -LiteralPath $log -PathType Leaf) {
  Select-String -LiteralPath $log -Pattern "Codex dispatcher unavailable|renderer.script_loaded|helper.backend_status_ok|launcher.ensure_injection_retry_failed|service_tier_dispatcher_patch_failed" |
    Select-Object -Last 40 |
    ForEach-Object { $_.Line }
} else {
  Write-Host "Log not found: $log"
}

Write-Section "Computer Use Files"
$helper = Join-Path $env:USERPROFILE ".codex\plugins\cache\openai-bundled\computer-use\latest\node_modules\@oai\sky\dist\project\cua\sky_js\src\targets\windows\internal\helper_transport.js"
[pscustomobject]@{
  EnvGate = [Environment]::GetEnvironmentVariable("CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE", "User")
  HelperTransport = $helper
  HelperTransportExists = Test-Path -LiteralPath $helper -PathType Leaf
} | Format-List

Write-Section "Codex++ Settings"
$settings = Join-Path $CodexPlusStateDir "settings.json"
if (Test-Path -LiteralPath $settings -PathType Leaf) {
  node -e "const fs=require('fs'); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'')); for (const r of j.relayProfiles||[]) console.log(r.id+' '+r.name);" $settings
} else {
  Write-Host "Settings not found: $settings"
}
