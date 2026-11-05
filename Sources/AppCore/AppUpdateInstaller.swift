import Foundation

/// 安装接口（测试注入 fake；真实实现替换当前 App Bundle）。
public protocol AppInstalling: Sendable {
    func install(release: ReleaseInfo, zipURL: URL) throws
}

/// 原地更新安装器。
///
/// 步骤：解压 → 校验版本/标识 → 去 quarantine + ad-hoc 重签 → 启动后台脚本。
/// 脚本等待当前进程退出后替换 `.app`，失败自动回滚并重新打开旧版本。
public struct AppUpdateInstaller: AppInstalling, Sendable {
    public static let bundleIdentifier = "app.agentkeeper.mac"
    public static let expectedAppName = "AgentKeeper.app"

    /// 要替换的 App Bundle（默认当前运行中的 App）。
    private let currentBundleURL: URL

    public init(currentBundleURL: URL = Bundle.main.bundleURL) {
        self.currentBundleURL = currentBundleURL
    }

    public func install(release: ReleaseInfo, zipURL: URL) throws {
        let fileManager = FileManager.default
        guard currentBundleURL.pathExtension.lowercased() == "app" else {
            throw UpdateError.notAnAppBundle(currentBundleURL.path)
        }
        let targetParent = currentBundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: targetParent.path) else {
            throw UpdateError.targetNotWritable(targetParent.path)
        }

        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("agentkeeper-install-\(UUID().uuidString)", isDirectory: true)
        let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        } catch {
            throw UpdateError.installationFailed(error.localizedDescription)
        }

        try run(
            "/usr/bin/ditto",
            ["-x", "-k", zipURL.path, extracted.path],
            onFailure: UpdateError.unzipFailed
        )

        let stagedApp = extracted.appendingPathComponent(Self.expectedAppName, isDirectory: true)
        guard fileManager.fileExists(atPath: stagedApp.path) else {
            throw UpdateError.unzipFailed("更新包内未找到 \(Self.expectedAppName)")
        }

        try Self.verifyStagedApp(at: stagedApp, expectedVersion: release.version)
        // 下载来源不可控属性清理与重签；失败不阻断（未签名也能本地运行）
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path], onFailure: UpdateError.installationFailed)
        try? run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", stagedApp.path], onFailure: UpdateError.installationFailed)

        let backup = currentBundleURL.deletingLastPathComponent()
            .appendingPathComponent(".\(Self.expectedAppName).backup-\(UUID().uuidString)", isDirectory: true)
        let script = Self.makeScript(
            target: currentBundleURL,
            staged: stagedApp,
            backup: backup,
            workDirectory: workDirectory,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        let scriptURL = workDirectory.appendingPathComponent("update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw UpdateError.installationFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.installationFailed(error.localizedDescription)
        }
    }

    // MARK: - 校验

    /// 暂存 App 必须与远端版本一致，且 Bundle ID 正确（防止资产错配/替换错误 App）。
    static func verifyStagedApp(at appURL: URL, expectedVersion: AppVersion) throws {
        let plistURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard let data = FileManager.default.contents(atPath: plistURL.path),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let info = propertyList as? [String: Any]
        else {
            throw UpdateError.verificationFailed("缺少或无法读取 Info.plist")
        }
        guard let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID == bundleIdentifier
        else {
            throw UpdateError.verificationFailed("Bundle ID 不匹配")
        }
        guard let rawVersion = info["CFBundleShortVersionString"] as? String,
              let version = AppVersion(rawVersion)
        else {
            throw UpdateError.verificationFailed("缺少可解析的版本号")
        }
        guard version == expectedVersion else {
            throw UpdateError.verificationFailed("版本不匹配：期望 \(expectedVersion)，实际 \(version)")
        }
    }

    // MARK: - 替换脚本

    /// 生成后台替换脚本：等待 PID 退出 → 备份 → 复制 → 失败回滚 → 重启。
    static func makeScript(
        target: URL,
        staged: URL,
        backup: URL,
        workDirectory: URL,
        pid: Int32
    ) -> String {
        """
        #!/bin/sh
        set -u
        PID=\(pid)
        TARGET=\(shellQuote(target.path))
        STAGED=\(shellQuote(staged.path))
        BACKUP=\(shellQuote(backup.path))
        WORK=\(shellQuote(workDirectory.path))

        i=0
        while kill -0 "$PID" 2>/dev/null; do
          i=$((i + 1))
          if [ "$i" -ge 150 ]; then
            exit 12
          fi
          sleep 0.2
        done

        rm -rf "$BACKUP"
        if ! mv "$TARGET" "$BACKUP"; then
          exit 10
        fi

        if /usr/bin/ditto "$STAGED" "$TARGET"; then
          /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
          /usr/bin/codesign --force --deep --sign - "$TARGET" >/dev/null 2>&1 || true
          /usr/bin/open "$TARGET"
          rm -rf "$BACKUP"
          rm -rf "$WORK"
        else
          rm -rf "$TARGET"
          mv "$BACKUP" "$TARGET"
          /usr/bin/open "$TARGET"
          exit 11
        fi
        """
    }

    /// POSIX 单引号转义（路径可能含空格/引号）。
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - 进程

    private func run(
        _ executable: String,
        _ arguments: [String],
        onFailure: (String) -> UpdateError
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw onFailure(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw onFailure("\(executable) 退出码 \(process.terminationStatus)")
        }
    }
}
