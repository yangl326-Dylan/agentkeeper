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
        .target(
            name: "AgentKeeperUI",
            dependencies: ["AppCore", "DomainKit", "InfraKit"]
        ),
        .executableTarget(
            name: "AgentKeeper",
            dependencies: ["AgentKeeperUI", "AppCore", "DomainKit", "InfraKit"]
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
            dependencies: ["AgentKeeperUI", "AppCore", "DomainKit", "InfraKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
