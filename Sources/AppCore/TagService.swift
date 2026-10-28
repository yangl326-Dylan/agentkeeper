import Foundation
import DomainKit
import InfraKit

/// 标签编排（design D4）：TagStore 单一写入口 + catalog 联动的 orphan 检测。
/// 不依赖 Actor：TagStore 自身队列同步；本类只做语义封装。
public final class TagService: @unchecked Sendable {
    private let store: TagStore
    private let disabledRoot: URL

    public init(store: TagStore, disabledRoot: URL) {
        self.store = store
        self.disabledRoot = disabledRoot
    }

    // MARK: - 标签定义

    public func tags() -> [String] {
        store.tags()
    }

    /// 增加标签并指给 skill（定义不存在则先建，对应 UI「新标签 chip」）。
    public func addTag(_ tag: String, toSkillID skillID: String) {
        store.addDefinition(tag)
        store.assign(tag: tag, skillID: skillID)
    }

    /// 删除标签定义（仅标签层，skill 文件不动）。
    public func deleteTag(_ tag: String) {
        store.removeDefinition(tag)
    }

    /// 重命名并同步全部关联。
    public func renameTag(_ from: String, to new: String) {
        store.rename(from, to: new)
    }

    /// 从某 skill 移除标签；该标签若不再有任何关联，由调用方决定保留（历史品味）。
    public func removeTag(_ tag: String, fromSkillID skillID: String) {
        store.unassign(tag: tag, skillID: skillID)
    }

    // MARK: - 关联查询

    public func assignments(tag: String) -> [String] {
        store.assignments(tag: tag)
    }

    public func tags(forSkillID skillID: String) -> [String] {
        store.tags(forSkillID: skillID)
    }

    /// catalog 中失踪、但在禁用区 manifest 可查证且带有标签的 skill → 合成 disabled 条目。
    /// 供标签筛选（spec：禁用条目同样可携带标签出现在分组中）。
    public func disabledTaggedSkills(catalog: [Skill]) -> [Skill] {
        let alive = Set(catalog.map(\.id))
        let tagged = Set(
            store.allAssignedSkillIDs()
                .filter { !alive.contains($0) && !store.tags(forSkillID: $0).isEmpty }
        )
        guard !tagged.isEmpty else { return [] }

        let fileManager = FileManager.default
        guard let agentDirectories = try? fileManager.contentsOfDirectory(
            at: disabledRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var result: [Skill] = []
        for agentDirectory in agentDirectories
        where (try? agentDirectory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let manifests = (try? fileManager.contentsOfDirectory(at: agentDirectory, includingPropertiesForKeys: nil)) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasSuffix(".manifest.json") {
                guard let data = try? Data(contentsOf: manifest),
                      let record = try? JSONDecoder().decode(DisabledSkillRecord.self, from: data)
                else { continue }
                let key = record.originalPath.standardizedPath
                guard tagged.contains(key) else { continue }
                result.append(Skill(
                    id: key,
                    name: record.name,
                    directory: URL(fileURLWithPath: record.originalPath, isDirectory: true),
                    scope: .agentOnly(agentID: record.agentID),
                    status: .disabled,
                    sha256: record.sha256
                ))
            }
        }
        return result
    }

    // MARK: - orphan（spec：悬挂关联提示与一键清理）

    /// catalog 中不存在、且不在禁用区的关联条目数。
    public func orphanCount(catalog: [Skill]) -> Int {
        orphanSkillIDs(catalog: catalog).count
    }

    /// 清除全部 orphan 关联（只动标签存储），返回清除条数。
    @discardableResult
    public func purgeOrphans(catalog: [Skill]) -> Int {
        let orphans = orphanSkillIDs(catalog: catalog)
        for skillID in orphans {
            for tag in store.tags(forSkillID: skillID) {
                store.unassign(tag: tag, skillID: skillID)
            }
        }
        return orphans.count
    }

    private func orphanSkillIDs(catalog: [Skill]) -> [String] {
        let alive = Set(catalog.map(\.id))
        let resolvedDisabled = disabledRoot.standardizedFileURL.path
        return store.allAssignedSkillIDs().filter { skillID in
            guard !alive.contains(skillID) else { return false }
            // 禁用区关联不算 orphan（禁用期间保留是 spec 要求）
            let disabledDirectory = resolvedDisabled
            let normalized = skillID.standardizedPath
            return !(normalized == disabledDirectory || normalized.hasPrefix(disabledDirectory + "/"))
        }
    }
}

extension String {
    /// skillID（目录路径）的规范化（/var ↔ /private/var 无碍——两端取同源规则）。
    var standardizedPath: String {
        URL(fileURLWithPath: self).standardizedFileURL.path
    }
}
