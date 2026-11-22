// swift-tools-version: 6.0
import PackageDescription

// 平台纪律：本清单零 os 条件分支（条件编译下沉到源文件级 guard）。
// 原因：清单内 `#if` 要求 SwiftPM 以 `env -i` 子进程探测编译器求值条件，
// 该探测在部分环境（受限沙箱/精简容器）静默失败，导致整个包静默空构建。
// macOS 专属目标（GUI）的源文件统一用 `#if os(macOS)` 文件级守卫，Linux 上编为空模块。
let package = Package(
    name: "AgentKeeper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AgentKeeper", targets: ["AgentKeeper"]),
        .executable(name: "ak", targets: ["ak"]),
    ],
    dependencies: [
        // sha256 指纹统一实现（Apple 官方维护，Linux 官方支持；macOS 侧由 CryptoKit 转发）。
        .package(url: "https://github.com/apple/swift-crypto", from: "3.10.0"),
        // Linux GUI 栈（SwiftCrossUI + Gtk3Backend；add-linux-app 决策 3）。
        // 依赖无条件声明（平台纪律：清单零 os 分支）；Gtk3Backend 在 macOS 也参与构建（CI 装 GTK3 头文件）。
        // 选 Gtk3Backend 而非 GtkBackend：AppIndicator 托盘库（libayatana-appindicator3）
        // 只支持 GTK3，GTK4 进程内再 dlopen GTK3 会类型注册冲突（GtkWidget critical）。
        .package(url: "https://github.com/moreSwift/swift-cross-ui", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "DomainKit"
        ),
        .target(
            name: "InfraKit",
            dependencies: [
                "DomainKit",
                "CSQLite3",
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        // SQLite3 C 绑定 shim：Apple 平台用 SDK 内建 SQLite3 模块；Linux 用系统 libsqlite3（pkg-config）。
        .systemLibrary(
            name: "CSQLite3",
            path: "Sources/CSQLite3",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "AppCore",
            dependencies: ["DomainKit", "InfraKit"]
        ),
        // 共享展示层（平台无关）：环境组装根、展示模型、设置存储、Markdown 块解析。
        // 平台行为经 PlatformAdapter 注入；本目标零 os 分支、零 AppKit/SwiftUI import。
        .target(
            name: "AgentKeeperShared",
            dependencies: ["AppCore", "DomainKit", "InfraKit"]
        ),
        .target(
            name: "AgentKeeperUI",
            dependencies: ["AgentKeeperShared", "AppCore", "DomainKit", "InfraKit"]
        ),
        // Linux GUI 栈（SCUI 视图 + LinuxPlatformAdapter）。源文件整文件 `#if os(Linux)` 守卫，
        // macOS 上编为空模块（与 AgentKeeperUI 的整文件 `#if os(macOS)` 对称）。
        .target(
            name: "AgentKeeperUILinux",
            dependencies: [
                "AgentKeeperShared",
                "AppCore",
                "DomainKit",
                "InfraKit",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "Gtk3Backend", package: "swift-cross-ui"),
            ]
        ),
        .executableTarget(
            name: "AgentKeeper",
            dependencies: [
                "AgentKeeperShared",
                "AgentKeeperUI",
                "AgentKeeperUILinux",
                "AppCore",
                "DomainKit",
                "InfraKit",
            ]
        ),
        .executableTarget(
            name: "ak",
            dependencies: ["AppCore", "DomainKit", "InfraKit"]
        ),
        .testTarget(
            name: "DomainKitTests",
            dependencies: ["DomainKit"]
        ),
        .testTarget(
            name: "InfraKitTests",
            dependencies: ["InfraKit", "DomainKit"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "DomainKit", "InfraKit"]
        ),
        .testTarget(
            name: "AgentKeeperTests",
            dependencies: [
                "AgentKeeperShared",
                "AgentKeeperUI",
                "AgentKeeperUILinux",
                "AppCore",
                "DomainKit",
                "InfraKit",
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
