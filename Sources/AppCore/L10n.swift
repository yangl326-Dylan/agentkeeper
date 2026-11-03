import Foundation
import DomainKit

// MARK: - 语言与本地化（i18n：设置可切换，默认同系统语言）

/// 用户可选语言（设置页；落盘 defaults）。
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    /// 系统语言解析（"默认同系统"）：首个首选语言 zh* → 简体中文，其余 → English。
    public static func resolveSystem(preferredLanguages: [String]) -> ResolvedLanguage {
        guard let first = preferredLanguages.first else { return .english }
        return first.lowercased().hasPrefix("zh") ? .zhHans : .english
    }

    /// 设置页展示名（各语言原生书写，始终可读）。
    public var displayName: String {
        switch self {
        case .system: L10n.resolve(.system, preferredLanguages: Locale.preferredLanguages).settingsFollowSystem
        case .zhHans: "简体中文"
        case .english: "English"
        }
    }
}

/// 解析后的界面语言。
public enum ResolvedLanguage: String, Sendable {
    case zhHans
    case english
}

/// 界面字符串表（编译期属性键控——拼错即编译错，无运行时 miss）。
/// AppCore 层（导航标题等）与 UI 层共用；语言源：AppSettingsStore.language → AppEnvironment.l10n。
public struct L10n: Sendable {
    public let lang: ResolvedLanguage

    public init(lang: ResolvedLanguage) {
        self.lang = lang
    }

