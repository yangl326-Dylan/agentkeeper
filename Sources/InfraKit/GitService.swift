import Foundation
import DomainKit

/// 单条提交记录。
public struct GitCommit: Hashable, Sendable {
    public var hash: String
    public var subject: String
    public var isoDate: String
}

/// Git CLI 封装（设计 D4）：`git log --porcelain` 解析 + `git diff`。
/// 非 git 目录一律体面返回空集，不抛错。版本嗅探用于跨 git 版本容错。
public enum GitServiceError: Error, Hashable {
    case notGitRepository(path: String)
    case gitNotFound
}

public struct GitService: @unchecked Sendable {
    /// git 可执行文件绝对路径（默认 /usr/bin/git；可注入 brew git 做跨版本测试）。
    /// 注入路径不可执行时按 PATH 逐目录探测回退（Linux 发行版 git 常在 /usr/bin 之外的 PATH 位置）。
    private let gitExecutablePath: String
    private let fileManager: FileManager

    public init(gitExecutablePath: String = "/usr/bin/git", fileManager: FileManager = .default) {
        self.gitExecutablePath = Self.resolveGitPath(injected: gitExecutablePath, fileManager: fileManager)
        self.fileManager = fileManager
    }

    /// 解析实际可用的 git 路径：注入路径可用即用；否则按 PATH 环境变量逐目录探测名为 `git` 的可执行文件；都不可用则原样返回（调用侧有体面降级）。
    private static func resolveGitPath(injected: String, fileManager: FileManager) -> String {
        if fileManager.isExecutableFile(atPath: injected) { return injected }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = String(directory).appendingPathComponent("git")
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return injected
    }

    // MARK: - 版本嗅探

    /// `git --version` 输出首行（如 "git version 2.39.2 (Apple Git-143)"）；不可用时 nil。
    public func version() -> String? {
        guard let result = run(["--version"], from: nil) else { return nil }
        guard let text = String(data: result, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").first.map(String.init)
    }

    // MARK: - 历史查询

    /// 最近提交（porcelain 输出解析，最新在前）。非 git 目录返回 []。
    public func history(directory: URL, limit: Int = 20) -> [GitCommit] {
        guard isGitRepository(directory: directory) else { return [] }
        guard let result = run([
            "log", "--pretty=medium", String(format: "--max-count=%d", max(1, limit)),
        ], from: directory) else { return [] }
        return Self.parsePorcelain(result)
    }

    /// 解析 `git log --pretty=medium`（形状与 porcelain 一致：commit / AuthorDate / 缩进消息行）。
    static func parsePorcelain(_ data: Data) -> [GitCommit] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var commits: [GitCommit] = []
        var hash: String?
        var date: String?
        var message: [String] = []

        func flush() {
            let unwrappedHash = hash
            if let unwrappedHash, let subject = message.first {
                commits.append(GitCommit(hash: unwrappedHash, subject: subject, isoDate: date ?? ""))
            }
            hash = nil
            date = nil
            message = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            if rawLine.hasPrefix("commit ") {
                flush()
                hash = String(rawLine.dropFirst("commit ".count))
            } else if rawLine.hasPrefix("AuthorDate:") {
                date = Self.afterColon(rawLine)
            } else if rawLine.hasPrefix("    ") {
                message.append(String(rawLine.dropFirst(4)))
            }
        }
        flush()
        return commits
    }

    private static func afterColon(_ line: String) -> String {
        guard let index = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - diff

    /// 未提交改动 diff（干净或非 git 目录返回空串，不抛错）。
    public func uncommittedDiff(directory: URL) -> String {
        guard isGitRepository(directory: directory) else { return "" }
        guard let result = run(["diff", "--"], from: directory) else { return "" }
        return String(data: result, encoding: .utf8) ?? ""
    }

    // MARK: - 内部

    func isGitRepository(directory: URL) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    /// 运行 git 子命令；失败返回 nil。stdout+stderr 合并读取至 EOF（MVP 不做超时）。
    private func run(_ arguments: [String], from directory: URL?) -> Data? {
        let process = Process()
        guard FileManager.default.isExecutableFile(atPath: gitExecutablePath) else { return nil }
        process.executableURL = URL(fileURLWithPath: gitExecutablePath)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // 任意退出码都返回输出（diff 的"1=有差异"、log 的错误），由调用方按需甄别
        return data
    }
}
