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

public enum Fingerprint {
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
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: nil
        ) else { return nil }

        var collected: [(relativePath: String, data: Data)] = []
        let basePath = directory.path
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, values.isHidden != true
            else { continue }
            // 相对路径必须基于同一路径表示形式；枚举器返回异常前缀时退回文件名
            let relative: String
            if url.path.hasPrefix(basePath) {
                relative = String(url.path.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relative = url.lastPathComponent
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            collected.append((relative, data))
        }
        guard !collected.isEmpty else { return nil }
        return sha256OfFiles(collected)
    }
}

// MARK: - 共享的 skill 解析（adapter 复用）

public enum SkillParsing {
    /// 判断目录是否是 skill：含 SKILL.md 即是；解析 frontmatter 与文件清单一并返回。
    public static func parseDirectory(_ directory: URL) -> ParsedSkill? {
        let fileManager = FileManager.default
        let skillMd = directory.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillMd.path) else { return nil }
        let markdown = (try? String(contentsOf: skillMd, encoding: .utf8)) ?? ""
        let parsedFront = FrontmatterParser.parse(markdown: markdown)
        return ParsedSkill(
            directory: directory,
            frontmatterName: parsedFront.name,
            frontmatterDescription: parsedFront.description,
            files: allRegularFiles(in: directory),
            sha256: Fingerprint.sha256OfDirectory(directory) ?? ""
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
}
