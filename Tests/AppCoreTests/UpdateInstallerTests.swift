import Foundation
import Testing
@testable import AppCore

/// 安装器：暂存 App 校验、替换脚本（等待 PID / 备份 / 回滚 / 重启）、目标可写性。
@Suite struct UpdateInstallerTests {
    private func makeApp(
        at root: URL,
        name: String = "AgentKeeper",
        version: String = "0.3.0",
        bundleID: String = "app.agentkeeper.mac"
    ) -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": version,
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": name,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-installer-test-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func verifiesMatchingStagedApp() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(at: root)
        try AppUpdateInstaller.verifyStagedApp(at: app, expectedVersion: AppVersion("0.3.0")!)
    }

    @Test func rejectsVersionMismatch() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(at: root, version: "0.2.9")
        #expect(throws: UpdateError.self) {
            try AppUpdateInstaller.verifyStagedApp(at: app, expectedVersion: AppVersion("0.3.0")!)
        }
    }

    @Test func rejectsWrongBundleIdentifier() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(at: root, bundleID: "com.example.evil")
        #expect(throws: UpdateError.self) {
            try AppUpdateInstaller.verifyStagedApp(at: app, expectedVersion: AppVersion("0.3.0")!)
        }
    }

    @Test func rejectsMissingInfoPlist() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Empty.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        #expect(throws: UpdateError.self) {
            try AppUpdateInstaller.verifyStagedApp(at: app, expectedVersion: AppVersion("0.3.0")!)
        }
    }

    @Test func scriptWaitsForExitThenSwapsAndRestarts() {
        let script = AppUpdateInstaller.makeScript(
            target: URL(fileURLWithPath: "/Applications/AgentKeeper.app"),
            staged: URL(fileURLWithPath: "/tmp/staged/AgentKeeper.app"),
            backup: URL(fileURLWithPath: "/tmp/staged/AgentKeeper.app.backup"),
            workDirectory: URL(fileURLWithPath: "/tmp/staged"),
            pid: 4242
        )
        #expect(script.contains("kill -0 \"$PID\""))
        #expect(script.contains("exit 12"))
        #expect(script.contains("mv \"$TARGET\" \"$BACKUP\""))
        #expect(script.contains("ditto \"$STAGED\" \"$TARGET\""))
        #expect(script.contains("rm -rf \"$BACKUP\""))
        #expect(script.contains("/usr/bin/open \"$TARGET\""))
        #expect(script.contains("exit 11"))
    }

    @Test func scriptQuotesPathsWithSpacesAndApostrophes() {
        let script = AppUpdateInstaller.makeScript(
            target: URL(fileURLWithPath: "/tmp/A B's.app"),
            staged: URL(fileURLWithPath: "/tmp/staged/AgentKeeper.app"),
            backup: URL(fileURLWithPath: "/tmp/backup.app"),
            workDirectory: URL(fileURLWithPath: "/tmp/staged"),
            pid: 1
        )
        #expect(script.contains("TARGET='/tmp/A B'\\''s.app'"))
    }

    @Test func rejectsNonAppBundleTarget() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let installer = AppUpdateInstaller(currentBundleURL: root.appendingPathComponent("ak"))
        let release = ReleaseInfo(
            version: AppVersion("0.3.0")!,
            tag: "v0.3.0",
            releaseURL: URL(string: "https://github.com/x/y/releases/tag/v0.3.0")!,
            appAssetURL: URL(string: "https://github.com/x/y/app.zip")
        )
        #expect(throws: UpdateError.self) {
            try installer.install(release: release, zipURL: root.appendingPathComponent("x.zip"))
        }
    }

    @Test func rejectsReadOnlyTargetParent() throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = makeApp(at: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        let installer = AppUpdateInstaller(currentBundleURL: app)
        let release = ReleaseInfo(
            version: AppVersion("0.3.0")!,
            tag: "v0.3.0",
            releaseURL: URL(string: "https://github.com/x/y/releases/tag/v0.3.0")!,
            appAssetURL: URL(string: "https://github.com/x/y/app.zip")
        )
        #expect(throws: UpdateError.targetNotWritable(root.path)) {
            try installer.install(release: release, zipURL: root.appendingPathComponent("x.zip"))
        }
    }
}
