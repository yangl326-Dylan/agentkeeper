import Foundation
import DomainKit

/// AppCore 测试专用"家目录"夹具（与 InfraKitTests 同形）。
@discardableResult
func makeFakeHome(
    files: [String],
    fileContents: [String: String] = [:]
) -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("ak-core-fixture-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for relative in files {
        let target = home.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = fileContents[relative] ?? "placeholder\n"
        try? content.write(to: target, atomically: true, encoding: .utf8)
    }
    return home
}

func cleanup(_ home: URL) {
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 共用 FakeAdapter（与 InfraKitTests 同形）

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
