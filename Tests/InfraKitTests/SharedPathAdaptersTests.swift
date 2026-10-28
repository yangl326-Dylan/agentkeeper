import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 固定标准路径 adapter（~/.agents 共享目录 / Qwen Code / Cursor）：
/// 常见 agent 安装目录与 skill 目录路径是固定的——这些候选必须覆盖，否则「搜索不全」。
@Suite struct SharedPathAdaptersTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-adapters-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeSkillRoot(_ home: URL, _ subpath: String) throws {
        let dir = home.appendingPathComponent(subpath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "placeholder\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    @Test func sharedAgentsDirectoryDetectedAndScanned() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeSkillRoot(home, ".agents/skills/archify")

        let adapter = SharedAgentsAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        guard case .installed = state else {
            Issue.record("~/.agents 存在应判 installed，实际 \(state)")
            return
        }
        let roots = await adapter.skillRoots()
        #expect(roots.map(\.path.path) == [home.appendingPathComponent(".agents/skills").path])
    }

    @Test func sharedAgentsAbsentIsNotInstalled() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = SharedAgentsAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        #expect(state == .notInstalled)
        let roots = await adapter.skillRoots()
        #expect(roots.isEmpty)
    }

    @Test func qwenDetectedWithSkillsRoot() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeSkillRoot(home, ".qwen/skills/demo")

        let adapter = QwenAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        guard case .installed = state else {
            Issue.record("~/.qwen 存在应判 installed，实际 \(state)")
            return
        }
        let roots = await adapter.skillRoots()
        #expect(roots.map(\.path.path) == [home.appendingPathComponent(".qwen/skills").path])
    }

    @Test func cursorDetectedWithSkillsRoot() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeSkillRoot(home, ".cursor/skills/demo")

        let adapter = CursorAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        guard case .installed = state else {
            Issue.record("~/.cursor 存在应判 installed，实际 \(state)")
            return
        }
        let roots = await adapter.skillRoots()
        #expect(roots.map(\.path.path) == [home.appendingPathComponent(".cursor/skills").path])
    }

    @Test func registryCoversStandardPaths() {
        let registry = AgentRegistry(homeDirectory: FileManager.default.temporaryDirectory)
        let ids = registry.all.map(\.id)
        #expect(ids.contains("agents-shared"))
        #expect(ids.contains("qwen"))
        #expect(ids.contains("cursor"))
    }
}
