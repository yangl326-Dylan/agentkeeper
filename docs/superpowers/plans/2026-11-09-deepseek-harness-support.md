# DeepSeek Harness 支持实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AgentKeeper 收录 DeepSeek Harness（`~/.dsh/skills`，目录包 + 扁平 `.md` 双形态）并将同名遮蔽判定升级到 deepseek（官方 rank 100 > 400）。发 v0.5.0。

**Architecture:** 声明式 `AgentSpec` 加一个字面量；`SkillParsing` 新增扁平文件解析；`SkillCollector` 枚举分支收 root 直属 `.md`；`Skill.layout` 字段驱动 UI 只读降级；`SkillShadowPolicy` 加一行。用户已授权免确认推进。

**Tech Stack:** Swift 6 / Swift Testing / SwiftUI（macOS 15+）

验证命令（每 Task 复用）：

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null; sleep 1
swift build 2>&1 | grep -cE "error|warning"          # 期望 0
swift test --filter <Suite> 2>&1 | tail -2
```

---

### Task 1: DomainKit——SkillLayout 枚举 + Skill.layout 字段

**Files:**
- Modify: `Sources/DomainKit/CoreModels.swift`（Skill 附近新增枚举；Skill 属性/init/CodingKeys/init(from:)）
- Test: `Tests/DomainKitTests/ModelTests.swift`（SkillHealthModelTests 既有两用例扩展）

- [x] **Step 1: 失败测试**——`Tests/DomainKitTests/ModelTests.swift` 的 `skillDecodesLegacyJSONWithoutNewFields` 内：

构造处追加 `layout: .flatFile`：

```swift
        let skill = Skill(
            id: "s1", name: "demo", directory: URL(fileURLWithPath: "/tmp/demo"),
            scope: .global(owners: ["claude-code"]), status: .enabled, sha256: "abc",
            frontmatterName: nil, skillDescription: nil, fileCount: 2, lastModified: nil,
            totalBytes: 100, skillMdBytes: 50, issues: [SkillIssue(kind: .emptySkillMd)],
            shadowedBy: "s0", shadowedCount: 2,
            layout: .flatFile
        )
        #expect(skill.layout == .flatFile)
```

移除键列表加 `layout`：

```swift
        for key in ["totalBytes", "skillMdBytes", "issues", "shadowedBy", "shadowedCount", "layout"] {
```

legacy 断言追加：

```swift
        #expect(legacy.layout == .directoryPackage)
```

- [x] **Step 2: 跑测试确认失败**（`cannot find 'layout' in scope`）

```bash
swift test --filter SkillHealthModelTests 2>&1 | grep -E "error:" | head -3
```

- [x] **Step 3: 实现**——`CoreModels.swift`，Skill 声明前加：

```swift
/// skill 文件形态（DeepSeek Harness 支持目录包与扁平单文件两种）。
public enum SkillLayout: String, Hashable, Codable, Sendable {
    /// `<name>/SKILL.md` 目录包（绝大多数 agent 的约定）。
    case directoryPackage
    /// root 直属 `<name>.md` 单文件（dsh 语义）。
    case flatFile
}
```

Skill 属性（shadowedCount 之后）：

```swift
    /// 文件形态；legacy 数据默认目录包。
    public var layout: SkillLayout = .directoryPackage
```

init 参数（`shadowedCount: Int = 0` 之后）：

```swift
        layout: SkillLayout = .directoryPackage
```

init 体赋值 `self.layout = layout`；CodingKeys 追加 `case layout`；`init(from:)` 追加：

```swift
        layout = try c.decodeIfPresent(SkillLayout.self, forKey: .layout) ?? .directoryPackage
```

- [x] **Step 4: 测试通过** `swift test --filter SkillHealthModelTests 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): SkillLayout 形态字段"`

### Task 2: SkillParsing.parseFlatFile + ParsedSkill.isFlatFile

**Files:**
- Modify: `Sources/DomainKit/CoreModels.swift`（ParsedSkill 加 `isFlatFile`）
- Modify: `Sources/InfraKit/SkillParsing.swift`（parseFlatFile）
- Test: `Tests/InfraKitTests/SkillParsingTests.swift`（新增 `FlatFileParsingTests` suite；该文件已存在则追加 suite）

