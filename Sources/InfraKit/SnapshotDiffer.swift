import Foundation
import DomainKit

/// 单文件差异。
public struct FileDiffEntry: Hashable, Sendable {
    public var relativePath: String
    /// 变更前内容（modified/removed 时为原内容；added 时 nil）。
    public var beforeContent: String?
    /// 变更后内容（modified/added 时为新内容；removed 时 nil）。
    public var afterContent: String?
}

/// 两个快照（或快照 vs 当前目录）之间的差异。
public struct SnapshotDiff: Hashable, Sendable {
    public var added: [FileDiffEntry]
    public var modified: [FileDiffEntry]
    /// 删除以路径清单呈现（内容不可恢复展示无意义）。
    public var removed: [String]

    public var isEmpty: Bool {
        added.isEmpty && modified.isEmpty && removed.isEmpty
    }
}

/// 快照差异计算：按相对路径对齐、逐文件字节级比较（hidden/临时文件豁免与指纹规则一致）。
public enum SnapshotDiffer {
    public static func diff(before: URL, after: URL) throws -> SnapshotDiff {
        let beforeFiles = try relativeFiles(of: before)
        let afterFiles = try relativeFiles(of: after)

        var added: [FileDiffEntry] = []
        var modified: [FileDiffEntry] = []
        var removed: [String] = []

        for (path, url) in afterFiles {
            if let oldURL = beforeFiles[path] {
                let oldData = try Data(contentsOf: oldURL)
                let newData = try Data(contentsOf: url)
                if oldData != newData {
                    modified.append(FileDiffEntry(
                        relativePath: path,
                        beforeContent: String.bytesToText(oldData),
                        afterContent: String.bytesToText(newData)
                    ))
                }
            } else {
                added.append(FileDiffEntry(
                    relativePath: path,
                    beforeContent: nil,
                    afterContent: String.bytesToText(try Data(contentsOf: url))
                ))
            }
        }
        for path in beforeFiles.keys where afterFiles[path] == nil {
            removed.append(path)
        }
        return SnapshotDiff(
            added: added.sorted { $0.relativePath < $1.relativePath },
            modified: modified.sorted { $0.relativePath < $1.relativePath },
            removed: removed.sorted()
        )
    }

    /// 相对路径 → URL；跳过 hidden（与指纹规则保持一致，临时写文件不打扰 diff）。
    private static func relativeFiles(of directory: URL) throws -> [String: URL] {
        var result: [String: URL] = [:]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: []
        )
        let basePath = directory.standardizedFileURL.path
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            guard values?.isRegularFile == true, values?.isHidden != true else { continue }
            let filePath = url.standardizedFileURL.path
            var relative = filePath
            if relative.hasPrefix(basePath) {
                relative = String(relative.dropFirst(basePath.count))
            } else {
                relative = url.lastPathComponent
            }
            relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            result[relative] = url
        }
        return result
    }
}

private extension String {
    /// 字节内容转展示文本；无法按 UTF-8 解码时给出占位说明。
    static func bytesToText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? "（二进制内容）"
    }
}
