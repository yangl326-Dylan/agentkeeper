# 实施计划：设置页检查更新

日期：2026-11-05
设计：`docs/superpowers/specs/2026-11-05-app-update-design.md`

## 步骤（TDD）

1. `AppVersion` 测试 → 实现（解析、比较、`v` 前缀、预发布后缀）
2. `UpdateService` 测试 → 实现
   - `ReleaseInfo` / `UpdateError` / `ReleaseFetching`
   - `GitHubReleaseClient`：JSON 解码、资产选择、URL 安全校验、HTTP 错误
3. `AppUpdateInstaller` 测试 → 实现
   - 暂存 App 版本/标识校验
   - 替换脚本生成（等待 PID、备份、回滚、重启、清理）
   - 路径转义；父目录不可写时拒绝
   - 下载/解压执行层（注入下载器，便于测试）
4. `UpdateModel` 测试 → 实现（状态机、手动检查、安装失败处理）
5. `L10n` 中英文案 + `AppSettingsView` 新 Section
6. `AppEnvironment` 装配 `UpdateModel`
7. 验收：`swift build` 0 warning、`swift test` 全绿
8. 升版 0.3.0（`scripts/build-app.sh`）、提交、推送、发 tag、本地重装验收

## 风险与缓解

- 替换运行中的 App：必须由后台脚本在进程退出后执行；脚本带备份回滚
- `/Applications` 不可写：提前检测父目录可写性，失败时给 Release 页面兜底
- 未公证 App：解压后去 quarantine 并 ad-hoc 重签；文档说明仍需用户信任
- GitHub API 限流：仅手动检查（60 次/小时足够），错误信息透传
- 开发态无 Bundle 版本：显示 0.0.0 并禁用安装，避免误替换
