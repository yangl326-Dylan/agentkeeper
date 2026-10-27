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
