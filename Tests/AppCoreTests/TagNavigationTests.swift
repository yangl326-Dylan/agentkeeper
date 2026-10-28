import Foundation
import Testing
import DomainKit
@testable import AppCore

/// 7.4：导航树「标签」分组的纯函数构建。
@Suite struct TagNavigationTests {
    private func skill(name: String, path: String) -> Skill {
        Skill(
            id: path,
            name: name,
            directory: URL(fileURLWithPath: path, isDirectory: true),
            scope: .agentOnly(agentID: "claude-code"),
            sha256: "x"
        )
    }

    @Test func tagSectionsBuiltWithCounts() {
        let alpha = skill(name: "alpha", path: "/a/alpha")
        let beta = skill(name: "beta", path: "/a/beta")
        let gamma = skill(name: "gamma", path: "/a/gamma")
        let sections = NavigationModel.buildTagSections(
            skills: [alpha, beta, gamma],
            tagsBySkill: [
                "/a/alpha": ["写作", "实验"],
                "/a/beta": ["写作"],
                "/a/gamma": ["阅读"],
            ]
        )
        #expect(sections.count == 3)
        #expect(sections.allSatisfy { $0.kind == .tag })
        let byTitle = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0) })
        #expect(byTitle["写作"]?.count == 2)
        #expect(byTitle["实验"]?.count == 1)
        #expect(byTitle["阅读"]?.count == 1)
        // 排序确定性
        #expect(sections.map(\.title) == sections.map(\.title).sorted())
    }

    @Test func emptySkillsSkippedInTagSections() {
        let sections = NavigationModel.buildTagSections(
            skills: [],
            tagsBySkill: ["/gone": ["写作"]]
        )
        #expect(sections.isEmpty) // catalog 无条目：标签节不渲染空组
    }
}