    /// 按设置解析（.system → 跟随系统首选语言）。
    public static func resolve(
        _ appLanguage: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> L10n {
        switch appLanguage {
        case .system: L10n(lang: AppLanguage.resolveSystem(preferredLanguages: preferredLanguages))
        case .zhHans: L10n(lang: .zhHans)
        case .english: L10n(lang: .english)
        }
    }

    private var zh: Bool { lang == .zhHans }

    // MARK: 侧栏

    public var sidebarAllSkills: String { zh ? "所有 Skills" : "All Skills" }
    public var sectionAgents: String { zh ? "Agents" : "Agents" }
    public var sectionScopes: String { zh ? "作用域" : "Scopes" }
    public var sectionTags: String { zh ? "标签" : "Tags" }
    public var sectionLifecycle: String { zh ? "生命周期" : "Lifecycle" }
    public var scopeGlobal: String { zh ? "全局" : "Global" }
    public var scopeAgentOnly: String { zh ? "Agent 专属" : "Agent-only" }
    public var scopeProject: String { zh ? "项目级" : "Project" }
    public var scopeMultiAgent: String { zh ? "多 Agent 共用" : "Shared" }
    public var sidebarNoAgents: String {
        zh ? "尚未发现已安装 agent——安装 Claude Code / Codex 等后自动识别"
           : "No installed agents found — recognized automatically after installing Claude Code / Codex, etc."
    }

    /// agent 行状态小字（可用 / 结构未知）。
    public func agentRowStatus(available: Bool, skillCount: Int) -> String {
        if available {
            return zh ? "可用 · \(skillCount) skills" : "\(skillCount) skills"
        }
        return zh ? "结构未知" : "Unknown layout"
    }

    // MARK: 导航标题

    public var listTitleAll: String { "Skills" }
    public var listTitleGlobal: String { zh ? "Skills · 全局" : "Skills · Global" }
    public func listTitleAgent(_ id: String) -> String { "Skills · \(id)" }
    public func listTitleProject(_ name: String) -> String { "Skills · \(name)" }
    public func listTitleTag(_ tag: String) -> String { zh ? "Skills · #\(tag)" : "Skills · #\(tag)" }
    public func zoneTitle(_ zone: LifecycleZone) -> String {
        switch zone {
        case .disabled: zh ? "停用区" : "Disabled"
        case .trash: zh ? "回收站" : "Trash"
        }
    }

    // MARK: 列表 / 工具条

    public var searchPrompt: String { zh ? "搜索名称 / 描述 / 项目" : "Search name / description / project" }
    public var noMatchingSkills: String { zh ? "没有匹配的 Skill" : "No Matching Skills" }
    public var adjustFilterOrRescan: String { zh ? "调整筛选或重新扫描" : "Adjust filters or rescan" }
    public var scanNow: String { zh ? "立即扫描" : "Scan Now" }
    public var scanning: String { zh ? "正在扫描…" : "Scanning…" }
    public var importSkill: String { zh ? "导入 skill…" : "Import Skill…" }
    public var installFromGit: String { zh ? "从 git 安装…" : "Install from Git…" }
    public var settingsMenu: String { zh ? "设置…" : "Settings…" }

    // MARK: 状态条

    public var stripIdle: String { zh ? "尚未扫描" : "Not scanned yet" }
    public var stripRunning: String { zh ? "正在扫描…" : "Scanning…" }
    public var stripRunningCompact: String { zh ? "扫描中…" : "Scanning…" }
    public var stripFailed: String { zh ? "扫描失败" : "Scan failed" }
    public func stripDone(agents: Int, skills: Int, time: String) -> String {
        zh ? "完成 · \(agents) agents · \(skills) skills · \(time)"
           : "Done · \(agents) agents · \(skills) skills · \(time)"
    }
    public func stripFailedDetail(_ message: String) -> String {
        zh ? "扫描失败：\(message)" : "Scan failed: \(message)"
    }

    // MARK: Skill 行 / 作用域

    public func scopeBadge(_ scope: SkillScope) -> String {
        switch scope {
        case .global: scopeGlobal
        case .agentOnly: zh ? "专属" : "Dedicated"
        case let .project(_, root): zh ? "项目 \(root.tagName)" : "Project \(root.tagName)"
        case .multiAgent: scopeMultiAgent
        }
    }
    public func scopeDetailText(_ scope: SkillScope) -> String {
        switch scope {
        case let .global(owners): zh ? "全局（\(owners.joined(separator: "、"))）" : "Global (\(owners.joined(separator: ", ")))"
        case let .agentOnly(agentID): zh ? "Agent 专属（\(agentID)）" : "Agent-only (\(agentID))"
        case let .project(agentID, root): zh ? "项目（\(agentID) · \(root.tagName)）" : "Project (\(agentID) · \(root.tagName))"
        case let .multiAgent(ids): zh ? "多 Agent 共用（\(ids.joined(separator: "、"))）" : "Shared (\(ids.joined(separator: ", ")))"
        }
    }
    public var statusEnabledHelp: String { zh ? "已启用" : "Enabled" }
    public var statusDisabledHelp: String { zh ? "已停用" : "Disabled" }
    public var statusUnrecognizedHelp: String { zh ? "结构未知" : "Unknown layout" }
    public var permissionDeniedHelp: String { zh ? "目录权限受限，需在系统设置中授权" : "Directory access restricted — grant access in System Settings" }

    // MARK: 详情

    public var detailPreview: String { zh ? "SKILL.md 预览" : "SKILL.md Preview" }
    public var detailReadingSkillMd: String { zh ? "正在读取 SKILL.md…" : "Reading SKILL.md…" }
    public var detailFiles: String { zh ? "文件清单" : "Files" }
    public var detailListingFiles: String { zh ? "正在列出文件…" : "Listing files…" }
    public var detailHistory: String { zh ? "操作历史" : "History" }
    public var detailTags: String { zh ? "标签" : "Tags" }
    public var detailNewTagPrompt: String { zh ? "新标签名（回车添加）" : "New tag (press Return to add)" }
    public var commonAdd: String { zh ? "添加" : "Add" }
    public var removeTagHelp: String { zh ? "移除标签" : "Remove tag" }
    public var commonLoading: String { zh ? "加载中…" : "Loading…" }
    public var detailNoHistory: String { zh ? "暂无操作记录" : "No history yet" }
    public var detailSnapshots: String { zh ? "历史快照" : "Snapshots" }
    public var detailNoSnapshots: String { zh ? "暂无快照（skill 内容变化时自动记录）" : "No snapshots yet (captured automatically when content changes)" }
    public func restoreSnapshotHelp(_ index: Int) -> String {
        zh ? "恢复 #\(index)（当前内容会先自动存一份快照）" : "Restore #\(index) (current content is snapshotted first)"
    }
    public var opDisable: String { zh ? "停用" : "Disable" }
    public var opEnable: String { zh ? "重新启用" : "Re-enable" }
    public var opMoveToTrash: String { zh ? "移入回收站" : "Move to Trash" }
    public var opInstallToAgents: String { zh ? "安装到其他 agent…" : "Install to Other Agents…" }
    public var disableHelp: String { zh ? "移入统一停用目录，可随时恢复" : "Moves to the unified disabled zone; restore anytime" }
    public var enableHelp: String {
        zh ? "停用时记录了原路径，恢复时原样放回" : "Original path is recorded on disable; restored as-is"
    }
    public var installToAgentsHelp: String {
        zh ? "把此 skill 复制安装到其他 agent 的目录（同名目标不覆盖）"
           : "Copies this skill to other agents' directories (existing same-name targets are never overwritten)"
    }
    public var moveToTrashHelp: String {
        zh ? "移到统一回收站（~/.agentkeeper/trash），可在侧栏「回收站」恢复或彻底删除"
           : "Moves to the unified trash (~/.agentkeeper/trash); restore or purge from the sidebar Trash"
    }
    public var dirDisable: String { zh ? "停用" : "Disable" }
    public var dirEnable: String { zh ? "重新启用" : "Re-enable" }
    public var dirSnapshotRestore: String { zh ? "从快照恢复" : "Snapshot restore" }
    public var dirDelete: String { zh ? "删除" : "Delete" }
    public var dirDistribute: String { zh ? "分发安装" : "Distribute" }
    public var dirUpdateAll: String { zh ? "更新全部副本" : "Update all copies" }

    /// 同名安装区。
    public var landingSameName: String { zh ? "同名安装" : "Same-name Copies" }
    public var landingDiverged: String { zh ? "同名安装（内容不一致）" : "Same-name Copies (content differs)" }
    public var landingUpdateAll: String { zh ? "用此版本更新全部副本…" : "Update All Copies to This Version…" }

    // MARK: 安装面板（跨 agent / git）

    public func installSheetTitle(_ name: String) -> String {
        zh ? "安装「\(name)」到其他 agent" : "Install “\(name)” to Other Agents"
    }
    public var installSheetExplain: String {
        zh ? "安装方式：复制，源文件保持不动；同名目标不会覆盖，内容一致时自动跳过并说明。"
           : "Copies only — sources stay untouched. Same-name targets are never overwritten; identical content is skipped with a note."
    }
    public var installNoTargets: String { zh ? "没有可用目标" : "No Targets Available" }
    public var installNoTargetsDetail: String {
        zh ? "先扫描出已安装的 agent 才能安装" : "Scan for installed agents first to enable installation"
    }
    public var gitSheetTitle: String { zh ? "从 git 安装 skill" : "Install Skill from Git" }
    public var gitURLPlaceholder: String { zh ? "https://…/repo.git 或 ~/本地仓库路径" : "https://…/repo.git or ~/local/repo/path" }
    public var gitFindCandidates: String { zh ? "查找候选" : "Find Candidates" }
    public var gitCloning: String { zh ? "正在 clone / 校验…" : "Cloning / verifying…" }
    public var gitNoSkills: String {
        zh ? "未发现合法 skill（检查 URL 或换本地路径形式）"
           : "No valid skills found (check the URL, or use a local path)"
    }
    public var gitPickSkills: String { zh ? "勾选要安装的 skill：" : "Select skills to install:" }
    public var gitInstallTo: String { zh ? "安装到" : "Install to" }
    public var commonCancel: String { zh ? "取消" : "Cancel" }
    public var commonInstall: String { zh ? "安装" : "Install" }

    // MARK: 生命周期区

    public var zoneDisabledEmpty: String { zh ? "停用区为空" : "Disabled Zone is Empty" }
    public var zoneDisabledEmptyDetail: String {
        zh ? "在 skill 详情页点「停用」即可把副本移入此处（原样保全，随时恢复）"
           : "Click “Disable” on a skill to move a copy here (preserved as-is, restorable anytime)"
    }
    public var zoneTrashEmpty: String { zh ? "回收站为空" : "Trash is Empty" }
    public var zoneTrashEmptyDetail: String {
        zh ? "删除的 skill 会先入回收站；内容原样保全，可恢复或彻底清除"
           : "Deleted skills land in the trash first; content is preserved — restore or purge"
    }
    public var zoneEmptyTrash: String { zh ? "清空回收站" : "Empty Trash" }
    public var zoneEmptyTrashHelp: String { zh ? "彻底删除回收站内全部条目（不可恢复）" : "Permanently deletes every item in the trash (irreversible)" }
    public func zonePurgeTitle(_ name: String) -> String {
        zh ? "彻底删除「\(name)」？" : "Permanently delete “\(name)”?"
    }
    public var zonePurgeButton: String { zh ? "彻底删除" : "Delete Permanently" }
    public func zonePurgeMessage(_ path: String) -> String {
        zh ? "将永久删除 \(path)—— 内容不可恢复。" : "\(path) will be permanently deleted — this cannot be undone."
    }
    public func zoneEmptyTrashTitle(_ count: Int) -> String {
        zh ? "清空回收站（\(count) 条）？" : "Empty Trash (\(count) items)?"
    }
    public var zoneEmptyButton: String { zh ? "清空" : "Empty" }
    public var zoneEmptyTrashMessage: String {
        zh ? "回收站内所有条目将被永久删除——内容不可恢复。"
           : "Everything in the trash will be permanently deleted — this cannot be undone."
    }
    public var zonePerforming: String { zh ? "正在执行…" : "Working…" }
    public var zoneDisabledAt: String { zh ? "停用于" : "Disabled " }
    public var zoneDeletedAt: String { zh ? "删除于" : "Deleted " }
    public var zoneEnableButton: String { zh ? "启用" : "Enable" }
    public var zoneRestoreButton: String { zh ? "恢复" : "Restore" }
    public var zoneRestoreHelp: String {
        zh ? "按 manifest 原路径放回；目标被占用时中止并显示冲突明细"
           : "Restores to the manifest-recorded path; aborts with conflict details if occupied"
    }
    public var zonePurgeRowHelp: String { zh ? "永久删除（不可恢复）" : "Delete permanently (irreversible)" }

    // MARK: 菜单栏面板

    public var menuScanning: String { zh ? "正在扫描…" : "Scanning…" }
    public var menuNoAgents: String { zh ? "尚未发现已安装的 agent" : "No installed agents found" }
    public var menuOpenMain: String { zh ? "打开主窗口" : "Open Main Window" }
    public var menuQuit: String { zh ? "退出 AgentKeeper" : "Quit AgentKeeper" }
    public var menuOpenFinderHelp: String {
        zh ? "在 Finder 中打开该 agent 的 skills 目录" : "Open this agent's skills folder in Finder"
    }

    // MARK: 引导页

    public var onboardingWelcome: String { zh ? "欢迎使用 AgentKeeper" : "Welcome to AgentKeeper" }
    public var onboardingSubtitle: String {
        zh ? "扫描本机 AI agent 的 skill 目录，标记来源作用域，支持安全停用与快照。"
           : "Scans every AI agent's skill folders, tags their scopes, and supports safe disabling with snapshots."
    }
    public var onboardingScanTitle: String { zh ? "一次全量扫描" : "One Full Scan" }
    public var onboardingScanDetail: String {
        zh ? "只读扫描各 agent 的标准 skill 目录；外部改动由系统级文件事件自动增量跟随。"
           : "Read-only scan of each agent's standard skill folders; external changes are followed incrementally via file-system events."
    }
    public var onboardingAuthTitle: String { zh ? "目录授权" : "Folder Access" }
    public var onboardingAuthDetail: String {
        zh ? "扫描仅限用户级与已知项目根，永不递归整个家目录。受限目录会以诊断形式提示你手动授权。"
           : "Scanning stays within user-level and known project roots — never your whole home folder. Restricted folders surface as diagnostics for manual approval."
    }
    public var onboardingDataDirTitle: String { zh ? "~/.agentkeeper 数据目录" : "~/.agentkeeper Data Directory" }
    public var onboardingDataDirDetail: String {
        zh ? "停用的 skill、快照、操作历史与缓存都存放在这里；文件系统是唯一真相，任何时刻都可以从磁盘重建。"
           : "Disabled skills, snapshots, history and caches live here; the file system is the single source of truth — rebuildable from disk at any moment."
    }
    public var onboardingNoOverrideTitle: String { zh ? "不覆盖不打扰" : "Never Overwrites" }
    public var onboardingNoOverrideDetail: String {
        zh ? "遇到冲突一律中止并逐条列出明细；停用/恢复使用原子搬移，失败自动回滚。"
           : "Conflicts always abort with itemized details; disable/restore uses atomic moves with automatic rollback on failure."
    }
    public var onboardingStartScan: String { zh ? "开始扫描本机" : "Scan This Mac" }

    // MARK: 设置

    public var settingsFollowSystem: String { zh ? "跟随系统" : "Follow System" }
    public var settingsAppearance: String { zh ? "外观" : "Appearance" }
    public var settingsTheme: String { zh ? "主题" : "Theme" }
    public var settingsLight: String { zh ? "日间" : "Light" }
    public var settingsDark: String { zh ? "夜间" : "Dark" }
    public var settingsMotion: String { zh ? "动效" : "Motion" }
    public var settingsReduceMotion: String { zh ? "减弱动效" : "Reduce Motion" }
    public var settingsAlwaysReduce: String { zh ? "始终减弱" : "Always Reduce" }
    public var settingsAlwaysNormal: String { zh ? "始终正常" : "Always Full" }
    public var settingsReduceMotionDetail: String {
        zh ? "减弱后列表过渡、详情切换等动画即时呈现。" : "List transitions and detail switches render instantly when reduced."
    }
    public var settingsOnboardingSection: String { zh ? "引导" : "Onboarding" }
    public var settingsShowOnboarding: String { zh ? "重新显示首次引导页" : "Show Onboarding Again" }
    public var settingsOnboardingDetail: String {
        zh ? "重新打开 AgentKeeper 首次启动时的功能引导。" : "Reopens the first-launch onboarding guide."
    }
    public var settingsLanguage: String { zh ? "语言" : "Language" }
    public var settingsLanguageDetail: String {
        zh ? "界面语言即时生效；「跟随系统」按系统首选语言。" : "Applies instantly; “Follow System” uses the system's preferred language."
    }

    // MARK: 总览

    public var overviewTitle: String { zh ? "总览" : "Overview" }
    public func overviewLastScan(_ time: String) -> String {
        zh ? "上次扫描 \(time)" : "Last scan \(time)"
    }
    public var overviewNotScanned: String {
        zh ? "尚未扫描——点击工具栏「立即扫描」开始" : "Not scanned yet — click “Scan Now” in the toolbar to start"
    }
    public var overviewTags: String { zh ? "标签" : "Tags" }
    public var overviewScopeDistribution: String { zh ? "Skill 来源分布" : "Skill Scope Distribution" }

    // MARK: 导入 / 提示

    public var importFailed: String { zh ? "导入失败" : "Import Failed" }
    public var importNoTargetRoots: String {
        zh ? "没有可用的 agent skill 目录（先扫描或检查目录结构）"
           : "No agent skill folders available (scan first, or check directory layout)"
    }
    public var importButtonOK: String { zh ? "好" : "OK" }

    // MARK: 状态条 / 文件清单 / Markdown 预览

    public var stripTapOpenMain: String {
        zh ? "点击打开主窗口 Skill 列表" : "Click to open the main window's skill list"
    }
    public var updateAllTitle: String { zh ? "用此版本更新全部安装副本？" : "Update all installed copies to this version?" }
    public var updateAllButton: String { zh ? "更新（覆盖前自动保存快照）" : "Update (snapshot saved before overwrite)" }
    public var updateAllMessage: String {
        zh ? "将用当前版本覆盖内容不一致的副本；覆盖前每个副本自动保存一份快照。已停用的副本跳过。"
           : "Copies whose content differs will be overwritten; each is snapshotted first. Disabled copies are skipped."
    }
    public func filesList(_ count: Int) -> String {
        zh ? "文件清单（\(count)）" : "Files (\(count))"
    }
    public var showInFinder: String { zh ? "在 Finder 中显示" : "Reveal in Finder" }
    public var openFolder: String { zh ? "打开文件夹" : "Open Folder" }
    public var doubleClickDirHelp: String { zh ? "双击打开该文件夹（Finder 定位）" : "Double-click to open this folder (revealed in Finder)" }
    public var doubleClickFileHelp: String { zh ? "双击在 Finder 中显示此文件" : "Double-click to reveal this file in Finder" }
    public var markdownMissing: String { zh ? "（SKILL.md 不存在或为空）" : "(SKILL.md missing or empty)" }
    public var markdownPreview: String { zh ? "SKILL.md 预览" : "SKILL.md Preview" }
    public var expand: String { zh ? "展开" : "Expand" }
    public var collapse: String { zh ? "折叠" : "Collapse" }
    public var expandHelp: String { zh ? "展开全文" : "Expand full text" }
    public var collapseHelp: String { zh ? "折叠预览" : "Collapse preview" }
}
