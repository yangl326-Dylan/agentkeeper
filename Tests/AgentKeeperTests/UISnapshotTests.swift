import Foundation
import Testing
import DomainKit
import InfraKit
import AppCore
import SwiftUI
@testable import AgentKeeperUI

/// UI 离屏快照管线：ImageRenderer 渲染真实视图层级出 PNG（目检 + 回归）。
/// 已知离屏限制（渲染器伪影，目检时忽略）：
/// - List / ScrollView 整体不出内容（→ 🚫 或空白）；Button/TextField 等控件为 🚫 占位。
/// - 因此内容型视图（行/详情正文）抽为可独立渲染的 struct 供快照引用。
@MainActor
enum UISnapshot {
    /// 渲染 view 为 PNG 并写入 /tmp/ak-ui/。
    @discardableResult
    static func render(_ name: String, view: some View, size: CGSize? = nil) throws -> URL {
        var content: AnyView = AnyView(view)
        if let size {
            content = AnyView(content.frame(width: size.width, height: size.height))
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "ui-snapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed: \(name)"])
        }
        let directory = URL(fileURLWithPath: "/tmp/ak-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(name).png")
        try png.write(to: output)
        return output
    }
}

/// 测试装配：假 home + 注入 catalog 的 env。
@MainActor
struct UIWiring {
    let env: AppEnvironment
    let home: URL

    init() {
        home = makeFakeHomeCore(files: ["dummy"])
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        self.env = env
    }

    /// demo catalog：2 agent × 2 skill + 全局共享 skill；每个 skill 目录带真实文件（SKILL.md + 附件），让预览/清单有内容。
    static func demoSkills(home: URL) -> [Skill] {
        var skills: [Skill] = []
        let owners = ["agent-0", "agent-1"]
        for (agentIndex, agent) in owners.enumerated() {
            for name in ["review", "docs-writer"] {
                let path = home.appendingPathComponent("\(agent)/skills/\(name)", isDirectory: true)
                writeSkillFiles(at: path, name: name, description: "\(name) 的用途说明")
                skills.append(Skill(
                    id: path.path,
                    name: name,
                    directory: path,
                    scope: .agentOnly(agentID: agent),
                    sha256: "sha-\(agentIndex)-\(name)",
                    frontmatterName: name,
                    skillDescription: "\(name) 的用途说明",
                    fileCount: 3,
                    lastModified: Date(timeIntervalSinceNow: -3600)
                ))
            }
        }
        // 全局（同铺设）：真实目录在 home 外，仅作 catalog 展示
        skills.append(Skill(
            id: "/shared/common",
            name: "common-sharing",
            directory: URL(fileURLWithPath: "/shared/common", isDirectory: true),
            scope: .global(owners: owners),
            sha256: "sha-global",
            frontmatterName: "common-sharing",
            skillDescription: "全局共享 skill",
            fileCount: 2
        ))
        return skills
    }

    /// 写入 SKILL.md + 2 个附件（总 3 文件，与 fileCount 一致）。
    private static func writeSkillFiles(at directory: URL, name: String, description: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let skillMd = """
        ---
        name: \(name)
        ---

        \(description) 的 SKILL.md 正文。
        """
        try? skillMd.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try? "参考内容\n".write(to: directory.appendingPathComponent("reference.md"), atomically: true, encoding: .utf8)
        try? "{}\n".write(to: directory.appendingPathComponent("meta.json"), atomically: true, encoding: .utf8)
    }
}

func makeFakeHomeCore(files: [String]) -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("ak-ui-fixture-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for relative in files {
        let target = home.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "placeholder\n".write(to: target, atomically: true, encoding: .utf8)
    }
    return home
}

@MainActor
@Suite struct UISnapshotTests {
    @Test func renderOnboarding() throws {
        let wiring = UIWiring()
        defer { try? FileManager.default.removeItem(at: wiring.home) }
        try UISnapshot.render("onboarding", view:
            OnboardingView(hasCompleted: .constant(false))
                .environment(wiring.env),
            size: CGSize(width: 680, height: 640)
        )
    }

    /// 列表行内容（真实 SkillRowView 像素；行删除 chips/图标/文案回归）。
    @Test func renderSkillRows() throws {
        let wiring = UIWiring()
        defer { try? FileManager.default.removeItem(at: wiring.home) }
        let skills = wiring.env.catalogStore.current
        try UISnapshot.render("rows", view:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(skills) { skill in
                    SkillRowView(skill: skill)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white)
                }
            }
            .padding(8),
            size: CGSize(width: 480, height: 360)
        )
    }

    /// 详情正文（真实 SkillDetailContent；含标签 chips）。
    @Test func renderDetailContent() throws {
        let wiring = UIWiring()
        defer { try? FileManager.default.removeItem(at: wiring.home) }
        // 给第一个 skill 打标签 → 详情出现 chips
        let skill = wiring.env.catalogStore.current[0]
        wiring.env.tagService.addTag("写作", toSkillID: skill.id)
        // 第二组同名铺设（agent-1 的 review）→ 落点面板出现（含分歧？不分歧仅并列）
        try UISnapshot.render("detail-content", view:
            SkillDetailContent(
                env: wiring.env,
                skill: skill,
                showInstallSheet: .constant(false),
                confirmUpdateAll: .constant(false)
            )
            .background(Color.white),
            size: CGSize(width: 520, height: 980)
        )
    }

    /// 安装面板空态（无 agent 时的 ContentUnavailableView 路径）。
    @Test func renderSheetInstallEmptyState() throws {
        let wiring = UIWiring()
        defer { try? FileManager.default.removeItem(at: wiring.home) }
        let skill = wiring.env.catalogStore.current.first { $0.name == "review" }!
        try UISnapshot.render("sheet-install", view: InstallToAgentSheet(skill: skill).environment(wiring.env))
    }

    /// 状态条（手动扫描反馈：完成文案带时间戳 + skill 数）。
    @Test func renderScanStatusStrip() throws {
        var scan = ScanPhaseState()
        scan.phase = .complete
        scan.agentCount = 1
        scan.lastCompletedAt = Date(timeIntervalSince1970: 1_800_000_123)
        try UISnapshot.render("scan-strip", view:
            ScanStatusStrip(scan: scan, skillsCount: 3)
                .padding(12)
                .background(Color.white),
            size: CGSize(width: 320, height: 60)
        )
    }
}
