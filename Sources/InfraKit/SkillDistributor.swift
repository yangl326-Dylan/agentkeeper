import Foundation
import DomainKit

/// 安装结果（skill-distribution spec）。
public enum DistributionInstallResult: Hashable, Sendable {
    case installed(name: String, target: URL, sha256: String)
    case alreadyDistributed(target: URL)
}

/// Skill 分发管线（design D1）：校验 → 冲突检查 → 原子落位。
/// 三种来源最终都收敛为「一个已通过识别规则的目录 + 名称」。
public struct SkillDistributor: Sendable {
    /// 目录复制动作（注入点：失败注入测试 / 生产实现换库都可）。
    /// 契约：把 source 深拷贝到 targetNamespaced stage 目录，失败即抛，无副作用保证由调用方回滚。
    public typealias Copier = @Sendable (URL, URL) throws -> Void

     
    private let git: GitInstaller
    private let copier: Copier

    public init(
        git: GitInstaller,
        copier: @escaping Copier = SkillDistributor.deepCopyAcrossVolumes
    ) {
        self.git = git
        self.copier = copier
    }

    // MARK: - 安装

    /// 把一个分发来源安装到目标 skill 根目录。
    /// 语义：复制非破坏（来源不动）、指纹校验、冲突不覆盖。
    public func install(
        source: DistributionSource,
        targetSkillRoot: URL
    ) async throws -> DistributionInstallResult {
        switch source {
        case let .existingSkill(_, _, directoryPath):
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            return try await install(materializedDirectory: directory, targetSkillRoot: targetSkillRoot)
        case let .localDirectory(path):
            let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            return try await install(materializedDirectory: directory, targetSkillRoot: targetSkillRoot)
        case let .gitRepository(url):
            return try await installFromGit(url: url, targetSkillRoot: targetSkillRoot)
        }
    }

    /// 物化目录 → 校验 → 冲突 → 落位 的公共管线。
    public func install(
        materializedDirectory: URL,
        name overrideName: String? = nil,
        targetSkillRoot: URL
    ) async throws -> DistributionInstallResult {
        // 1. 校验（识别规则 = SKILL.md + 合法 frontmatter；分发比扫描更严：必须有 name）
        guard let parsed = SkillParsing.parseDirectory(materializedDirectory) else {
            throw DistributionError.invalidSource(reason: invalidReason(of: materializedDirectory))
        }
        guard parsed.frontmatterName?.isEmpty == false else {
            throw DistributionError.invalidSource(
                reason: "SKILL.md frontmatter 不合法（缺少 name）：\(materializedDirectory.path)"
            )
        }

        // 2. 冲突检查
        let name = overrideName ?? materializedDirectory.lastPathComponent
        try FileManager.default.createDirectory(at: targetSkillRoot, withIntermediateDirectories: true)
        let target = targetSkillRoot.appendingPathComponent(name, isDirectory: true)
        if let existingSha = Fingerprint.sha256OfDirectory(target) {
            if existingSha == parsed.sha256 {
                return .alreadyDistributed(target: target)
            }
            throw DistributionError.conflict(DistributionConflict(
                targetPath: target.path,
                existingSha256: existingSha,
                incomingSha256: parsed.sha256
            ))
        }

        // 3. 原子落位：staging 深拷贝（目标根内唯一前缀）→ 指纹校验 → rename
        let staging = targetSkillRoot.appendingPathComponent(".ak-stage-\(name)-\(UUID().uuidString)", isDirectory: true)
        do {
            try copier(materializedDirectory, staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            if let distributionError = error as? DistributionError { throw distributionError }
            throw DistributionError.ioFailure(
                path: materializedDirectory.path,
                underlyingDescription: "复制失败：\(error)"
            )
        }
        guard let stagedSha = Fingerprint.sha256OfDirectory(staging) else {
            try? FileManager.default.removeItem(at: staging)
            throw DistributionError.ioFailure(path: staging.path, underlyingDescription: "stage 校验失败")
        }
        guard stagedSha == parsed.sha256 else {
            try? FileManager.default.removeItem(at: staging)
            throw DistributionError.ioFailure(
                path: staging.path,
                underlyingDescription: "复制后指纹不一致（\(stagedSha.prefix(8))… vs \(parsed.sha256.prefix(8))…）"
            )
        }
        do {
            try FileManager.default.moveItem(at: staging, to: target)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw DistributionError.ioFailure(path: target.path, underlyingDescription: "rename 失败：\(error)")
        }
        return .installed(name: name, target: target, sha256: stagedSha)
    }

    // MARK: - git 来源

    /// git 来源安装：物化 → 候选 → 单候选直接装 / 多候选待选由调用方逐个 install 分发。
    public func installFromGit(
        url raw: String,
        targetSkillRoot: URL
    ) async throws -> DistributionInstallResult {
        let materialized = try await git.materialize(url: raw)
        let inTempArea = isInsideTemp(materialized)
        defer { if inTempArea { git.cleanup(materialized) } }

        let candidates = git.candidates(for: raw, in: materialized)
        guard !candidates.isEmpty else {
            throw DistributionError.invalidSource(reason: "仓库中未发现合法 skill（既非单 skill 仓库也无合法一级子目录）")
        }
        guard candidates.count == 1 else {
            // 多候选不该走本入口：由 UI 勾选后调用「本地目录安装」逐个进行
            throw DistributionError.invalidSource(
                reason: "仓库含 \(candidates.count) 个候选 skill，请先在候选面板勾选"
            )
        }
        let candidate = candidates[0]
        return try await install(
            materializedDirectory: candidate.directory,
            name: candidate.name,
            targetSkillRoot: targetSkillRoot
        )
    }

    private func isInsideTemp(_ directory: URL) -> Bool {
        directory.path.hasPrefix(baseTempAreaPath)
    }

    private var baseTempAreaPath: String {
        git.baseDirectoryPath
    }

    // MARK: - 校验细节

    private func invalidReason(of directory: URL) -> String {
        let skillMarkdown = directory.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMarkdown.path) else {
            return "目录缺少 SKILL.md：\(directory.path)"
        }
        guard let raw = try? String(contentsOf: skillMarkdown, encoding: .utf8) else {
            return "SKILL.md 无法读取：\(directory.path)"
        }
        if FrontmatterParser.parse(markdown: raw).name == nil {
            return "SKILL.md frontmatter 不合法（缺少 name）"
        }
        return "目录不符合 skill 识别规则：\(directory.path)"
    }

