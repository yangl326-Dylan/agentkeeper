import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 8.2：性能预算——tags 写 100 次 <2s；双 agent × 50 skill 铺设分组 <1s。
@Suite struct DistributionPerformanceTests {
    /// tags 写 100 次全量走原子持久化（磁盘真实落盘）。
    @Test func hundredTagWritesUnderTwoSeconds() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let store = TagStore(directory: home.appendingPathComponent("ak", isDirectory: true))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<100 {
                let tag = "标签-\(index)"
                store.addDefinition(tag)
                _ = store.assign(tag: tag, skillID: "/skills/skill-\(index % 20)")
            }
        }
        #expect(elapsed < Duration.seconds(2))
        #expect(store.tags().count == 100)
    }

    /// 双 agent × 50 skill 同名铺设 → namedLandingPoints 分组 <1s（重扫后列表场景）。
    @Test func landingPointsGroupingFast() {
        var catalog: [Skill] = []
        for index in 0..<50 {
            for agent in ["claude-code", "codex"] {
                let path = "/\(agent)/skills/skill-\(index)"
                catalog.append(Skill(
                    id: path,
                    name: "skill-\(index)",
                    directory: URL(fileURLWithPath: path, isDirectory: true),
                    scope: .agentOnly(agentID: agent),
                    sha256: "sha-\(index)"
                ))
            }
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<50 {
                _ = CatalogQuery.landingPoints(named: "skill-\(index)", catalog: catalog)
            }
        }
        #expect(elapsed < Duration.seconds(1))
    }
}