- [x] **Step 1: 失败测试**——新建 suite：

```swift
@Suite struct FlatFileParsingTests {
    /// 扁平 md：frontmatter name 优先；files=[自身]；指纹=文件内容。
    @Test func parsesFrontmatterAndFingerprint() throws {
        let home = makeFakeHome(
            files: [".dsh/skills/demo.md"],
            fileContents: [".dsh/skills/demo.md": "---\nname: demo\ndescription: d\n---\nBody"]
        )
        defer { cleanup(home) }
        let file = home.appendingPathComponent(".dsh/skills/demo.md")
        let parsed = try #require(SkillParsing.parseFlatFile(at: file))
        #expect(parsed.frontmatterName == "demo")
        #expect(parsed.frontmatterDescription == "d")
        #expect(parsed.files == [file.standardizedFileURL])
        #expect(parsed.skillMdBytes == parsed.totalBytes)
        #expect(parsed.issues.isEmpty)
        #expect(parsed.isFlatFile)
        #expect(!parsed.sha256.isEmpty)
    }

    /// 无 frontmatter → name 缺省文件名；报 missingFrontmatter/missingName/missingDescription。
    @Test func bareMarkdownFallsBackToFilename() throws {
        let home = makeFakeHome(files: [".dsh/skills/bare.md"], fileContents: [".dsh/skills/bare.md": "Just text"])
        defer { cleanup(home) }
        let parsed = try #require(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/bare.md")))
        #expect(parsed.frontmatterName == nil)
        #expect(parsed.issues.contains { $0.kind == .missingFrontmatter })
    }

    /// 非 md / 空文件：非 md 返回 nil；空文件报 emptySkillMd。
    @Test func rejectsNonMdAndFlagsEmpty() throws {
        let home = makeFakeHome(
            files: [".dsh/skills/note.txt", ".dsh/skills/empty.md"],
            fileContents: [".dsh/skills/note.txt": "x", ".dsh/skills/empty.md": ""]
        )
        defer { cleanup(home) }
        #expect(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/note.txt")) == nil)
        let empty = try #require(SkillParsing.parseFlatFile(at: home.appendingPathComponent(".dsh/skills/empty.md")))
        #expect(empty.issues.contains { $0.kind == .emptySkillMd })
    }
}
```

- [x] **Step 2: 确认失败**（`parseFlatFile`/`isFlatFile` 不存在）
- [x] **Step 3: 实现**

`CoreModels.swift` ParsedSkill 追加（issues 之后）：

```swift
    /// true = 扁平单文件 skill（directory 字段此时指向文件本体 URL）。
    public var isFlatFile: Bool = false
```

init 参数 `issues: [SkillIssue] = []` 后加 `isFlatFile: Bool = false`，体赋值。

`SkillParsing.swift`（parseDirectory 之后、同 enum 内）：

```swift
    /// 解析扁平 skill 文件（DeepSeek Harness 语义：root 直属 `<name>.md`）。
    /// directory 指向文件本体 URL；frontmatter 缺省时 name 由上层用文件名兜底。
    public static func parseFlatFile(at file: URL) -> ParsedSkill? {
        let fileManager = FileManager.default
        guard file.pathExtension.lowercased() == "md" else { return nil }
        let data = (try? Data(contentsOf: file)) ?? Data()
        let totalBytes = data.count
        let markdown = String(data: data, encoding: .utf8)
        // 解码失败只报 invalidEncoding（单因汇报，同 parseDirectory）
        guard let markdown else {
            return ParsedSkill(
                directory: file.standardizedFileURL,
                files: [file.standardizedFileURL],
                sha256: sha256OfFiles([(relativePath: file.lastPathComponent, data: data)]),
                totalBytes: totalBytes,
                skillMdBytes: totalBytes,
                issues: [SkillIssue(kind: .invalidEncoding)],
                isFlatFile: true
            )
        }
        var issues: [SkillIssue] = []
        if totalBytes == 0 || markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(SkillIssue(kind: .emptySkillMd))
        }
        let front = FrontmatterParser.parseDetailed(markdown: markdown)
        if !front.hasFrontmatter {
            issues.append(SkillIssue(kind: .missingFrontmatter))
        } else {
            if front.name == nil { issues.append(SkillIssue(kind: .missingName)) }
            if front.description == nil { issues.append(SkillIssue(kind: .missingDescription)) }
        }
        return ParsedSkill(
            directory: file.standardizedFileURL,
            frontmatterName: front.name,
            frontmatterDescription: front.description,
            files: [file.standardizedFileURL],
            sha256: sha256OfFiles([(relativePath: file.lastPathComponent, data: data)]),
            totalBytes: totalBytes,
            skillMdBytes: totalBytes,
            issues: issues,
            isFlatFile: true
        )
    }
```

