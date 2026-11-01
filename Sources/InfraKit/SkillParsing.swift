import Foundation
import CryptoKit
import DomainKit

// MARK: - Frontmatter 解析（SKILL.md YAML-lite）

public enum FrontmatterParser {
    /// 解析 SKILL.md 前置 `---` 块中 name/description（行级处理，容忍缩进与引号）。
    public static func parse(markdown: String) -> (name: String?, description: String?) {
        guard markdown.hasPrefix("---") else { return (nil, nil) }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeFirst() // "---"
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (nil, nil)
        }
        var name: String?
        var description: String?
        for line in lines[..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if name == nil, trimmed.hasPrefix("name:") {
                name = valueAfter("name:", in: trimmed)
            } else if description == nil, trimmed.hasPrefix("description:") {
                description = valueAfter("description:", in: trimmed)
            }
        }
        return (name, description)
    }

    private static func valueAfter(_ key: String, in line: String) -> String? {
        var value = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        } else if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}

// MARK: - 内容指纹

/// 进程级目录指纹缓存：以「相对路径 + mtime + size」签名为目录做 memoize。
/// 纯缓存（不改输出语义）：签名匹配 → 直接复用上次全量流式哈希，
/// 免读盘免哈希（只剩枚举 + stat）；内容/mtime/任何签名分量变化 → 全量重算。
public final class FingerprintStatCache: @unchecked Sendable {
    private struct Stat: Hashable {
        var relativePath: String
        var mtime: Double
        var size: Int
    }

    private struct Entry {
        var signature: [Stat]
        var sha256: String?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    /// 针对枚举产物（相对路径有序）与本次统计签名匹配则返回缓存 sha。
    func hit(
        directoryPath: String,
        signature: [(relativePath: String, mtime: Double, size: Int)]
    ) -> String? {
        let key = makeKey(signature: signature)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[directoryPath], entry.signature == key else { return nil }
        return entry.sha256
    }

    /// 任一文件读取失败即不落缓存（避免把撕裂读当真值缓存）。
    func miss(
        directoryPath: String,
        signature: [(relativePath: String, mtime: Double, size: Int)],
        sha256: String?
    ) {
        let key = makeKey(signature: signature)
        lock.lock()
        defer { lock.unlock() }
        entries[directoryPath] = Entry(signature: key, sha256: sha256)
    }

    private func makeKey(
        signature: [(relativePath: String, mtime: Double, size: Int)]
    ) -> [Stat] {
        var result: [Stat] = []
        result.reserveCapacity(signature.count)
        for stat in signature {
            result.append(
                Stat(
                    relativePath: stat.relativePath,
                    mtime: stat.mtime,
                    size: stat.size
                )
            )
        }
        return result
    }
}

public struct DirectoryFingerprint {
    /// 目录为空（无参与哈希的常规文件）时为 nil——与空目录语义一致。
    public var sha256: String?
    /// 参与哈希的常规文件（相对路径有序）。
    public var regularFiles: [URL]

    public init(sha256: String?, regularFiles: [URL]) {
        self.sha256 = sha256
        self.regularFiles = regularFiles
    }
}

public enum Fingerprint {
    /// 进程级共享缓存（目录级 memoize）。
    private static let cache = FingerprintStatCache()

    /// 清空进程级缓存（测试隔离与读写冲突后的一致性兜底）。
    public static func clearCache() {
        cache.clear()
    }

