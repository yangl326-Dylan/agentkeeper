import Foundation
import DomainKit

/// git 来源物化器（design D3）：
/// - 本地路径（裸路径 / file://）直接复用为只读源，不 clone；
/// - 远程 URL 用 `git clone --depth 1` 到 `base/tmp/clone-<uuid>`，超时 60s 默认；
/// - 失败（含超时）清理临时目录并抛 `DistributionError`，stderr 摘要透传。
public struct GitInstaller: Sendable {
    private let baseDirectory: URL
    private let timeout: TimeInterval
    private let gitExecutablePath: String

    public init(
        baseDirectory: URL,
        timeout: TimeInterval = 60,
        gitExecutablePath: String = "/usr/bin/git"
    ) {
        self.baseDirectory = baseDirectory
        self.timeout = timeout
        self.gitExecutablePath = gitExecutablePath
    }

    /// 把用户提供的来源 URL 物化为一个可读取的目录。
    public func materialize(url raw: String) async throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DistributionError.invalidSource(reason: "git URL 为空")
        }

        // 本地路径（裸路径或 file://）：存在目录即直接复用
        if let localPath = Self.localDirectoryPath(of: trimmed) {
            let directory = URL(fileURLWithPath: localPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw DistributionError.invalidSource(reason: "本地路径不存在或不是目录：\(directory.path)")
            }
            return directory.standardizedFileURL
        }

        // 远程 URL：临时 clone
        let temporaryRoot = temporaryCloneRoot()
        try? FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        do {
            try await clone(url: trimmed, into: temporaryRoot)
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            Self.removeEmptyParentChain(of: temporaryRoot, downTo: baseDirectory)
            throw error
        }
        return temporaryRoot
    }

    /// clone 后的临时根目录（仓库内容直接在此目录，目标即 clone 出的 .git 所在目录）。
    public func temporaryCloneRoot() -> URL {
        baseDirectory.appendingPathComponent("tmp/clone-\(UUID().uuidString)", isDirectory: true)
    }

    /// 清理临时 clone 目录（install 成功后的收尾）。
    public func cleanup(_ directory: URL) {
        // 仅清理属于临时 clone 语义的目录：位于 base/tmp 下才删
        let tmpRoot = baseDirectory.appendingPathComponent("tmp", isDirectory: true)
        guard directory.path.hasPrefix(tmpRoot.path) else { return }
        try? FileManager.default.removeItem(at: directory)
        Self.removeEmptyParentChain(of: directory, downTo: baseDirectory)
    }

    /// 候选发现（design D3）：物化目录内按 skill 识别规则定位候选。
    /// - 仓库根本身合法 → 单候选（名称取仓库目录末段去 .git）；
    /// - 否则扫一级子目录，逐个校验，多候选交上层勾选；
    /// - 零候选不报错（上层转 invalidSource）。
    public func candidates(for repositoryURL: String, in directory: URL) -> [GitSkillCandidate] {
        let fileManager = FileManager.default
        guard let rootParsed = SkillParsing.parseDirectory(directory) else {
            // 根非法 → 一级子目录扫描
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return [] }
            return children
                .filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { child -> GitSkillCandidate? in
                    guard let parsed = SkillParsing.parseDirectory(child) else { return nil }
                    return GitSkillCandidate(
                        repositoryURL: repositoryURL,
                        directory: child.standardizedFileURL,
                        name: child.lastPathComponent,
                        sha256: parsed.sha256
                    )
                }
        }
        let rootName = (directory.lastPathComponent as NSString)
            .replacingOccurrences(of: ".git", with: "")
        return [GitSkillCandidate(
            repositoryURL: repositoryURL,
            directory: directory.standardizedFileURL,
            name: rootName,
            sha256: rootParsed.sha256
        )]
    }

    /// 目录删除后，向上把 Until:base 之间变空的中间目录清掉（保持临时区整洁）。
    private static func removeEmptyParentChain(of directory: URL, downTo: URL) {
        var current = directory.deletingLastPathComponent()
        while current.path.hasPrefix(downTo.path) && current.path != downTo.path {
            let contents = (try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)) ?? []
            guard contents.isEmpty else { break }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    private static func localDirectoryPath(of raw: String) -> String? {
        if raw.hasPrefix("file://") {
            return raw.dropFirst("file://".count).description
        }
        // 裸路径：以 / 或 ~ 开头，或包含磁盘特征的相对路径一律按本地处理，
        // 其余（含 "https://", "git@", "ssh://"）按远程 URL 处理。
        if raw.hasPrefix("/") || raw.hasPrefix("~/") || raw.hasPrefix(".") {
            return (raw as NSString).expandingTildeInPath
        }
        return nil
    }

    private func clone(url: String, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitExecutablePath)
        process.arguments = ["clone", "--depth", "1", url, directory.path]

        var environment = ProcessInfo.processInfo.environment
        // 禁用交互式凭据提示：失败直接报错，不 hang
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DistributionError.cloneFailed(detail: "无法启动 git：\(error)")
        }

        // 等待退出，超时即 kill
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                throw DistributionError.cloneTimeout
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrMessage = String(data: data, encoding: .utf8) ?? ""
            let summary = stderrMessage
                .split(separator: "\n")
                .suffix(3)
                .joined(separator: " / ")
            throw DistributionError.cloneFailed(detail: summary.isEmpty ? "git 退出码 \(process.terminationStatus)" : summary)
        }
    }
}