注意：`ParsedSkill` 既有 init 参数顺序为 `directory, frontmatterName, frontmatterDescription, files, sha256, totalBytes, skillMdBytes, issues`（均有缺省的靠后）——上面按此顺序传参。

- [x] **Step 4: 通过** `swift test --filter FlatFileParsingTests 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): 扁平 skill 文件解析"`

### Task 3: SkillCollector 收 root 直属扁平文件

**Files:**
- Modify: `Sources/InfraKit/SkillCollector.swift`
- Test: `Tests/InfraKitTests/SkillCollectorTests.swift`（无则新建，模式同 ShadowRelationTests 的 makeFakeHome）

- [x] **Step 1: 失败测试**

```swift
import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// DeepSeek Harness 扁平 skill 收集：root 直属 `<name>.md`；子目录内扁平不收。
@Suite struct SkillCollectorFlatTests {
    @Test func collectsRootFlatMdAndSkipsNested() {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/top.md",
                ".dsh/skills/nested/inner.md",
                ".dsh/skills/.hidden.md",
                ".dsh/skills/ignored.txt",
                ".dsh/skills/SKILL.md",
            ],
            fileContents: [
                ".dsh/skills/top.md": "---\nname: top\ndescription: t\n---\nT",
                ".dsh/skills/nested/inner.md": "---\nname: inner\ndescription: i\n---\nI",
                ".dsh/skills/.hidden.md": "h",
                ".dsh/skills/ignored.txt": "x",
                ".dsh/skills/SKILL.md": "s",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent(".dsh/skills", isDirectory: true)
        let parsed = SkillCollector().collect(inRoot: root, agentID: "deepseek")
        let flatNames = parsed.filter { $0.isFlatFile }.map { $0.frontmatterName ?? "" }
        // root 直属 top.md 收集；nested/inner.md、隐藏、非 md、游离 SKILL.md 均不收
        #expect(flatNames == ["top"])
    }

    @Test func flatAndPackageCoexist() {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/pack/SKILL.md",
                ".dsh/skills/pack.md",
            ],
            fileContents: [
                ".dsh/skills/pack/SKILL.md": "---\nname: pack\ndescription: pkg\n---\nP",
                ".dsh/skills/pack.md": "---\nname: pack\ndescription: flat\n---\nF",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent(".dsh/skills", isDirectory: true)
        let parsed = SkillCollector().collect(inRoot: root, agentID: "deepseek")
        #expect(parsed.count == 2)
        #expect(parsed.filter { !$0.isFlatFile }.first?.frontmatterDescription == "pkg")
        #expect(parsed.filter { $0.isFlatFile }.first?.frontmatterDescription == "flat")
    }
}
```

- [x] **Step 2: 确认失败**（isFlatFile 恒 false / inner.md 未隔离）
- [x] **Step 3: 实现**——`SkillCollector.collect` 改为：

```swift
    public func collect(inRoot root: URL, agentID: AgentID) -> [ParsedSkill] {
        var results = collectRecursive(rootPath: root.path)
            .compactMap { SkillParsing.parseDirectory(at: URL(fileURLWithPath: $0)) }
        results.append(contentsOf: collectFlat(rootPath: root.path))
        return results
    }

    /// root 直属扁平 `<name>.md`（DeepSeek Harness「直属平铺条目」语义）。
    /// 子目录内扁平文件不收；隐藏文件跳过；游离的根级 SKILL.md 不是 skill 名。
    private func collectFlat(rootPath: String) -> [ParsedSkill] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: rootPath) else { return [] }
        return contents
            .filter { !$0.hasPrefix(".") && $0 != "SKILL.md" && $0.lowercased().hasSuffix(".md") }
            .sorted()
            .compactMap { SkillParsing.parseFlatFile(at: URL(fileURLWithPath: rootPath + "/" + $0)) }
    }
```

