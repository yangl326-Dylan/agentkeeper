import Foundation
import Testing
import DomainKit
@testable import AppCore

@Suite struct LandingPointsTests {
    private func skill(agentID: String, name: String, sha256: String, path: String) -> Skill {
        Skill(
            id: path,
            name: name,
            directory: URL(fileURLWithPath: path, isDirectory: true),
            scope: .agentOnly(agentID: agentID),
            sha256: sha256
        )
    }

    /// 同名同指纹的两个落点 → 组互相链接（同组返回多条 LandingPoint）。
    @Test func sameNameSameShaGroupsAsOneLandingSet() {
        let catalog = [
            skill(agentID: "claude-code", name: "review", sha256: "aaa", path: "/a/.claude/skills/review"),
            skill(agentID: "codex", name: "review", sha256: "aaa", path: "/a/.codex/skills/review"),
            skill(agentID: "codex", name: "docs", sha256: "bbb", path: "/a/.codex/skills/docs"),
        ]
        let points = CatalogQuery.landingPoints(named: "review", catalog: catalog)
        #expect(points.count == 2)
        #expect(Set(points.map(\.agentID)) == ["claude-code", "codex"])
    }

    /// 同名不同指纹（分歧）→ 按指纹拆组，每组独立。
    @Test func divergedNameSplitsByFingerprint() {
        let catalog = [
            skill(agentID: "claude-code", name: "review", sha256: "aaa", path: "/a/.claude/skills/review"),
            skill(agentID: "codex", name: "review", sha256: "zzz", path: "/a/.codex/skills/review"),
        ]
        let points = CatalogQuery.landingPoints(named: "review", catalog: catalog)
        #expect(points.count == 1) // 只返回与所选指纹一致的一组（调用方带 fingerprint 过滤）
        #expect(points[0].agentID == "claude-code")
    }

    /// multiAgent 作用域的记录同样计入落点——但按目录收编（每目录一条，owners 合并显示）。
    /// per-owner 展开会宣称 claude-code 加载 ~/.agents 目录（错误归属），v0.4.1 修复。
    @Test func multiAgentScopeCountsAsLandingPoint() {
        let multi = Skill(
            id: "/m/id",
            name: "review",
            directory: URL(fileURLWithPath: "/x/review", isDirectory: true),
            scope: .multiAgent(["claude-code", "opencode"]),
            sha256: "aaa"
        )
        let other = skill(agentID: "codex", name: "review", sha256: "aaa", path: "/a/.codex/skills/review")
        let points = CatalogQuery.landingPoints(named: "review", fingerprint: "aaa", catalog: [multi, other])
        #expect(points.count == 2)
        let byDir = Dictionary(uniqueKeysWithValues: points.map { ($0.directory.path, $0) })
        #expect(byDir["/x/review"]?.agentID == "claude-code, opencode")
        #expect(byDir["/a/.codex/skills/review"]?.agentID == "codex")
    }

    /// 不同名互不干扰。
    @Test func otherNamesIgnored() {
        let catalog = [
            skill(agentID: "claude-code", name: "review", sha256: "aaa", path: "/a/.claude/skills/review"),
            skill(agentID: "codex", name: "review-docs", sha256: "aaa", path: "/a/.codex/skills/review-docs"),
        ]
        #expect(CatalogQuery.landingPoints(named: "review", catalog: catalog).count == 1)
    }
}
