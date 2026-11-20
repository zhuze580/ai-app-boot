# WorkBuddy 项目入口

先读 README.md 与 AGENTS.md。这是给 Codex 和 WorkBuddy 两款应用本身加启动动画的独立项目。

- 检查 Codex：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\launch.ps1 -App Codex -Action Check`
- 检查 WorkBuddy：同上改为 `-App WorkBuddy`。
- 运行测试：`npm test`，或 launch.ps1 的 `-Action Test`。
- 单独预览：`-Action Preview`。
- 真正启动所选应用及视频：`-Action Start`。

不要为测试而结束用户正在使用的应用。安装桌面入口需使用用户明确选择的 App 参数。配置路径请写入被 Git 忽略的 config.local.json。
