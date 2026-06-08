# Windows 免安装版 Codex 修复教程

本文整理一次实际排查过程，目标是帮助修复 Windows 免安装版 Codex Desktop 的汉化、插件商店、Computer Use、浏览器/Edge、Codex++ 后端连接和 Codex++ 配置乱码问题。

## 适用范围

- Windows 免安装版 Codex Desktop，例如：
  - `E:\OpenAI.Codex_26.602.4764.0_x64免安装版\app`
- Codex++ 中转站软件，例如：
  - `E:\Codex++`
- 本地 Codex++ 状态目录：
  - `%USERPROFILE%\.codex-session-delete`

## 先说结论

### 1. 汉化的核心补丁

汉化真正有效的位置通常在 ASAR 的 webview 主入口文件里：

```text
webview\assets\app-main-*.js
```

常见目标是把：

```js
get(`enable_i18n`,!1)
```

改成：

```js
get(`enable_i18n`,!0)
```

只写配置或改缓存文件，重启后可能失效。

### 2. 插件商店和 Computer Use 是前端 gate + 本地插件配置问题

插件商店、Computer Use、browser、chrome/Edge 相关能力通常同时依赖：

- Codex 前端 webview gate 是否被隐藏。
- `%USERPROFILE%\.codex\config.toml` 是否启用了对应插件。
- `%USERPROFILE%\.codex\plugins\cache\...` 是否有可用插件缓存。
- Windows Computer Use 环境变量和 sandbox 配置是否正确。

### 3. Codex++ 的“后端未连接”可能是假象

如果这个接口返回 ok：

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:57321/backend/status" -Body "{}" -ContentType "application/json"
```

但 Codex++ UI 仍显示“后端未连接”，要看日志：

```text
%USERPROFILE%\.codex-session-delete\codex-plus.log
```

如果出现：

```text
renderer.script_loaded
renderer.upstream_pending_worktree_patch_failed
renderer.service_tier_dispatcher_patch_failed
Codex dispatcher unavailable
```

说明不是 `57321` 后端坏了，而是 Codex 前端 dispatcher 结构和 Codex++ 注入脚本不兼容。常见原因是汉化教程或 Fast Mode / plugin gate 补丁改动过多。

## 推荐修复顺序

1. 备份 `app.asar`、`settings.json`、`config.toml`。
2. 先修 Codex 本体的插件商店、Computer Use、browser/Edge。
3. 再做汉化补丁。
4. 最后检查 Codex++ 是否仍能注入。
5. 如果 Codex++ 断开，使用“兼容汉化 ASAR”：保留汉化文件，回退非必要的 dispatcher/service-tier/plugin 相关前端补丁。

## 诊断命令

### 检查端口

```powershell
Get-NetTCPConnection -LocalPort 57319,57320,57321,9229 -ErrorAction SilentlyContinue |
  Select-Object LocalAddress,LocalPort,State,OwningProcess |
  Sort-Object LocalPort,OwningProcess
```

含义：

- `57319`: Codex++ manager。
- `57320`: Codex++ launcher guard。
- `57321`: Codex++ helper backend。
- `9229`: Codex Electron CDP 调试端口。

### 检查 Codex++ 后端

```powershell
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:57321/backend/status" -Body "{}" -ContentType "application/json"
```

正常结果类似：

```json
{"status":"ok","message":"后端已连接","version":"1.2.3","transport":"http-helper"}
```

### 检查 Codex++ 日志

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex-session-delete\codex-plus.log" -Tail 120
```

重点搜索：

```text
Codex dispatcher unavailable
renderer.script_loaded
helper.backend_status_ok
launcher.ensure_injection_retry_failed
```

## 汉化与 Codex++ 兼容策略

如果完整补丁后 Codex++ 断开，建议构建兼容 ASAR：

1. 从当前已汉化 ASAR 提取完整目录。
2. 从原始备份 ASAR 提取完整目录。
3. 以当前目录为基础。
4. 保留：

```text
webview\assets\app-main-*.js
```

5. 从原始 ASAR 恢复这些类型的文件：

```text
.vite\build\main-*.js
webview\assets\browser-sidebar-availability-*.js
webview\assets\local-remote-selection-*.js
webview\assets\plugins-page-*.js
webview\assets\read-service-tier-for-request-*.js
webview\assets\use-is-plugins-enabled-*.js
webview\assets\use-plugin-install-flow-*.js
webview\assets\use-service-tier-settings-*.js
```

6. 重新打包时要保留 `app.asar.unpacked` 的 native 模块布局，避免用粗暴的 `--unpack-dir node_modules`。

本仓库提供脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\skill\scripts\New-CodexCompatI18nAsar.ps1" `
  -CurrentAsar "E:\...\app\resources\app.asar" `
  -OriginalAsar "E:\...\backup-before-portable-patch-...\app.asar" `
  -OutputAsar "$env:TEMP\app.codexpp-compat-i18n.asar"
```

生成后，完全退出 Codex 和 Codex++，再替换：

```powershell
Copy-Item "E:\...\app\resources\app.asar" "E:\...\app\resources\app.asar.backup-before-compat" -Force
Copy-Item "$env:TEMP\app.codexpp-compat-i18n.asar" "E:\...\app\resources\app.asar" -Force
```

## Computer Use 修复要点

常见必要配置：

```toml
[features]
computer_use = true

[windows]
sandbox = "unelevated"

[plugins."computer-use@openai-bundled"]
enabled = true
```

环境变量：

```powershell
[Environment]::SetEnvironmentVariable("CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE", "1", "User")
```

检查 helper 文件是否存在：

```powershell
Test-Path "$env:USERPROFILE\.codex\plugins\cache\openai-bundled\computer-use\latest\node_modules\@oai\sky\dist\project\cua\sky_js\src\targets\windows\internal\helper_transport.js"
```

## Browser / Chrome / 本地 Edge

Codex 插件名称可能叫 `chrome@openai-bundled`，但实际自动化可连接 Chromium 系浏览器。若用户使用 Edge，排查重点不是“是不是谷歌”，而是：

- 插件缓存是否存在。
- native host 是否指向稳定缓存路径。
- Codex 前端是否把 browser/chrome gate 隐藏。
- Edge 是否允许远程调试或插件连接。

如果插件商店已经能访问，优先通过插件商店安装/启用 browser、chrome、computer-use，再验证。

## Codex++ 设置乱码修复

乱码常见原因：PowerShell 5.1 用错误编码读取/写入 JSON，把 UTF-8 中文二次编码。

症状：

```text
deepseek-v4-pro瀹樻柟绋冲畾
绀惧尯gpt澶╁ぉ鎹ey
```

修复方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\skill\scripts\Repair-CodexPlusSettingsEncoding.ps1"
```

脚本会：

- 自动寻找 `%USERPROFILE%\.codex-session-delete\settings.backup-*`。
- 从有效备份恢复 `relayProfiles[*].name`。
- 恢复 `relayCommonConfigContents` 里的中文 `[projects.'...']` 路径。
- 保留当前 API Key、模型列表、Codex 路径等字段。
- 先备份当前文件再写入。

## 注意事项

- 不要把包含 API Key 的个人 `settings.json` 上传 GitHub。
- 不要上传 `app.asar`，体积大且可能涉及版权。
- 替换 ASAR 后必须完全重启 Codex。
- 如果进程无法终止，常见原因是权限级别不同；用管理员终端关闭，或手动退出应用。
- 若 Codex++ 与新补丁仍不兼容，应优先保留 Codex 插件商店/Computer Use 可用，再等待 Codex++ 更新适配。
