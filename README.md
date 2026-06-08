# Codex Windows Portable Repair Kit

用于 Windows 免安装版 Codex Desktop 的汉化、插件商店、Computer Use、浏览器/Edge、Codex++ 后端连接排查与修复记录。

这个仓库包含两部分：

- `skill/`: 可安装到 Codex 的 Skill，供 Codex 代理按流程排查。
- `docs/repair-guide.zh-CN.md`: 人工操作教程和原理说明。
- `skill/scripts/`: 可复用的 PowerShell 辅助脚本。

## 解决的问题

- Codex 免安装版界面重启后无法汉化。
- 插件商店入口消失、插件页不可访问。
- Computer Use / Browser / Chrome 或本地 Edge 相关能力被前端 gate 隐藏。
- Codex++ 显示后端未连接，但 `57321` 后端实际可用。
- Codex++ 供应商名称或配置路径被 PowerShell 编码写坏后出现乱码。

## 重要结论

Codex++ 的“后端未连接”不一定是后端没启动。若 `http://127.0.0.1:57321/backend/status` 返回 ok，但日志里出现：

```text
Codex dispatcher unavailable
renderer.service_tier_dispatcher_patch_failed
renderer.upstream_pending_worktree_patch_failed
```

通常是 Codex 前端 ASAR 补丁改变了 Codex++ 注入脚本依赖的 dispatcher 结构。此时应优先做兼容补丁：保留汉化文件，回退非必要的 Fast Mode / plugin gate / service tier 前端补丁。

## 快速使用

下载源码 ZIP：

[下载 main.zip](https://github.com/ggban666/codex-codex-/archive/refs/heads/main.zip)

这个链接是 GitHub 自动生成的源码压缩包，不需要额外发布 Release。

或者用 Git 克隆：

```powershell
git clone https://github.com/ggban666/codex-codex-.git
cd codex-codex-
```

安装 Skill：

```powershell
Copy-Item -Recurse -Force ".\skill" "$env:USERPROFILE\.codex\skills\codex-windows-portable-repair-kit"
```

查看详细教程：

```text
docs/repair-guide.zh-CN.md
```

运行诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\skill\scripts\Test-CodexPortableRepair.ps1" `
  -AppPath "E:\OpenAI.Codex_26.602.4764.0_x64免安装版\app"
```

修复 Codex++ 配置中文乱码：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\skill\scripts\Repair-CodexPlusSettingsEncoding.ps1"
```

生成 Codex++ 兼容汉化 ASAR：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\skill\scripts\New-CodexCompatI18nAsar.ps1" `
  -CurrentAsar "E:\OpenAI.Codex_26.602.4764.0_x64免安装版\app\resources\app.asar" `
  -OriginalAsar "E:\OpenAI.Codex_26.602.4764.0_x64免安装版\app\resources\backup-before-portable-patch-YYYYMMDD-HHMMSS\app.asar" `
  -OutputAsar "$env:TEMP\app.codexpp-compat-i18n.asar"
```

## 安全说明

- 脚本不会包含、读取或上传 API Key。
- 替换 `app.asar` 前必须备份。
- 替换 ASAR 后必须完全退出并重新打开 Codex / Codex++ 才会生效。
- 不建议对 `C:\Program Files\WindowsApps` 原地修改；本仓库主要面向免安装版目录。

## License

MIT
