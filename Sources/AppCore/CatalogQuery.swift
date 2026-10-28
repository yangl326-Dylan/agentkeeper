import Foundation
import DomainKit

// MARK: - Skill owner 派生

extension Skill {
    /// 该 skill "归属于哪些 agent"（目录归属或 scope 链接）。
    public var owners: [AgentID] {
        switch scope {
        case let .global(owners): owners
        case let .agentOnly(agentID): [agentID]
        case let .project(agentID, _): [agentID]
        case let .multiAgent(ids): ids
        }
    }
}

// MARK: - 作用域大类（筛选语义）

public enum ScopeKind: Hashable, Sendable {
    case global
    case agentOnly
    case project
    case multiAgent

    public static func of(_ skill: Skill) -> ScopeKind {
        switch skill.scope {
        case .global: .global
        case .agentOnly: .agentOnly
        case .project: .project
        case .multiAgent: .multiAgent
        }
    }
}

// MARK: - 铺设落点

extension CatalogQuery {
    /// 同名同名（同指纹）落点集合：铺设记录详情的「全部落点」数据源。
    /// 指纹分歧时按调用方给出的 fingerprint 过滤（缺省取组内第一个指纹为基准）。
    public static func landingPoints(
        named name: String,
        fingerprint: String? = nil,
        catalog: [Skill]
    ) -> [LandingPoint] {
        let matching = catalog.filter { $0.name == name }
        let chosenFingerprint = fingerprint
            ?? matching.first?.sha256
            ?? ""
        let sameContent = matching.filter { $0.sha256 == chosenFingerprint }
        return sameContent.flatMap { skill -> [LandingPoint] in
            switch skill.scope {
            case .global, .agentOnly, .project, .multiAgent:
                return skill.owners.map { agentID in
                    LandingPoint(agentID: agentID, directory: skill.directory)
                }
            }
        }
    }

    /// 同名落点全集（不按指纹过滤）：「更新所有落点」的数据源——需覆盖指纹分歧的落点。
    public static func namedLandingPoints(
        named name: String,
        catalog: [Skill]
    ) -> [LandingPoint] {
        let matching = catalog.filter { $0.name == name }
        // 指纹分歧的落点也必须收编（旨在更新），因此这里不做指纹过滤，只按 owner 展开
        return matching.flatMap { skill -> [LandingPoint] in
            skill.owners.map { agentID in
                LandingPoint(agentID: agentID, directory: skill.directory)
            }
        }
    }

    /// 同名落点之间是否存在指纹分歧（「已分歧」提示的判定）。
    public static func isDiverged(name: String, catalog: [Skill]) -> Bool {
        let matching = catalog.filter { $0.name == name }
        return Set(matching.map(\.sha256)).count > 1
    }
}

// MARK: - 查询

/// Catalog 统一查询：agent / 作用域大类 / 名称与描述搜索（大小写不敏感）。
public struct CatalogQuery: Sendable {
    public var agentID: AgentID?
    public var scopeKinds: Set<ScopeKind>
    public var searchText: String

    public init(agentID: AgentID? = nil, scopeKinds: Set<ScopeKind> = [], searchText: String = "") {
        self.agentID = agentID
        self.scopeKinds = scopeKinds
        self.searchText = searchText
    }

    public static let initial = CatalogQuery()

    public func apply(catalog: [Skill]) -> [Skill] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.filter { skill in
            if let agentID, !skill.owners.contains(agentID) { return false }
            if !scopeKinds.isEmpty, !scopeKinds.contains(ScopeKind.of(skill)) { return false }
            if !keyword.isEmpty {
                let haystacks = [skill.name, skill.skillDescription ?? "", skill.projectTag() ?? ""]
                let match = haystacks.contains { $0.lowercased().contains(keyword) }
                if !match { return false }
            }
            return true
        }
    }
}