    // MARK: - 深拷贝（生产实现）

    /// 递归深拷贝；hidden 与符号链接跳过（与 SkillParsing.allRegularFiles 同口径）。
    public static func deepCopyAcrossVolumes(source: URL, target: URL) throws {
        // /var 与 /private/var 表示形式的坑：先 resolve，再保证枚举前缀一致
        let source = source.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw DistributionError.invalidSource(reason: "来源目录不存在")
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in SkillParsing.allRegularFiles(in: source) {
            // 已知前缀重映射：macOS 枚举器恒返回 /private/var 形态，传入 /var 形态时归一化回去
            var filePath = file.path
            if filePath.hasPrefix("/private/var/"), source.path.hasPrefix("/var/") {
                filePath = "/var" + filePath.dropFirst("/private/var".count)
            }
            guard filePath.hasPrefix(source.path) else {
                throw DistributionError.ioFailure(
                    path: file.path,
                    underlyingDescription: "枚举前缀与来源不一致，放弃复制以防错位落盘"
                )
            }
            let relative = filePath.dropFirst(source.path.count + 1)
            let destination = target.appendingPathComponent(String(relative))
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 内容失败即抛（readDataToEndOfFile 权限错误走 ioFailure 语义）
            let data = try Data(contentsOf: file)
            try data.write(to: destination, options: .atomic)
        }
    }

    // MARK: - 落点覆盖

    /// 覆盖既有落点内容（「更新所有落点」原语，design D2）：
    /// staging 拷贝校验 → 旧内容原子让位（.ak-old-*）→ 新内容 rename 落位 → 清掉旧内容。
    /// 任何失败回滚让位（落点回到原状），由上层先做 autoSnapshot 兜底。
    public func replaceDirectoryContent(target: URL, sourceDirectory: URL) throws {
        guard let parsed = SkillParsing.parseDirectory(sourceDirectory) else {
            throw DistributionError.invalidSource(reason: "替换来源不是合法 skill：\(sourceDirectory.path)")
        }
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".ak-stage-\(target.lastPathComponent)-\(UUID().uuidString)", isDirectory: true
        )
        let displaced = parent.appendingPathComponent(
            ".ak-old-\(target.lastPathComponent)-\(UUID().uuidString)", isDirectory: true
        )

        func rollback() {
            try? FileManager.default.removeItem(at: staging)
            if FileManager.default.fileExists(atPath: displaced.path) {
                if !FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.moveItem(at: displaced, to: target)
                }
                try? FileManager.default.removeItem(at: displaced)
            }
        }

        do {
            try copier(sourceDirectory, staging)
            guard let stagedSha = Fingerprint.sha256OfDirectory(staging), stagedSha == parsed.sha256 else {
                throw DistributionError.ioFailure(
                    path: staging.path,
                    underlyingDescription: "stage 校验失败（指纹与来源不一致）"
                )
            }
            // 旧内容让位（原子 move），新内容落位
            try FileManager.default.moveItem(at: target, to: displaced)
        } catch {
            rollback()
            if let distributionError = error as? DistributionError { throw distributionError }
            throw DistributionError.ioFailure(path: staging.path, underlyingDescription: "复制失败：\(error)")
        }
        do {
            try FileManager.default.moveItem(at: staging, to: target)
        } catch {
            rollback()
            throw DistributionError.ioFailure(path: target.path, underlyingDescription: "rename 失败：\(error)")
        }
        // 成功：清掉让位的旧内容（其内容已被上层 autoSnapshot 兜底）
        try? FileManager.default.removeItem(at: displaced)
    }
}
