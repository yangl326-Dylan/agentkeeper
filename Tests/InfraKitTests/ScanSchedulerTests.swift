import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 测试用 fake adapter。
struct FakeAdapter: AgentAdapter {
    let id: AgentID
    let displayName: String
    let install: AgentInstallState
    let roots: [SkillRoot]
    let projectRoots: [ProjectRoot]
    let parseResult: ParsedSkill?

    init(
        id: AgentID,
        install: AgentInstallState,
        roots: [SkillRoot],
        displayName: String? = nil,
        projectRoots: [ProjectRoot] = [],
        parseResult: ParsedSkill? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.install = install
        self.roots = roots
        self.projectRoots = projectRoots
        self.parseResult = parseResult
    }

    func detectInstallation() async -> AgentInstallState { install }
    func skillRoots() async -> [SkillRoot] { roots }
    func discoverProjectRoots() async -> [ProjectRoot] { projectRoots }
    func parseSkill(at directory: URL) async -> ParsedSkill? { parseResult }
}

@Suite struct AgentRegistryTests {
    @Test func registryHoldsAllBuiltinAdapters() {
        let registry = AgentRegistry(homeDirectory: URL(fileURLWithPath: "/tmp/ak-nonexistent-home"))
        let ids = Set(registry.all.map(\.id))
        #expect(ids == Set([
            "claude-code", "opencode", "codex", "gemini", "openclaw", "pi", "oh-my-pi",
            // 固定标准路径（常见 harness 安装/skill 目录）：共享目录 + Qwen + Cursor + DeepSeek
            "agents-shared", "qwen", "cursor", "deepseek",
        ]))
    }

    @Test func canAppendCustomAdapterWithoutCoreChanges() {
        var registry = AgentRegistry(homeDirectory: URL(fileURLWithPath: "/tmp/ak-nonexistent-home"))
        let before = registry.all.count
        registry.append(FakeAdapter(id: "custom-x", install: .notInstalled, roots: []))
        #expect(registry.all.count == before + 1)
    }
}

@Suite struct ScanSchedulerTests {
    private func skillRoot(_ home: URL, _ subpath: String, owners: [AgentID]) -> SkillRoot {
        SkillRoot(path: home.appendingPathComponent(subpath, isDirectory: true), owners: owners, level: .user)
    }

    @Test func concurrentScanMergesSharedRootOwners() async {
        let home = makeFakeHome(files: [".claude/skills/a/SKILL.md", ".config/opencode/skill/b/SKILL.md"])
        defer { cleanup(home) }
        let sharedPath = home.appendingPathComponent("shared", isDirectory: true)
        let claude = FakeAdapter(id: "claude-code", install: .installed(configDirectory: nil), roots: [skillRoot(home, "shared", owners: ["claude-code"])])
        let opencode = FakeAdapter(id: "opencode", install: .installed(configDirectory: nil), roots: [skillRoot(home, "shared", owners: ["opencode"])])
        var registry = AgentRegistry(adapters: [])
        registry.append(claude)
        registry.append(opencode)
        let scheduler = ScanScheduler(registry: registry)
        let report = await scheduler.scanAll(rootDirectory: home)
        #expect(report.agents.count == 2)
        let sharedRoots = report.agents.flatMap(\.skillRoots).filter { $0.path == sharedPath }
        #expect(sharedRoots.count == 2)  // 各 agent 各自有 root 记录
        // 调度器输出的"共享目录"索引反映双方 owner
        let sharedIndex = report.sharedRoots.first { $0.path == sharedPath }
        #expect(sharedIndex != nil)
        #expect(Set(sharedIndex!.owners) == ["claude-code", "opencode"])
    }

    @Test func permissionDeniedRootProducesDiagnosticAndKeepsScanning() async throws {
        let home = makeFakeHome(files: ["locked/ignored.txt"])
        let locked = home.appendingPathComponent("locked", isDirectory: true)
        // 收走读权限（POSIX 同用户仍生效）
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            var attributes = try? FileManager.default.attributesOfItem(atPath: locked.path)
            attributes?[.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(attributes!, ofItemAtPath: locked.path)
            cleanup(home)
        }

        let adapter = FakeAdapter(
            id: "victim",
            install: .installed(configDirectory: nil),
            roots: [skillRoot(home, "locked", owners: ["victim"])]
        )
        var registry = AgentRegistry(adapters: [])
        registry.append(adapter)
        let scheduler = ScanScheduler(registry: registry)
        let report = await scheduler.scanAll(rootDirectory: home)
        #expect(report.agents.count == 1)  // agent 依然完整出现

        // 测试环境特例：作为 root 或无权限强制时目录仍可读，则只有权限诊断被跳过——用标志说明
        let readable = FileManager.default.isReadableFile(atPath: locked.path)
        if !readable {
            let diagnostic = report.diagnostics.first {
                $0.kind == .permissionDenied && $0.path == locked.path
            }
            #expect(diagnostic != nil)
            // 授权引导 key 供 UI 跳转
            #expect(diagnostic?.remediation == .grantAccess)
            // 诊断必须能定位到具体目录（不模糊）
            #expect(diagnostic?.agentID == "victim")
        }
    }

    @Test func scanReportIncludesElapsedAndTimeStamp() async {
        var registry = AgentRegistry(adapters: [])
        registry.append(FakeAdapter(id: "solo", install: .notInstalled, roots: []))
        let scheduler = ScanScheduler(registry: AgentRegistry(adapters: [FakeAdapter(id: "solo", install: .notInstalled, roots: [])]))
        let report = await scheduler.scanAll(rootDirectory: makeFakeHome(files: []))
        #expect(report.startedAt <= Date())
        #expect(report.elapsed >= 0)
    }
}
