param(
  [Parameter(Mandatory = $true)]
  [string]$CurrentAsar,

  [Parameter(Mandatory = $true)]
  [string]$OriginalAsar,

  [Parameter(Mandatory = $true)]
  [string]$OutputAsar,

  [string]$WorkDir = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path -LiteralPath $CurrentAsar -PathType Leaf)) { throw "Current ASAR not found: $CurrentAsar" }
if (-not (Test-Path -LiteralPath $OriginalAsar -PathType Leaf)) { throw "Original ASAR not found: $OriginalAsar" }

if (-not $WorkDir) {
  $WorkDir = Join-Path $env:TEMP ("codex-compat-i18n-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}

$curDir = Join-Path $WorkDir "current"
$origDir = Join-Path $WorkDir "original"
$compatDir = Join-Path $WorkDir "compat"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Invoke-Asar {
  param([string[]]$Arguments)
  & npx --yes '@electron/asar' @Arguments
  if ($LASTEXITCODE -ne 0) { throw "asar command failed: $($Arguments -join ' ')" }
}

Write-Host "Extracting current ASAR..."
Invoke-Asar @("extract", $CurrentAsar, $curDir)
Write-Host "Extracting original ASAR..."
Invoke-Asar @("extract", $OriginalAsar, $origDir)

if (Test-Path -LiteralPath $compatDir) { Remove-Item -LiteralPath $compatDir -Recurse -Force }
Copy-Item -LiteralPath $curDir -Destination $compatDir -Recurse -Force

$restorePatterns = @(
  ".vite\build\main-*.js",
  "webview\assets\browser-sidebar-availability-*.js",
  "webview\assets\local-remote-selection-*.js",
  "webview\assets\plugins-page-*.js",
  "webview\assets\read-service-tier-for-request-*.js",
  "webview\assets\use-is-plugins-enabled-*.js",
  "webview\assets\use-plugin-install-flow-*.js",
  "webview\assets\use-service-tier-settings-*.js"
)

$restored = @()
foreach ($pattern in $restorePatterns) {
  $matches = Get-ChildItem -LiteralPath $origDir -Recurse -File |
    Where-Object {
      $rel = $_.FullName.Substring($origDir.Length + 1)
      $rel -like $pattern
    }
  foreach ($m in $matches) {
    $rel = $m.FullName.Substring($origDir.Length + 1)
    $dest = Join-Path $compatDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $m.FullName -Destination $dest -Force
    $restored += $rel
  }
}

$i18nFiles = Get-ChildItem -LiteralPath (Join-Path $compatDir "webview\assets") -Filter "app-main-*.js" -File -ErrorAction SilentlyContinue
$i18nOk = $false
foreach ($f in $i18nFiles) {
  $text = Get-Content -LiteralPath $f.FullName -Raw
  if ($text -match "enable_i18n" -and ($text -match "enable_i18n`,!0" -or $text -match "enable_i18n.\s*,\s*!0")) {
    $i18nOk = $true
  }
}
if (-not $i18nOk) {
  Write-Warning "Could not prove i18n is forced on. Verify webview/assets/app-main-*.js manually."
}

$outDir = Split-Path -Parent $OutputAsar
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $OutputAsar) { Remove-Item -LiteralPath $OutputAsar -Force }
if (Test-Path -LiteralPath ($OutputAsar + ".unpacked")) { Remove-Item -LiteralPath ($OutputAsar + ".unpacked") -Recurse -Force }

$unpackPattern = "**/{HID.node,serialport.node,better_sqlite3.node,better-sqlite3/lib/**,better-sqlite3/node_modules/.bin/**,node-pty/build/Release/**,node-pty/lib/**}"
Write-Host "Packing compatible ASAR..."
Invoke-Asar @("pack", $compatDir, $OutputAsar, "--unpack", $unpackPattern)

Write-Host ""
Write-Host "Output: $OutputAsar"
Write-Host "Restored files:"
$restored | Sort-Object | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "Next: fully exit Codex/Codex++, back up the installed app.asar, then copy this output ASAR into app\resources\app.asar."
