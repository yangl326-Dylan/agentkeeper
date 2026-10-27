import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct ClaudeProjectRootDiscoveryTests {
    @Test func discoversProjectRootsFromClaudeJSONAndFiltersMissing() async {
        let home = makeFakeHome(files: [
            "code/atlas/SKILL.md",
            "code/notes/README.md",
        ])
        defer { cleanup(home) }
        let atlasPath = home.appendingPathComponent("code/atlas", isDirectory: true).path
        let notesPath = home.appendingPathComponent("code/notes", isDirectory: true).path
        let vanishedPath = home.appendingPathComponent("code/vanished", isDirectory: true).path
        let json = #"{"projects": {"\#(atlasPath)": {}, "\#(notesPath)": {}, "\#(vanishedPath)": {}}}"#
        try? json.write(
            to: home.appendingPathComponent(".claude.json"),
            atomically: true,
            encoding: .utf8
        )
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let roots = await adapter.discoverProjectRoots()
        let paths = Set(roots.map(\.path.path))
        #expect(paths.contains(atlasPath))
        #expect(paths.contains(notesPath))
        #expect(!paths.contains(vanishedPath))
    }
}

@Suite struct ScanScopeStoreTests {
    @Test func addAndPersistUserProjectRoots() throws {
        let base = makeFakeHome(files: [])
        defer { cleanup(base) }
        let store = try ScanScopeStore(directory: base)
        let root = ProjectRoot(path: base.appendingPathComponent("code/atlas", isDirectory: true))
        try store.addProjectRoot(root)
        // 重新加载验证持久化
        let reloaded = try ScanScopeStore(directory: base)
        #expect(reloaded.userProjectRoots().contains(root))
    }

    @Test func removeProjectRoot() throws {
        let base = makeFakeHome(files: [])
        defer { cleanup(base) }
        var store = try ScanScopeStore(directory: base)
        let root = ProjectRoot(path: "/Users/x/code/atlas")
        try store.addProjectRoot(root)
        try store.removeProjectRoot(root)
        #expect(store.userProjectRoots().isEmpty)
    }

    @Test func duplicateAddIsIdempotent() throws {
        let base = makeFakeHome(files: [])
        defer { cleanup(base) }
        let store = try ScanScopeStore(directory: base)
        let root = ProjectRoot(path: "/Users/x/code/atlas")
        try store.addProjectRoot(root)
        try store.addProjectRoot(root)
        #expect(store.userProjectRoots().count == 1)
    }

    @Test func corruptedFileFallsBackToEmpty() throws {
        let base = makeFakeHome(files: ["scan-scope.json"])
        defer { cleanup(base) }
        try "not json at all!".write(to: base.appendingPathComponent("scan-scope.json"), atomically: true, encoding: .utf8)
        let store = try ScanScopeStore(directory: base)
        #expect(store.userProjectRoots().isEmpty)
    }
}

@Suite struct ProjectRootScannerTests {
    @Test func enumeratesAgentSkillDirsInsideProjectRoot() throws {
        // 项目根内的各 agent skill 目录候选
        let project = makeFakeHome(files: [
            ".claude/skills/one/SKILL.md",
            ".claude/skills/two/SKILL.md",
        ])
        defer { cleanup(project) }
        let root = ProjectRoot(path: project)
        let scanner = ProjectRootScanner()
        let roots = scanner.skillRoots(inProjectRoot: root)
        let claudeRoot = roots.first { $0.owners == ["claude-code"] }
        #expect(claudeRoot != nil)
        #expect(claudeRoot?.level == .project(root))
    }

    @Test func noCandidatesMeansNoRoots() {
        let root = ProjectRoot(path: URL(fileURLWithPath: "/nonexistent-project"))
        let scanner = ProjectRootScanner()
        #expect(scanner.skillRoots(inProjectRoot: root).isEmpty)
    }
}