    /// 对一组文件（相对路径+内容哈希）的规范化组合做 SHA256；
    /// 覆盖按"文件树"语义：路径或内容任一变化都会改变指纹。
    public static func sha256OfFiles(_ files: [(relativePath: String, data: Data)]) -> String {
        var hasher = SHA256()
        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0x00]))
            hasher.update(data: file.data)
            hasher.update(data: Data([0x00]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 读入目录内所有常规文件并计算整树指纹（跳过隐藏与符号链接）。
    public static func sha256OfDirectory(_ directory: URL) -> String? {
        fingerprint(of: directory).sha256
    }

    /// 单遍目录指纹：一次枚举同时产出文件清单与（缓存感知的）整树哈希。
    /// 已修掉的旧口：枚举后把每个文件的**全部字节**攒进内存再哈希；现在是
    /// 每文件 64KB 分块流式 SHA256，栈上无 Data 堆积；命中进程级缓存时连哈希都省。
    public static func fingerprint(of directory: URL) -> DirectoryFingerprint {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey,
                .contentModificationDateKey, .fileSizeKey
            ],
            options: [],
            errorHandler: nil
        ) else {
            return DirectoryFingerprint(sha256: nil, regularFiles: [])
        }

        var files: [(url: URL, relative: String, mtime: Double, size: Int)] = []
        // 与 legacy 逐字节一致：raw path 判前缀（枚举 URL 可能被解析出 /private 前缀，
        // 与 raw 基路径失配 → 历史行为是回退 basename；保持不变以保护已持久化指纹比对）。
        let rawBase = directory.path
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey,
                .contentModificationDateKey, .fileSizeKey
            ]),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.isHidden != true,
                  let mtime = values.contentModificationDate?.timeIntervalSince1970,
                  let size = values.fileSize
            else { continue }
            let relative: String
            if url.path.hasPrefix(rawBase) {
                relative = String(url.path.dropFirst(rawBase.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relative = url.lastPathComponent
            }
            files.append((url, relative, mtime, size))
        }
        // 签名与组合序都要求确定性：relative 同名（不同目录）用完整路径破平。
        files.sort {
            $0.relative != $1.relative ? $0.relative < $1.relative : $0.url.path < $1.url.path
        }
        let sortedFiles = files.map(\.url)
        let signature = files.map { ($0.relative, $0.mtime, $0.size) }

        let directoryPath = directory.standardizedFileURL.path
        if let cached = cache.hit(directoryPath: directoryPath, signature: signature) {
            return DirectoryFingerprint(sha256: cached, regularFiles: sortedFiles)
        }

        var hasher = SHA256()
        var readCount = 0
        for file in files {
            // 打开失败/读取中断：跳过该条目（旧语义），且不落缓存（避免撕裂读当真值）
            var fileHasher = hasher
            fileHasher.update(data: Data(file.relative.utf8))
            fileHasher.update(data: Data([0x00]))
            if streamHasher(for: file.url, into: &fileHasher) {
                hasher = fileHasher
                hasher.update(data: Data([0x00]))
                readCount += 1
            }
        }
        guard readCount > 0 else {
            return DirectoryFingerprint(sha256: nil, regularFiles: sortedFiles)
        }
        let sha = hasherHex(hasher)
        if readCount == files.count {
            cache.miss(
                directoryPath: directoryPath,
                signature: signature,
                sha256: sha
            )
        }
        return DirectoryFingerprint(sha256: sha, regularFiles: sortedFiles)
    }

    private static func hasherHex(_ hasher: SHA256) -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 逐文件 64KB 分块流式哈希（内容直接进共享 hasher：读取字节本身，不落内存聚合）。
    private static func streamHasher(for url: URL, into hasher: inout SHA256) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let chunkSize = 65_536
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return true
    }
}

// MARK: - 共享的 skill 解析（adapter 复用）

public enum SkillParsing {
    /// 判断目录是否是 skill：含 SKILL.md 即是；解析 frontmatter 与文件清单一并返回。
    /// 文件清单与指纹共用一次枚举（fingerprint 内部顺带产出有序文件列表）。
    public static func parseDirectory(_ directory: URL) -> ParsedSkill? {
        let fileManager = FileManager.default
        let skillMd = directory.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillMd.path) else { return nil }
        let markdown = (try? String(contentsOf: skillMd, encoding: .utf8)) ?? ""
        let parsedFront = FrontmatterParser.parse(markdown: markdown)
        let fingerprint = Fingerprint.fingerprint(of: directory)
        return ParsedSkill(
            directory: directory,
            frontmatterName: parsedFront.name,
            frontmatterDescription: parsedFront.description,
            files: fingerprint.regularFiles,
            sha256: fingerprint.sha256 ?? ""
        )
    }

    /// 递归收集目录内全部常规文件（跳过隐藏与符号链接）。
    public static func allRegularFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.isHidden != true
            else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// 把任意 skillID 变成文件系统安全的目录键（内容哈希，防路径注入/超长）。
    static func directoryKey(for skillID: String) -> String {
        let digest = SHA256.hash(data: Data(skillID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24) + ""
    }
}
