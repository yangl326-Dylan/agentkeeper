import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SnapshotDifferTests {
    private func makeVersion(_ root: URL, files: [String: String]) throws {
        for (relative, content) in files {
            let target = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: target, atomically: true, encoding: .utf8)
        }
    }

    @Test func diffClassifiesAddedModifiedRemoved() throws {
        let home = makeFakeHome(files: ["scratch/placeholder"])
        defer { cleanup(home) }
        let v1 = home.appendingPathComponent("v1", isDirectory: true)
        let v2 = home.appendingPathComponent("v2", isDirectory: true)
        try makeVersion(v1, files: [
            "a.md": "old text",
            "deleted.md": "bye",
            "same.txt": "stable",
        ])
        try makeVersion(v2, files: [
            "a.md": "new text",
            "added.md": "welcome",
            "same.txt": "stable",
        ])

        let diff = try SnapshotDiffer.diff(before: v1, after: v2)
        #expect(Set(diff.added.map({ $0.relativePath })) == ["added.md"])
        #expect(Set(diff.modified.map({ $0.relativePath })) == ["a.md"])
        #expect(Set(diff.removed) == ["deleted.md"])
        // unmodified 不出现在任何类别
        #expect(diff.isEmpty == false)
    }

    @Test func identicalVersionsProduceEmptyDiff() throws {
        let home = makeFakeHome(files: ["scratch/placeholder"])
        defer { cleanup(home) }
        let v1 = home.appendingPathComponent("v1", isDirectory: true)
        let v2 = home.appendingPathComponent("v2", isDirectory: true)
        try makeVersion(v1, files: ["nested/deep/x.md": "same"])
        try makeVersion(v2, files: ["nested/deep/x.md": "same"])

        let diff = try SnapshotDiffer.diff(before: v1, after: v2)
        #expect(diff.isEmpty)
    }

    @Test func diffWorksBetweenRecordedSnapshots() throws {
        let home = makeFakeHome(files: ["skills/alpha/SKILL.md"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let skill = home.appendingPathComponent("skills/alpha", isDirectory: true)
        let store = SnapshotStore(baseDirectory: base)
        let first = try store.record(skillID: "alpha|claude-code", directory: skill)
        try "改版内容".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let second = try store.record(skillID: "alpha|claude-code", directory: skill)

        let oldURL = store.snapshotURL(skillID: "alpha|claude-code", sha: first!.sha)
        let newURL = store.snapshotURL(skillID: "alpha|claude-code", sha: second!.sha)
        let diff = try SnapshotDiffer.diff(before: oldURL, after: newURL)
        #expect(diff.modified.count == 1)
        #expect(diff.modified[0].relativePath == "SKILL.md")
        #expect(diff.modified[0].beforeContent != diff.modified[0].afterContent)
    }
}