- [x] **Step 4: 通过 + 既有收集器回归** `swift test --filter "SkillCollector" 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): 收集 root 直属扁平 skill"`

### Task 4: CatalogBuilder 接线 layout

**Files:**
- Modify: `Sources/InfraKit/CatalogBuilder.swift`（build 内 Skill 构造加 layout）
- Test: `Tests/InfraKitTests/ShadowRelationTests.swift` 旁新增 `Tests/InfraKitTests/DeepSeekCatalogTests.swift`

- [x] **Step 1: 失败测试**

```swift
import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// deepseek 收录后的 catalog 链路：双形态扫描 + layout 标注。
@Suite struct DeepSeekCatalogTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    @Test func catalogMarksFlatLayout() {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/pack/SKILL.md",
                ".dsh/skills/flat-one.md",
            ],
            fileContents: [
                ".dsh/skills/pack/SKILL.md": "---\nname: pack\ndescription: pkg\n---\nP",
                ".dsh/skills/flat-one.md": "---\nname: flat-one\ndescription: flat\n---\nF",
            ]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".dsh/skills", isDirectory: true),
            owners: ["deepseek"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("deepseek", roots: [root])])
        #expect(skills.count == 2)
        let flat = try! #require(skills.first { $0.layout == .flatFile })
        #expect(flat.name == "flat-one")
        #expect(flat.skillDescription == "flat")
        guard case let .agentOnly(owner) = flat.scope else {
            Issue.record("expected agentOnly, got \(flat.scope)")
            return
        }
        #expect(owner == "deepseek")
        #expect(skills.first { $0.layout == .directoryPackage }?.name == "pack")
    }
}
```

（`try!` 在 @Test 内不可用则改 `try #require`——测试函数签名加 `throws`。）

- [x] **Step 2: 确认失败**（layout 恒 directoryPackage）
- [x] **Step 3: 实现**——`CatalogBuilder.build` 的 Skill 构造尾部（`issues: parsed.issues` 后）追加：

```swift
                            layout: parsed.isFlatFile ? .flatFile : .directoryPackage
```

- [x] **Step 4: 通过** `swift test --filter "DeepSeekCatalogTests|CatalogBuilder" 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): catalog 标注 skill 形态"`

### Task 5: AgentSpec 收录 deepseek

**Files:**
- Modify: `Sources/InfraKit/AgentSpec.swift`（BuiltInAgents.deepseek + all）
- Test: `Tests/InfraKitTests/AgentSpecTests.swift`（ids 集合断言）

- [x] **Step 1: 失败测试**——AgentSpecTests 首用例的 Set 字面量加 `"deepseek"`（cursor 之后）；追加用例：

```swift
    /// DeepSeek Harness：用户级 + 项目级 .dsh/skills；无项目注册中心（.none）。
    @Test func deepseekHarnessSpec() {
        let spec = BuiltInAgents.spec(for: "deepseek")
        #expect(spec?.displayName == "DeepSeek Harness")
        #expect(spec?.skillRootCandidates == [".dsh/skills"])
        #expect(spec?.projectSkillSubpaths == [".dsh/skills"])
        #expect(spec?.projectRootDiscovery == .none)
    }
```

- [x] **Step 2: 确认失败**
- [x] **Step 3: 实现**——`BuiltInAgents` 内 cursor 之后：

```swift
    /// DeepSeek Harness（developer preview）：官方 rank 文档 100 项目.dsh / 400 用户.dsh；
    /// ~/.agents/skills（rank 500）仍归 agents-shared，v1 不接入。
    public static let deepseek = AgentSpec(
        id: "deepseek",
        displayName: "DeepSeek Harness",
        detectionSubpaths: [".dsh"],
        skillRootCandidates: [".dsh/skills"],
        projectSkillSubpaths: [".dsh/skills"],
        icon: "wand.and.stars"
    )
```

