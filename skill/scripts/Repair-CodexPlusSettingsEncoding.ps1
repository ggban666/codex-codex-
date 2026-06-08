param(
  [string]$StateDir = "$env:USERPROFILE\.codex-session-delete",
  [string]$SettingsPath = "",
  [string]$BackupPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $SettingsPath) {
  $SettingsPath = Join-Path $StateDir "settings.json"
}
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
  throw "settings.json not found: $SettingsPath"
}

$script = @'
const fs = require("fs");
const path = require("path");

const settingsPath = process.argv[2];
const explicitBackup = process.argv[3] || "";
const stateDir = path.dirname(settingsPath);

function readJson(file) {
  const raw = fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(raw);
}

function isLikelyMojibake(s) {
  return /[瀹绋绀惧尯澶╂湰骞诲煄鑷姩璇妯瀷涓嶇ǔ姹熸箹鑻卞浗浠欑紭閲嶈鎴戠殑]/.test(s || "");
}

let current = readJson(settingsPath);
let backups = [];
if (explicitBackup) {
  backups.push(explicitBackup);
} else {
  backups = fs.readdirSync(stateDir)
    .filter(name => /^settings\.backup-.*\.json$/i.test(name))
    .map(name => path.join(stateDir, name))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
}

let selected = null;
let selectedJson = null;
for (const file of backups) {
  try {
    const j = readJson(file);
    const names = (j.relayProfiles || []).map(p => p.name || "");
    if (names.some(n => /[\u4e00-\u9fff]/.test(n)) && !names.every(isLikelyMojibake)) {
      selected = file;
      selectedJson = j;
      break;
    }
  } catch {
    continue;
  }
}

if (!selectedJson) {
  throw new Error("No valid Chinese settings backup found. Pass -BackupPath explicitly.");
}

const stamp = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
const before = path.join(stateDir, `settings.backup-before-encoding-repair-${stamp}.json`);
fs.copyFileSync(settingsPath, before);

const goodNames = new Map((selectedJson.relayProfiles || []).map(p => [p.id, p.name]));
const fixes = [];
for (const p of current.relayProfiles || []) {
  const good = goodNames.get(p.id);
  if (good && p.name !== good && (isLikelyMojibake(p.name) || /[\u4e00-\u9fff]/.test(good))) {
    fixes.push({ id: p.id, from: p.name, to: good });
    p.name = good;
  }
}

const goodCommon = selectedJson.relayCommonConfigContents || "";
const curCommon = current.relayCommonConfigContents || "";
const goodProjectLines = goodCommon.split("\n").filter(l => l.startsWith("[projects."));
const curProjectLines = curCommon.split("\n").filter(l => l.startsWith("[projects."));
let projectFixes = 0;
if (goodProjectLines.length === curProjectLines.length && goodProjectLines.length > 0) {
  let next = curCommon;
  for (let i = 0; i < curProjectLines.length; i++) {
    if (curProjectLines[i] !== goodProjectLines[i] && isLikelyMojibake(curProjectLines[i])) {
      next = next.replace(curProjectLines[i], goodProjectLines[i]);
      projectFixes++;
    }
  }
  current.relayCommonConfigContents = next;
}

fs.writeFileSync(settingsPath, JSON.stringify(current, null, 2) + "\n", "utf8");
readJson(settingsPath);

console.log(JSON.stringify({
  settingsPath,
  selectedBackup: selected,
  backupBeforeWrite: before,
  providerNameFixes: fixes,
  projectPathFixes: projectFixes
}, null, 2));
'@

$tmp = Join-Path $env:TEMP ("repair-codex-plus-settings-" + [guid]::NewGuid().ToString("N") + ".js")
Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
try {
  node $tmp $SettingsPath $BackupPath
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
