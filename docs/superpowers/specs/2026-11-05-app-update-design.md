# 设置页检查更新设计（GitHub Release 版本对比 + 原地更新）

日期：2026-11-05
状态：已批准（用户确认直接实现）

## 背景与目标

当前 App 没有版本展示，也没有任何更新检查。用户希望：

- 设置页显示当前版本
- 手动检查 GitHub 上的最新版本（比较版本号）
- 发现新版本时可以在 App 内直接更新
- **外部不显示红点**：菜单栏、Dock、侧栏、启动弹窗一律不加更新标记

约束：无第三方依赖；`swift build` 0 warning；全量测试全绿；TDD。

## 方案选择

- **A. 内置轻量更新器（采用）**：URLSession + GitHub Releases API + 后台脚本替换 `.app`。
- B. Sparkle 2：成熟但需要 SPM 依赖、appcast、签名密钥，且默认 UI 与「无红点」冲突。
- C. 只打开 Release 页面：用户已排除。

## 架构

### 1. 版本模型 `AppVersion`（`Sources/AppCore/AppVersion.swift`）

```swift
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]      // 0.2.0 → [0, 2, 0]
    public init?(_ raw: String)       // 容忍 "v0.2.0"、"0.2"；忽略预发布后缀
}
```

- 比较：补齐尾部 0 后逐段比较
- 当前版本来自 `CFBundleShortVersionString`；非 `.app` 运行（`swift run`）回退 `"0.0.0"`

### 2. 远端查询 `UpdateService.swift`

```swift
public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let tag: String
    public let releaseURL: URL
    public let appAssetURL: URL?
}

public protocol ReleaseFetching: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}
```

`GitHubReleaseClient`：

- `GET https://api.github.com/repos/yangl326-Dylan/agentkeeper/releases/latest`
- Header：`Accept: application/vnd.github+json`、`User-Agent: AgentKeeper/<current>`
- 15 秒超时；非 200、坏 JSON、无 `AgentKeeper-app-macos.zip` 资产 → 可读错误
- 资产 URL 必须 `https` 且 host 为 `github.com` 或 `*.githubusercontent.com`

错误统一为 `UpdateError`（网络 / HTTP 状态 / 缺资产 / 非法资产 URL / 版本非法 / 下载失败 / 校验失败 / 安装失败 / 目录不可写 / 非 App Bundle）。

### 3. 安装器 `AppUpdateInstaller.swift`

流程：

1. `URLSession.download` 下载 zip 到临时目录
2. `ditto -x -k` 解压，定位 `AgentKeeper.app`
3. 校验解压产物的 `CFBundleShortVersionString` **等于**远端版本，`CFBundleIdentifier` 为 `app.agentkeeper.mac`
4. `xattr -dr com.apple.quarantine` + `codesign --force --deep --sign -`（保持 ad-hoc 可启动）
5. 写后台 shell 脚本并启动：
   - 等待当前 PID 退出（最多 30 秒）
   - 旧 `.app` 移到备份
   - 复制新 `.app` 到原路径；失败则回滚备份
   - 成功后 `open` 新 App、清理备份与临时目录
6. 调用方 `NSApplication.shared.terminate(nil)`

替换目标为 `Bundle.main.bundleURL`；父目录不可写时直接失败并提示「打开 Release 页面」。
开发态（非 `.app`）只允许检查，不显示安装按钮。

脚本路径一律做单引号转义；备份与临时目录放在 `FileManager.temporaryDirectory`。

### 4. 状态机 `UpdateModel`（`Sources/AppCore/UpdateModel.swift`）

`@MainActor @Observable`，状态：

```swift
enum UpdateState {
    case idle
    case checking
    case upToDate(AppVersion)
    case available(ReleaseInfo)
    case downloading(ReleaseInfo)
    case installing(ReleaseInfo)
    case failed(String)
}
```

- 仅手动触发：`check()` / `install()`
- 依赖注入：`ReleaseFetching`、`UpdateDownloading`、`AppUpdateInstaller`，便于测试
- 失败保留可重试状态与 Release 页面 URL
- 不做启动检查、不做定时检查、不写任何角标

### 5. 设置页 UI（`AppSettingsView.swift`）

新增「关于 / 更新」Section：

- `AgentKeeper <当前版本>`
- 「检查更新」按钮（checking / downloading / installing 时禁用）
- 状态行：
  - `upToDate` → 「当前已是最新版本。」
  - `available` → 「发现新版本 X。」+「立即更新」
  - `downloading` / `installing` → 进度指示
  - `failed` → 错误说明 +「打开 Release 页面」
- 文案全部进 `L10n`（中英）

### 6. 测试

| 套件 | 覆盖 |
|---|---|
| `AppVersionTests` | `v` 前缀、位数不同、相等、预发布后缀、非法输入 |
| `UpdateServiceTests` | JSON 解码、资产选择、缺资产、非 200、非法 host、版本比较 |
| `UpdateInstallerTests` | 版本/标识校验、脚本包含等待/回滚/重启、路径转义、不可写拒绝 |
| `UpdateModelTests` | idle → checking → upToDate / available；失败可重试；安装失败回到 failed |

真实更新链路在发版后手工验收（旧版 App 检查到新 Release → 更新 → 重启后版本变化）。

## 非目标（YAGNI）

自动/定时检查、红点/角标/弹窗、增量更新、预发布通道、Sparkle、CLI 升级、正式签名/公证。
