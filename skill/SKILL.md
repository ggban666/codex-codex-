---
name: codex-windows-portable-repair-kit
description: Repair and diagnose Windows portable Codex Desktop localization, plugin store gates, Computer Use, browser/Edge availability, Codex++ backend status, ASAR compatibility, and Codex++ settings encoding corruption.
---

# Codex Windows Portable Repair Kit

Use this skill for Windows portable Codex Desktop repairs involving localization, plugin store visibility, Computer Use, browser/Edge automation availability, Codex++ backend connection state, ASAR repacking, or Codex++ settings mojibake.

## Guardrails

- Prefer diagnosis before patching. Distinguish a dead backend from a renderer injection failure.
- Never expose or rewrite API keys. If editing Codex++ settings, preserve auth fields as-is.
- Back up any file before writing it, especially `app.asar`, `settings.json`, and `config.toml`.
- Avoid PowerShell JSON rewriting for files containing Chinese text unless the script explicitly handles UTF-8. Use Node.js for JSON edits when possible.
- For portable Codex, patch the app directory supplied by the user. Do not modify `C:\Program Files\WindowsApps` in place.
- Replacing `app.asar` requires a full Codex/Codex++ restart before verification.

## Triage Workflow

1. Run `scripts/Test-CodexPortableRepair.ps1` with the portable `-AppPath`.
2. Check Codex++ backend:
   - `POST http://127.0.0.1:57321/backend/status`
   - Ports `57319`, `57320`, `57321`, and `9229`.
3. If `57321` returns ok but Codex++ UI says disconnected, inspect `%USERPROFILE%\.codex-session-delete\codex-plus.log`.
4. If the log contains `Codex dispatcher unavailable`, treat it as a frontend dispatcher compatibility problem, not a helper backend problem.
5. If provider names or project paths are mojibake, run `scripts/Repair-CodexPlusSettingsEncoding.ps1`.
6. If localization must be retained while restoring Codex++ compatibility, generate a compatible ASAR with `scripts/New-CodexCompatI18nAsar.ps1`.

## Common Diagnoses

### Backend is actually down

Symptoms:

- `57321` is not listening.
- `/backend/status` cannot connect.
- Codex++ manager may listen on `57319` but launcher/helper is absent.

Action:

- Start Codex++ normally.
- If stale elevated processes cannot be stopped, ask the user to close Codex++ manually or run an elevated terminal.
- Recheck ports and `/backend/status`.

### Backend is ok but UI still says disconnected

Symptoms:

- `/backend/status` returns `{"status":"ok" ...}`.
- Log shows `renderer.script_loaded`.
- Log then shows `Codex dispatcher unavailable`.

Action:

- Explain that the UI message is misleading.
- Use a compatible ASAR: keep the i18n patch, revert nonessential frontend unlock patches that alter dispatcher/service-tier/plugin behavior.

### Provider names are mojibake

Symptoms:

- Codex++ provider names look like `瀹樻柟绋冲畾`.
- Earlier `settings.backup-*` files have correct Chinese names.

Action:

- Run `Repair-CodexPlusSettingsEncoding.ps1`.
- It restores `relayProfiles[*].name` and Chinese project-path lines from the newest valid backup while preserving current API keys and paths.

## Scripts

- `scripts/Test-CodexPortableRepair.ps1`: endpoint, port, ASAR, and settings diagnostics.
- `scripts/Repair-CodexPlusSettingsEncoding.ps1`: repair Codex++ settings mojibake from backups.
- `scripts/New-CodexCompatI18nAsar.ps1`: build a Codex++ compatible i18n ASAR by combining current patched ASAR and original backup ASAR.

## Verification

After repairs:

- `Invoke-RestMethod -Method Post http://127.0.0.1:57321/backend/status` returns `status = ok`.
- Plugin store opens in Codex.
- UI language remains Chinese after restart.
- Computer Use / browser plugins are visible if enabled by the user's local config.
- Codex++ log does not add new `Codex dispatcher unavailable` events after the app was fully restarted with the compatible ASAR.