`all` 追加 `deepseek`（cursor 之后）：

```swift
    public static let all: [AgentSpec] = [
        claudeCode, openCode, codex, gemini, openClaw,
        pi, ohMyPi, sharedAgents, qwen, cursor, deepseek,
    ]
```

- [x] **Step 4: 通过 + 全 InfraKit 回归** `swift test --filter "AgentSpecTests|ScanSchedulerTests|UserAgentConfigTests" 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): 内置 DeepSeek Harness agent"`

### Task 6: SkillShadowPolicy 升级 deepseek

**Files:**
- Modify: `Sources/InfraKit/CatalogBuilder.swift`（precedence switch）
- Test: `Tests/InfraKitTests/ShadowRelationTests.swift`（追加 deepseek 用例）

- [x] **Step 1: 失败测试**——ShadowRelationTests 追加：

```swift
    /// deepseek 有官方 rank 文档（项目 .dsh=100 > 用户 .dsh=400）→ 同 claude-code 判定。
    @Test func deepseekUserCopyShadowedByProjectCopy() throws {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/demo/SKILL.md",
                "projects/atlas/.dsh/skills/demo/SKILL.md",
            ],
            fileContents: [
                ".dsh/skills/demo/SKILL.md": "---\nname: demo\ndescription: user\n---\nU",
                "projects/atlas/.dsh/skills/demo/SKILL.md": "---\nname: demo\ndescription: proj\n---\nP",
            ]
        )
        defer { cleanup(home) }
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("projects/atlas", isDirectory: true))
        let projectSkillRoot = SkillRoot(
            path: projectRoot.path.appendingPathComponent(".dsh/skills", isDirectory: true),
            owners: ["deepseek"],
            level: .project(projectRoot)
        )
        let userRoot = SkillRoot(
            path: home.appendingPathComponent(".dsh/skills", isDirectory: true),
            owners: ["deepseek"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("deepseek", roots: [userRoot, projectSkillRoot])])
        #expect(skills.count == 2)
        let project = try #require(skills.first { $0.skillDescription == "proj" })
        let user = try #require(skills.first { $0.skillDescription == "user" })
        #expect(user.shadowedBy == project.id)
        #expect(project.shadowedCount == 1)
    }
```

- [x] **Step 2: 确认失败**（shadowedBy nil）
- [x] **Step 3: 实现**——`SkillShadowPolicy.precedence`：

```swift
    public static func precedence(for agentID: AgentID) -> Precedence {
        switch agentID {
        case "claude-code", "deepseek": .projectOverUser
        default: .none
        }
    }
```

- [x] **Step 4: 通过** `swift test --filter "ShadowRelationTests" 2>&1 | tail -2`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): 遮蔽判定覆盖 deepseek（官方 rank project>user）"`

### Task 7: UI——扁平 skill 只读降级 + 预览/文件清单适配

**Files:**
- Modify: `Sources/AppCore/L10n.swift`（flatReadOnlyNotice）
- Modify: `Sources/AgentKeeperUI/SkillPreviewModel.swift`（loadMarkdown/loadFiles flat 分支——新增 loadMarkdownFile/loadFlatFiles）
- Modify: `Sources/AgentKeeperUI/RootView.swift`（SkillDetailContent.task 分支 + operationButtons 降级）
- Test: `Tests/AppCoreTests/L10nTests.swift`（追加断言）

- [x] **Step 1: 失败测试**——L10nTests `effectStringsAreLocalized` 后追加：

```swift
    /// 扁平 skill 只读降级文案：双语非空且不同。
    @Test func flatReadOnlyNoticeIsLocalized() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(!zh.flatReadOnlyNotice.isEmpty)
        #expect(zh.flatReadOnlyNotice != en.flatReadOnlyNotice)
    }
```

- [x] **Step 2: 确认失败**
- [x] **Step 3: 实现**

L10n.swift（effectCrossNote 之后）：

