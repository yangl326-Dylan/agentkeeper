import Foundation
import DomainKit

/// 把 ScanReport 中各 agent 的 skill 根目录展开为最终 Skill 目录实体，
/// 确定性判定作用域（含 multi-agent 铺设识别）。
public struct CatalogBuilder: Sendable {
    private let collector: SkillCollector

    public init(collector: SkillCollector = SkillCollector()) {
        self.collector = collector
    }

    public func build(agents: [Agent]) -> [Skill] {
        var skills: [Skill] = []

        for agent in agents {
            for root in agent.skillRoots {
                for parsed in collector.collect(inRoot: root.path, agentID: agent.id) {
                    let scope = initialScope(
                        root: root,
                        agentID: agent.id,
                        frontmatterName: parsed.frontmatterName
                    )
                    skills.append(
                        Skill(
                            id: skillID(parsed: parsed, scope: scope),
                            name: parsed.frontmatterName ?? parsed.directory.lastPathComponent,
                            directory: parsed.directory,
                            scope: scope,
                            status: .enabled,
                            sha256: parsed.sha256,
                            frontmatterName: parsed.frontmatterName,
                            skillDescription: parsed.frontmatterDescription,
                            fileCount: parsed.files.count,
                            lastModified: lastModified(of: parsed),
                            totalBytes: parsed.totalBytes,
                            skillMdBytes: parsed.skillMdBytes,
                            issues: parsed.issues,
                            layout: parsed.isFlatFile ? .flatFile : .directoryPackage
                        )
                    )
                }
            }
        }

        return labelShadowing(in: relabelMultiAgent(in: skills))
    }

    // MARK: - 同名遮蔽标注

    /// 同 agent 内同名 skill 的副作用判定：官方优先级有据才标（spec 2026-11-09）。
    /// 只处理 agentOnly/project scope；global/multiAgent 是另一条语义（跨 agent 共同加载）。
    private func labelShadowing(in skills: [Skill]) -> [Skill] {
        var result = skills
        var groups: [String: [Int]] = [:]
        for (index, skill) in result.enumerated() {
            switch skill.scope {
            case .agentOnly, .project:
                guard let owner = skill.scope.agentIDForOwner else { continue }
                groups["\(owner)|\(skill.name)", default: []].append(index)
            case .global, .multiAgent:
                continue
            }
        }
        for (key, indices) in groups where indices.count > 1 {
            let agentID = key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            guard SkillShadowPolicy.precedence(for: agentID) == .projectOverUser else { continue }
            // 仅当恰好一个项目级副本；多个项目间排序不可知，保持中性
            let projectIndices = indices.filter { index in
                if case .project = result[index].scope { return true }
                return false
            }
            guard projectIndices.count == 1, let projectIndex = projectIndices.first else { continue }
            let userIndices = indices.filter { index in
                if case .agentOnly = result[index].scope { return true }
                return false
            }
            guard !userIndices.isEmpty else { continue }
            for index in userIndices where result[index].shadowedBy == nil {
                result[index].shadowedBy = result[projectIndex].id
            }
            result[projectIndex].shadowedCount += userIndices.count
        }
        return result
    }

    // MARK: - 初始作用域

    private func initialScope(root: SkillRoot, agentID: AgentID, frontmatterName: String?) -> SkillScope {
        switch root.level {
        case let .project(projectRoot):
            return .project(agentID: agentID, root: projectRoot)
        case .user:
            // 共享目录（≥2 agent 引用）→ 全局
            if root.owners.count >= 2 {
                return .global(owners: root.owners.sorted())
            }
            return .agentOnly(agentID: agentID)
        }
    }

    // MARK: - multi-agent 铺设识别

    /// 同名（frontmatter name，缺省目录名）且同指纹、出现在 ≥2 个 agent 目录 → .multiAgent。
    /// 分叉（同名不同内容）不标注，保持 agentOnly/global 原状。
    private func relabelMultiAgent(in skills: [Skill]) -> [Skill] {
        var groups: [String: [Int]] = [:]
        for (index, skill) in skills.enumerated() {
            // 只对"单 agent 归属"的条目做铺设检查
            switch skill.scope {
            case .agentOnly, .multiAgent:
                let key = "\(skill.name)|\(skill.sha256)"
                groups[key, default: []].append(index)
            case .global, .project:
                continue
            }
        }
        var result = skills
        for (_, indices) in groups {
            let ownerIDs = Set(indices.compactMap { result[$0].scope.agentIDForOwner })
            guard ownerIDs.count >= 2 else { continue }
            for index in indices {
                result[index].scope = .multiAgent(ownerIDs.sorted())
            }
        }
        return result.sorted {
            ($0.projectTag() ?? "", $0.name) < ($1.projectTag() ?? "", $1.name)
        }
    }

    // MARK: - 辅助

    private func skillID(parsed: ParsedSkill, scope: SkillScope) -> String {
        let tag = scope.projectRoot?.tagName ?? ""
        let base = parsed.directory.standardizedFileURL.path
        return tag.isEmpty ? base : tag + "|" + base
    }

    private func lastModified(of parsed: ParsedSkill) -> Date? {
        parsed.files
            .compactMap { url -> Date? in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            .max()
    }
}

/// 同名 skill 优先级判定（官方文档背书；无据一律 none，宁可少说）。
public enum SkillShadowPolicy: Sendable {
    public enum Precedence: Hashable, Sendable {
        /// 项目级目录覆盖用户级（Claude Code 官方 skills 文档）。
        case projectOverUser
        /// 无官方优先级文档，不判定。
        case none
    }

    public static func precedence(for agentID: AgentID) -> Precedence {
        switch agentID {
        case "claude-code": .projectOverUser
        default: .none
        }
    }
}
