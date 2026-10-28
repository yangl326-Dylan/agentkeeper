// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentKeeper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AgentKeeper", targets: ["AgentKeeper"])
    ],
    targets: [
        .target(
            name: "DomainKit"
        ),
        .target(
            name: "InfraKit",
            dependencies: ["DomainKit"]
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