```swift
    /// 扁平 skill 在线操作降级提示。
    public var flatReadOnlyNotice: String {
        zh ? "扁平 skill（单文件）暂不支持在线操作（停用 / 安装到其他 agent / 移入回收站）"
           : "Flat (single-file) skills do not support in-app operations yet (disable / install / trash)"
    }
```

SkillPreviewModel.swift 追加：

```swift
    /// 扁平 skill：读文件本体（skill.directory 即文件 URL）。
    static func loadMarkdownFile(_ file: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                return content
            }
            return nil
        }.value
    }

    /// 扁平 skill：文件清单即单文件自身。
    static func loadFlatFileEntry(_ file: URL) async -> [FileListEntry] {
        await Task.detached(priority: .userInitiated) { [path = file.standardizedFileURL.path] in
            [FileListEntry(path: StandardAgentAdapter.dropPrivatePrefix(path), isDirectory: false)]
        }.value
    }
```

（`dropPrivatePrefix` 是 `static` internal——同模块 AgentKeeperUI 不可见则改 `public`，或内联裁前缀逻辑：`path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path`。）

RootView.swift `.task(id: skill.id)` 内替换加载两行：

```swift
            async let md = skill.layout == .flatFile
                ? SkillPreviewModel.loadMarkdownFile(skill.directory)
                : SkillPreviewModel.loadMarkdown(skillDir: skill.directory)
            async let fs = skill.layout == .flatFile
                ? SkillPreviewModel.loadFlatFileEntry(skill.directory)
                : SkillPreviewModel.loadFiles(skillDir: skill.directory)
```

`operationButtons(_ skill:)` 开头改为：

```swift
        let isDisabled = skill.status == .disabled
        let pending = env.store.state.operation
        let l = env.l10n
        if skill.layout == .flatFile {
            Text(l.flatReadOnlyNotice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280, alignment: .leading)
            return
        }
```

（ViewBuilder 内不能用裸 `return` 早期的 body 分支——operationButtons 非 ViewBuilder（返回 some View 的普通函数），`return` 可用；若编译器报错则改 `@ViewBuilder` + if/else 两分支。）

- [x] **Step 4: 通过** `swift test --filter "L10nTests" 2>&1 | tail -2 && swift build 2>&1 | grep -cE "error|warning"`
- [x] **Step 5: Commit** `git commit -m "feat(deepseek): 扁平 skill 详情只读降级 + 预览适配"`

### Task 8: 全量验证 + README + 真机 + 发 v0.5.0

- [x] **Step 1: 全量**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null; sleep 1
swift build 2>&1 | grep -cE "error|warning"   # 0
swift test --no-parallel 2>&1 | tail -1        # 全绿（基线 429+）
```

- [x] **Step 2: README**——支持 agent 清单处补 DeepSeek Harness；功能清单补「扁平 skill」；spec 状态同步 commit
- [x] **Step 3: 真机 fixture**（测完清理）

```bash
mkdir -p ~/.dsh/skills/pack ~/.dsh/skills
printf -- '---\nname: demo-pack\ndescription: 目录包形态\n---\nP' > ~/.dsh/skills/pack/SKILL.md
printf -- '---\nname: demo-flat\ndescription: 扁平形态\n---\nF' > ~/.dsh/skills/demo-flat.md
sleep 8   # 等自动扫描
```

验收（截图目检）：侧栏出现 DeepSeek Harness（2 skills）；demo-pack 详情正常（操作按钮在）；demo-flat 详情显示只读降级文案 + 预览/文件清单正常。

```bash
rm -rf ~/.dsh   # 清理（本机无真实 dsh）
```

- [x] **Step 4: 发版**——`scripts/build-app.sh` 版本 `0.5.0`/`CFBundleVersion 6`；`docs/releases/v0.5.0.md` 中英（DeepSeek Harness 收录 + 扁平 skill + 遮蔽升级 + 已知盲区）；arm64/x86_64 分建 → lipo → 组装签名 → ditto/zip → 冒烟（版本号 + ak doctor）→ commit + tag v0.5.0 → `gh release create v0.5.0 -R yangl326-Dylan/agentkeeper --notes-file` → `releases/latest` 终验 → /Applications 安装 → push main+tag
