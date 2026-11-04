import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 用户自定义 agent（`~/.agentkeeper/agents.json`）：合法生效、非法条目被拒且不阻塞扫描。
@Suite struct UserAgentConfigTests {
    private func writeConfig(_ home: URL, _ json: String) {
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? json.write(to: base.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)
    }

    private func base(_ home: URL) -> URL {
        home.appendingPathComponent(".agentkeeper", isDirectory: true)
    }

    @Test func loadsValidCustomAgent() {
        let home = makeFakeHome(files: [".windsurf/skills/foo/SKILL.md"])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[{
          "id":"windsurf",
          "displayName":"Windsurf",
          "detectionSubpaths":[".windsurf"],
          "skillRootCandidates":[".windsurf/skills"],
          "projectSkillSubpaths":[".windsurf/skills"],
          "icon":"wind"
        }]}
        """)

        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.diagnostics.isEmpty)
        #expect(result.specs.count == 1)
        let spec = result.specs[0]
        #expect(spec.id == "windsurf")
        #expect(spec.displayName == "Windsurf")
        #expect(spec.detectionSubpaths == [".windsurf"])
        #expect(spec.projectSkillSubpaths == [".windsurf/skills"])
        #expect(spec.icon == "wind")
        #expect(spec.projectRootDiscovery == .none)
    }

    @Test func missingFileYieldsEmptyWithoutDiagnostics() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.isEmpty)
        #expect(result.diagnostics.isEmpty)
    }

    /// 内置 id 不可被覆盖（防劫持）：冲突条目忽略并给出诊断。
    @Test func rejectsBuiltInIDConflict() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[{"id":"claude-code","displayName":"Fake","detectionSubpaths":[".evil"],"skillRootCandidates":[".evil/skills"]}]}
        """)
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].kind == .unrecognizedStructure)
        #expect(result.diagnostics[0].message.contains("claude-code"))
    }

    /// 路径必须是家目录下的相对路径：绝对路径 / `..` / `~` 一律拒绝。
    @Test func rejectsUnsafePaths() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[
          {"id":"abs","detectionSubpaths":["/etc"],"skillRootCandidates":["/etc/skills"]},
          {"id":"traversal","detectionSubpaths":["../x"],"skillRootCandidates":["../x/skills"]},
          {"id":"tilde","detectionSubpaths":["~/x"],"skillRootCandidates":["~/x/skills"]}
        ]}
        """)
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.isEmpty)
        #expect(result.diagnostics.count == 3)
        #expect(result.diagnostics.allSatisfy { $0.kind == .unrecognizedStructure })
    }

    @Test func rejectsMalformedJSON() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        writeConfig(home, "{ not json")
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].path.hasSuffix("agents.json"))
    }

    /// 重复 id：先出现者生效，后者忽略并诊断。
    @Test func duplicateIDsFirstWins() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[
          {"id":"dup","displayName":"First","detectionSubpaths":[".dup"],"skillRootCandidates":[".dup/skills"]},
          {"id":"dup","displayName":"Second","detectionSubpaths":[".dup2"],"skillRootCandidates":[".dup2/skills"]}
        ]}
        """)
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.map(\.id) == ["dup"])
        #expect(result.specs[0].displayName == "First")
        #expect(result.diagnostics.count == 1)
    }

    /// 非法 id（大写/下划线/空）被拒绝。
    @Test func rejectsInvalidIDs() {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[
          {"id":"Bad_ID","detectionSubpaths":[".x"],"skillRootCandidates":[".x/skills"]},
          {"id":"","detectionSubpaths":[".y"],"skillRootCandidates":[".y/skills"]}
        ]}
        """)
        let result = UserAgentConfigLoader.load(baseDirectory: base(home))
        #expect(result.specs.isEmpty)
        #expect(result.diagnostics.count == 2)
    }

    /// 注册表自动合并用户 agent，内置不受影响。
    @Test func registryMergesUserAgents() {
        let home = makeFakeHome(files: [".windsurf/skills/foo/SKILL.md"])
        defer { cleanup(home) }
        writeConfig(home, """
        {"agents":[{"id":"windsurf","displayName":"Windsurf","detectionSubpaths":[".windsurf"],"skillRootCandidates":[".windsurf/skills"]}]}
        """)
        let registry = AgentRegistry(homeDirectory: home)
        #expect(registry.specs.map(\.id) == BuiltInAgents.all.map(\.id) + ["windsurf"])
        #expect(registry.all.map(\.id).contains("windsurf"))
        #expect(registry.configDiagnostics.isEmpty)
    }
}
