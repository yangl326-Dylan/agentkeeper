# Skill 健康检查 v1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扫描时顺路收集 skill 的客观健康事实（frontmatter 完整性 / 结构异常 / 体积），在详情面板与列表行暴露，零阈值判定。

**Architecture:** 事实在 `SkillParsing.parseDirectory` / `Fingerprint` 扫描时收集，存进 `Skill` 模型（DomainKit）；判定无运行时逻辑——`issues` 就是事实。UI 读模型渲染徽章与区块。Skill 目录为内存重建（不落盘），Codable 兼容仅防御性处理。

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing / macOS 15+

**验证基线命令（每个 Task 复用）：**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift build 2>&1 | grep -cE "error|warning"   # 期望 0
swift test --filter <Suite名> 2>&1 | tail -6
```

---

### Task 1: DomainKit 模型——SkillIssue + Skill 新字段

**Files:**
- Modify: `Sources/DomainKit/CoreModels.swift:122-178`（Skill 与 ParsedSkill）
- Test: `Tests/DomainKitTests/ModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/DomainKitTests/ModelTests.swift` 末尾追加（文件内已有 `scopesCodableRoundTrip` 等 roundtrip 惯例）：

```swift
@Suite struct SkillHealthModelTests {
    /// SkillIssue 编解码 roundtrip。
    @Test func skillIssueRoundTrip() throws {
        let issue = SkillIssue(kind: .missingDescription)
        let data = try JSONEncoder().encode(issue)
        let decoded = try JSONDecoder().decode(SkillIssue.self, from: data)
        #expect(decoded == issue)
    }

    /// 旧 JSON（无新字段）解码得到默认值——防御未来缓存/测试 fixture。
    @Test func skillDecodesLegacyJSONWithoutNewFields() throws {
        var skill = Skill(
            id: "s1", name: "demo", directory: URL(fileURLWithPath: "/tmp/demo"),
            scope: .global(owners: ["claude-code"]), status: .enabled, sha256: "abc",
            frontmatterName: nil, skillDescription: nil, fileCount: 2, lastModified: nil,
            totalBytes: 100, skillMdBytes: 50, issues: [SkillIssue(kind: .emptySkillMd)]
        )
        #expect(skill.totalBytes == 100) // memberwise init 生效
        let data = try JSONEncoder().encode(skill)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["totalBytes", "skillMdBytes", "issues"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Skill.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.totalBytes == 0)
        #expect(legacy.skillMdBytes == 0)
        #expect(legacy.issues.isEmpty)
        #expect(legacy.name == "demo")
    }

    /// ParsedSkill 旧 JSON（无新字段）同样可解码。
    @Test func parsedSkillDecodesLegacyJSONWithoutNewFields() throws {
        let parsed = ParsedSkill(
            directory: URL(fileURLWithPath: "/tmp/demo"), frontmatterName: "demo",
            frontmatterDescription: "d", files: [], sha256: "abc",
            totalBytes: 10, skillMdBytes: 5, issues: [SkillIssue(kind: .emptySkillMd)]
        )
        let data = try JSONEncoder().encode(parsed)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["totalBytes", "skillMdBytes", "issues"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(ParsedSkill.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.totalBytes == 0)
        #expect(legacy.skillMdBytes == 0)
        #expect(legacy.issues.isEmpty)
    }
}
```

（技巧说明：不手写旧版 JSON 字符串——枚举关联值的合成编码形态脆弱。改为「编码现值 → 删掉新字段 key → 再解码」，精确模拟旧数据。）

- [ ] **Step 2: 运行确认失败**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift test --filter SkillHealthModelTests 2>&1 | tail -8
```

Expected: 编译失败，`SkillIssue` / `totalBytes` 不存在。

- [ ] **Step 3: 实现**

`Sources/DomainKit/CoreModels.swift`：

(a) `Skill` struct 内（`lastModified` 之后）加三个存储属性，并把 memberwise init 扩展（带默认值，现有调用点不破坏）：

```swift
    /// 目录内非隐藏常规文件字节数总和（agent 实际加载口径；与 sha256 同一文件集）。
    public var totalBytes: Int = 0
    /// SKILL.md 字节数。
    public var skillMdBytes: Int = 0
    /// 扫描时收集的客观健康事实（缺 frontmatter 字段、空文件、坏链接等）。
    public var issues: [SkillIssue] = []
```

init 参数相应追加 `totalBytes: Int = 0, skillMdBytes: Int = 0, issues: [SkillIssue] = []` 并赋值。

(b) Skill 是 `Codable`——手写 `init(from:)`（`encode(to:)` 保持编译器合成）：

```swift
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        directory = try c.decode(URL.self, forKey: .directory)
        scope = try c.decode(SkillScope.self, forKey: .scope)
        status = try c.decode(SkillStatus.self, forKey: .status)
        sha256 = try c.decode(String.self, forKey: .sha256)
        frontmatterName = try c.decodeIfPresent(String.self, forKey: .frontmatterName)
        skillDescription = try c.decodeIfPresent(String.self, forKey: .skillDescription)
        fileCount = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified)
        totalBytes = try c.decodeIfPresent(Int.self, forKey: .totalBytes) ?? 0
        skillMdBytes = try c.decodeIfPresent(Int.self, forKey: .skillMdBytes) ?? 0
        issues = try c.decodeIfPresent([SkillIssue].self, forKey: .issues) ?? []
    }
```

（struct 内需声明 `private enum CodingKeys: String, CodingKey { case id, name, directory, scope, status, sha256, frontmatterName, skillDescription, fileCount, lastModified, totalBytes, skillMdBytes, issues }`——若已有合成 keys 则显式声明同名。）

(c) `ParsedSkill` 同法：加 `totalBytes / skillMdBytes / issues` 三属性（默认 0/0/[]），init 追加带默认值参数，手写 `init(from:)`（`directory` 用 `decodeIfPresent ?? URL(fileURLWithPath: "/")` 不必要——directory 必有，用 decode；`files` 用 `decodeIfPresent ?? []`）。

(d) 文件内（`Skill` 定义之前）新增：

```swift
/// Skill 客观健康问题类型（扫描时收集的事实，非阈值判定）。
public enum SkillIssueKind: Hashable, Codable, Sendable {
    case missingFrontmatter      // 无 frontmatter 块（正文非空）
    case missingName             // 有块缺 name
    case missingDescription      // 有块缺 description（空串视为缺失）
    case emptySkillMd            // SKILL.md 0 字节或 trim 后为空
    case invalidEncoding         // SKILL.md 非 UTF-8
    case brokenSymlink           // 符号链接目标不存在
}

public struct SkillIssue: Hashable, Codable, Sendable {
    public var kind: SkillIssueKind

    public init(kind: SkillIssueKind) {
        self.kind = kind
    }
}
```

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter SkillHealthModelTests 2>&1 | tail -6
```

Expected: 3 tests passed。

- [ ] **Step 5: 提交**

```bash
git add Sources/DomainKit/CoreModels.swift Tests/DomainKitTests/ModelTests.swift
git commit -m "feat(health): DomainKit 健康事实模型（SkillIssue + 体积字段）"
```

---

### Task 2: FrontmatterParser.parseDetailed

**Files:**
- Modify: `Sources/InfraKit/SkillParsing.swift:8-27`（FrontmatterParser）
- Test: `Tests/InfraKitTests/HealthCheckTests.swift`（新建）

- [ ] **Step 1: 写失败测试**

新建 `Tests/InfraKitTests/HealthCheckTests.swift`：

```swift
import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct FrontmatterDetailedTests {
    @Test func noBlockReportsHasFrontmatterFalse() {
        let d = FrontmatterParser.parseDetailed(markdown: "# Hello\n\nbody")
        #expect(d.hasFrontmatter == false)
        #expect(d.name == nil)
        #expect(d.description == nil)
    }

    @Test func blockWithBothKeysReportsTrue() {
        let md = "---\nname: demo\ndescription: does things\n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == "does things")
    }

    @Test func blockMissingKeysReportsTrueWithNils() {
        let md = "---\nname: demo\n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == nil)
    }

    @Test func unterminatedBlockReportsFalse() {
        let d = FrontmatterParser.parseDetailed(markdown: "---\nname: demo\n\nbody")
        #expect(d.hasFrontmatter == false)
    }

    /// 空 description 归一为 nil（健康检查把空串视为缺失）。
    @Test func emptyValuesNormalizeToNil() {
        let md = "---\nname: demo\ndescription: \n---\n\nbody"
        let d = FrontmatterParser.parseDetailed(markdown: md)
        #expect(d.hasFrontmatter == true)
        #expect(d.name == "demo")
        #expect(d.description == nil)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter FrontmatterDetailedTests 2>&1 | tail -8
```

Expected: 编译失败，无 `parseDetailed`。

- [ ] **Step 3: 实现**

`FrontmatterParser` 改造：`parse` 委托 `parseDetailed`。

```swift
public enum FrontmatterParser {
    /// 解析 SKILL.md 前置块，额外回报是否存在 frontmatter（健康检查用）。
    /// 空串值归一为 nil（视为缺失）。
    public static func parseDetailed(markdown: String) -> (hasFrontmatter: Bool, name: String?, description: String?) {
        guard markdown.hasPrefix("---") else { return (false, nil, nil) }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeFirst() // "---"
        guard let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (false, nil, nil)
        }
        var name: String?
        var description: String?
        for line in lines[..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if name == nil, trimmed.hasPrefix("name:") {
                name = valueAfter("name:", in: trimmed)
            } else if description == nil, trimmed.hasPrefix("description:") {
                description = valueAfter("description:", in: trimmed)
            }
        }
        return (true, normalized(name), normalized(description))
    }

    /// 兼容旧签名：丢弃 hasFrontmatter。
    public static func parse(markdown: String) -> (name: String?, description: String?) {
        let d = parseDetailed(markdown: markdown)
        return (d.name, d.description)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func valueAfter(_ key: String, in line: String) -> String? {
        // ……保留现有实现不动……
    }
}
```

行为说明（可接受的有意变化）：空串 name/description 由「保留空串」变为 `nil`——`SkillDistributor` 的 `name == nil` 校验变严格（空串名视为缺失），`CatalogBuilder` 空串名回退目录名（更合理）。

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter "FrontmatterDetailedTests" 2>&1 | tail -6
```

Expected: 5 tests passed。再跑 `swift test --filter "Frontmatter" 2>&1 | tail -3` 确认既有 frontmatter 相关测试未回归。

- [ ] **Step 5: 提交**

```bash
git add Sources/InfraKit/SkillParsing.swift Tests/InfraKitTests/HealthCheckTests.swift
git commit -m "feat(health): parseDetailed 回报 frontmatter 存在性，空值归一缺失"
```

---

### Task 3: DirectoryFingerprint.totalBytes

**Files:**
- Modify: `Sources/InfraKit/SkillParsing.swift:110-226`（DirectoryFingerprint 与 Fingerprint.fingerprint(of:)）
- Test: `Tests/InfraKitTests/HealthCheckTests.swift`

- [ ] **Step 1: 写失败测试**

`HealthCheckTests.swift` 追加：

```swift
@Suite struct FingerprintTotalBytesTests {
    /// 多文件目录 totalBytes 求和正确；缓存命中后值仍正确。
    @Test func totalBytesSumsRegularFiles() throws {
        Fingerprint.clearCache()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(Array(repeating: UInt8(0x61), count: 100)).write(to: dir.appendingPathComponent("SKILL.md"))
        try Data(repeating: 0x62, count: 250).write(to: dir.appendingPathComponent("a.txt"))
        try Data(repeating: 0x63, count: 50).write(to: dir.appendingPathComponent("b.txt"))

        let first = Fingerprint.fingerprint(of: dir)
        #expect(first.totalBytes == 400)
        // 二次调用走缓存，值不变
        let second = Fingerprint.fingerprint(of: dir)
        #expect(second.totalBytes == 400)
        // 隐藏文件不计入（agent 不加载）
        try Data(repeating: 0x64, count: 999).write(to: dir.appendingPathComponent(".hidden"))
        Fingerprint.clearCache()
        let third = Fingerprint.fingerprint(of: dir)
        #expect(third.totalBytes == 400)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter FingerprintTotalBytesTests 2>&1 | tail -8
```

Expected: 编译失败，无 `totalBytes`。

- [ ] **Step 3: 实现**

`DirectoryFingerprint` 加字段（init 带默认值，既有构造点不破坏）：

```swift
public struct DirectoryFingerprint {
    public var sha256: String?
    public var regularFiles: [URL]
    /// 非隐藏常规文件字节数总和（与 sha256 同一文件集）。
    public var totalBytes: Int

    public init(sha256: String?, regularFiles: [URL], totalBytes: Int = 0) {
        self.sha256 = sha256
        self.regularFiles = regularFiles
        self.totalBytes = totalBytes
    }
}
```

`Fingerprint.fingerprint(of:)`：`files.sort` 之后取 `let totalBytes = files.reduce(0) { $0 + $1.size }`，并把该值传入函数内**全部四处** `DirectoryFingerprint(...)` 构造（顶部 enumerator 为空的早退、缓存命中、readCount==0、末尾正常返回）。顶部早退处无 files，用默认 0 即可。

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter "FingerprintTotalBytesTests|FingerprintSemanticTests|FingerprintTests" 2>&1 | tail -6
```

Expected: 全部通过（既有指纹测试无回归）。

- [ ] **Step 5: 提交**

```bash
git add Sources/InfraKit/SkillParsing.swift Tests/InfraKitTests/HealthCheckTests.swift
git commit -m "feat(health): 指纹顺路产出 totalBytes（零额外 IO）"
```

---

### Task 4: parseDirectory 收集 issues

**Files:**
- Modify: `Sources/InfraKit/SkillParsing.swift:248-265`（SkillParsing.parseDirectory）
- Test: `Tests/InfraKitTests/HealthCheckTests.swift`

- [ ] **Step 1: 写失败测试**

`HealthCheckTests.swift` 追加 fixture 工厂与六个用例：

```swift
@Suite struct ParseDirectoryHealthTests {
    private func makeSkillDir(_ body: (URL) throws -> Void) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body(dir)
        return dir
    }
    private func kinds(_ parsed: ParsedSkill?) -> Set<SkillIssueKind> {
        Set((parsed?.issues ?? []).map(\.kind))
    }

    @Test func healthySkillHasNoIssuesAndCarriesSizes() throws {
        let dir = try makeSkillDir { dir in
            try Data("---\nname: demo\ndescription: ok\n---\n\n# Demo\n".utf8)
                .write(to: dir.appendingPathComponent("SKILL.md"))
            try Data(repeating: 0x61, count: 20).write(to: dir.appendingPathComponent("a.txt"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let parsed = SkillParsing.parseDirectory(dir)
        #expect(parsed != nil)
        #expect(kinds(parsed).isEmpty)
        #expect(parsed?.totalBytes == 20 + "---\nname: demo\ndescription: ok\n---\n\n# Demo\n".utf8.count)
        #expect(parsed?.skillMdBytes == "---\nname: demo\ndescription: ok\n---\n\n# Demo\n".utf8.count)
    }

    @Test func emptySkillMdReported() throws {
        let dir = try makeSkillDir { dir in
            try Data().write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.emptySkillMd])
    }

    @Test func missingFrontmatterReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("# Just body\n".utf8).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.missingFrontmatter])
    }

    @Test func missingNameAndDescriptionReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("---\nother: x\n---\n\nbody".utf8).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.missingName, .missingDescription])
    }

    @Test func invalidEncodingReported() throws {
        let dir = try makeSkillDir { dir in
            try Data([0xFF, 0xFE, 0xFD]).write(to: dir.appendingPathComponent("SKILL.md"))
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.invalidEncoding])
    }

    @Test func brokenSymlinkReported() throws {
        let dir = try makeSkillDir { dir in
            try Data("---\nname: demo\ndescription: ok\n---\n\nbody".utf8)
                .write(to: dir.appendingPathComponent("SKILL.md"))
            try FileManager.default.createSymbolicLink(
                at: dir.appendingPathComponent("dangling"),
                withDestinationURL: dir.appendingPathComponent("no-such-target")
            )
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(kinds(SkillParsing.parseDirectory(dir)) == [.brokenSymlink])
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter ParseDirectoryHealthTests 2>&1 | tail -10
```

Expected: 编译失败（ParsedSkill 无 `totalBytes` 之外的构造参数——实际是断言失败：issues 恒为空）。以实际失败形态为准。

- [ ] **Step 3: 实现**

`SkillParsing.parseDirectory` 整体替换：

```swift
    /// 判断目录是否是 skill：含 SKILL.md 即是；解析 frontmatter、文件清单与健康事实一并返回。
    public static func parseDirectory(_ directory: URL) -> ParsedSkill? {
        let fileManager = FileManager.default
        let skillMd = directory.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillMd.path) else { return nil }

        let fingerprint = Fingerprint.fingerprint(of: directory)
        let skillMdBytes = (try? fileManager.attributesOfItem(atPath: skillMd.path))?[.size] as? Int ?? 0

        var issues: [SkillIssue] = []
        let markdown: String
        do {
            markdown = try String(contentsOf: skillMd, encoding: .utf8)
        } catch {
            // 解码失败只报 invalidEncoding，不再叠加 emptySkillMd（单因汇报）
            issues.append(SkillIssue(kind: .invalidEncoding))
            return ParsedSkill(
                directory: directory,
                frontmatterName: nil,
                frontmatterDescription: nil,
                files: fingerprint.regularFiles,
                sha256: fingerprint.sha256 ?? "",
                totalBytes: fingerprint.totalBytes,
                skillMdBytes: skillMdBytes,
                issues: issues
            )
        }

        if skillMdBytes == 0 || markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(SkillIssue(kind: .emptySkillMd))
        } else {
            let front = FrontmatterParser.parseDetailed(markdown: markdown)
            if !front.hasFrontmatter {
                issues.append(SkillIssue(kind: .missingFrontmatter))
            } else {
                if front.name == nil { issues.append(SkillIssue(kind: .missingName)) }
                if front.description == nil { issues.append(SkillIssue(kind: .missingDescription)) }
            }
        }

        // 符号链接目标存在性（枚举本身跳过 symlink，这里单独轻量扫一遍）
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) {
            scan: for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                      values.isSymbolicLink == true
                else { continue }
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) { continue }
                issues.append(SkillIssue(kind: .brokenSymlink))
                break scan
            }
        }

        let front = FrontmatterParser.parseDetailed(markdown: markdown)
        return ParsedSkill(
            directory: directory,
            frontmatterName: front.name,
            frontmatterDescription: front.description,
            files: fingerprint.regularFiles,
            sha256: fingerprint.sha256 ?? "",
            totalBytes: fingerprint.totalBytes,
            skillMdBytes: skillMdBytes,
            issues: issues
        )
    }
```

注意两点：
- 空文件分支里 `parseDetailed` 仍会执行（frontmatterName 为 nil，语义正确），但 issues 只含 `emptySkillMd`。
- `front` 在尾部调用一次（空文件时 markdown=""，返回 (false,nil,nil)，name/desc 均 nil，与旧行为一致）。

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter "ParseDirectoryHealthTests" 2>&1 | tail -8
```

Expected: 6 tests passed。再跑 `swift test --filter "Collector|CatalogBuilder" 2>&1 | tail -3` 确认采集/构建无回归。

- [ ] **Step 5: 提交**

```bash
git add Sources/InfraKit/SkillParsing.swift Tests/InfraKitTests/HealthCheckTests.swift
git commit -m "feat(health): parseDirectory 收集六类客观健康事实"
```

---

### Task 5: CatalogBuilder 透传

**Files:**
- Modify: `Sources/InfraKit/CatalogBuilder.swift:25-37`（Skill 构造处）
- Test: `Tests/InfraKitTests/CatalogBuilderTests.swift`

- [ ] **Step 1: 写失败测试**

`CatalogBuilderTests.swift` 末尾追加（fixture 抄文件内既有惯例：顶层 `makeFakeHome(files:fileContents:)` / `cleanup(_:)` 助手 + `agent(_ roots:)` 私有构造）：

```swift
@Suite struct CatalogBuilderHealthTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    @Test func buildCarriesHealthFacts() throws {
        let home = makeFakeHome(
            files: [".claude/skills/demo/SKILL.md"],
            fileContents: [".claude/skills/demo/SKILL.md": "---\nname: demo\n---\nbody"]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: [root])])
        let demo = skills.first { $0.name == "demo" }
        #expect(demo != nil)
        // 有 name 缺 description → 恰好一条 missingDescription
        #expect(demo?.issues.map(\.kind) == [.missingDescription])
        let mdBytes = "---\nname: demo\n---\nbody".utf8.count
        #expect(demo?.skillMdBytes == mdBytes)
        #expect(demo!.totalBytes >= mdBytes)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter CatalogBuilderTests 2>&1 | tail -8
```

Expected: 新断言失败（issues 为空）。

- [ ] **Step 3: 实现**

`CatalogBuilder.swift` 的 `Skill(...)` 构造追加三个参数：

```swift
                            fileCount: parsed.files.count,
                            lastModified: lastModified(of: parsed),
                            totalBytes: parsed.totalBytes,
                            skillMdBytes: parsed.skillMdBytes,
                            issues: parsed.issues
```

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter CatalogBuilderTests 2>&1 | tail -4
```

Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/InfraKit/CatalogBuilder.swift Tests/InfraKitTests/CatalogBuilderTests.swift
git commit -m "feat(health): catalog 构建透传健康事实"
```

---

### Task 6: L10n 文案

**Files:**
- Modify: `Sources/AppCore/L10n.swift`（`menuShowInFinder` 附近）
- Test: `Tests/AppCoreTests/L10nTests.swift`

- [ ] **Step 1: 写失败测试**

`L10nTests.swift` 追加（套内已有 `menuAgentRowStringsAreLocalized` 模式）：

```swift
    /// 健康检查文案：双语非空且中英不同。
    @Test func healthStringsAreLocalized() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(!zh.healthSectionTitle.isEmpty)
        #expect(zh.healthSectionTitle != en.healthSectionTitle)
        #expect(!zh.healthBadgeHelp.isEmpty)
        #expect(zh.healthBadgeHelp != en.healthBadgeHelp)
        let kinds: [SkillIssueKind] = [
            .missingFrontmatter, .missingName, .missingDescription,
            .emptySkillMd, .invalidEncoding, .brokenSymlink,
        ]
        for kind in kinds {
            #expect(!zh.healthIssueText(kind).isEmpty)
            #expect(!en.healthIssueText(kind).isEmpty)
            #expect(zh.healthIssueText(kind) != en.healthIssueText(kind))
        }
        #expect(zh.healthFilesCount(3).contains("3"))
        #expect(en.healthFilesCount(3).contains("3"))
        #expect(zh.healthFilesCount(3) != en.healthFilesCount(3))
    }
```

文件头需 `import DomainKit`（若缺）。

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter L10nTests 2>&1 | tail -8
```

Expected: 编译失败。

- [ ] **Step 3: 实现**

`L10n.swift`（`menuFilterAgentHelp` 之后追加；文件已 import DomainKit 则不动，缺则补）：

```swift
    // MARK: 健康检查

    public var healthSectionTitle: String { zh ? "健康" : "Health" }
    public var healthBadgeHelp: String { zh ? "存在健康问题" : "Has health issues" }

    public func healthIssueText(_ kind: SkillIssueKind) -> String {
        switch kind {
        case .missingFrontmatter:
            zh ? "SKILL.md 缺少 frontmatter 块" : "SKILL.md is missing its frontmatter block"
        case .missingName:
            zh ? "frontmatter 缺少 name 字段" : "Frontmatter is missing the name field"
        case .missingDescription:
            zh ? "frontmatter 缺少 description 字段" : "Frontmatter is missing the description field"
        case .emptySkillMd:
            zh ? "SKILL.md 是空的" : "SKILL.md is empty"
        case .invalidEncoding:
            zh ? "SKILL.md 不是有效的 UTF-8 文本" : "SKILL.md is not valid UTF-8 text"
        case .brokenSymlink:
            zh ? "目录内存在指向空目标的符号链接" : "A symlink points to a missing target"
        }
    }

    public func healthFilesCount(_ count: Int) -> String {
        zh ? "\(count) 个文件" : "\(count) files"
    }
```

- [ ] **Step 4: 运行确认通过**

```bash
swift test --filter L10nTests 2>&1 | tail -4
```

Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/AppCore/L10n.swift Tests/AppCoreTests/L10nTests.swift
git commit -m "feat(health): 健康问题中英文案"
```

---

### Task 7: UI——健康区块组件 + 详情嵌入 + 行徽章

**Files:**
- Create: `Sources/AgentKeeperUI/SkillHealthSection.swift`
- Modify: `Sources/AgentKeeperUI/RootView.swift:291-317`（SkillRowView 徽章）、`:570-584`（SkillDetailContent body 插入区块）
- Test: `Tests/AgentKeeperTests/ProbeButton.swift`（ProbeRender suite 追加渲染探针）

- [ ] **Step 1: 写失败探针**

`ProbeButton.swift` 的 `ProbeRender` 内追加：

```swift
    /// 健康区块与列表行徽章：渲染出真实像素。
    @Test func healthSectionAndBadgeRenderToPixels() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        var sick = env.catalogStore.current[0]
        sick.totalBytes = 53_000
        sick.skillMdBytes = 3_100
        sick.issues = [SkillIssue(kind: .missingDescription), SkillIssue(kind: .brokenSymlink)]
        let content = VStack(spacing: 12) {
            SkillRowView(skill: sick, l10n: env.l10n)
                .frame(width: 280)
            SkillHealthSection(skill: sick, l10n: env.l10n)
                .frame(width: 280, alignment: .leading)
            SkillHealthSection(
                skill: env.catalogStore.current[1],
                l10n: env.l10n
            )
            .frame(width: 280, alignment: .leading)
        }
        .frame(width: 300, height: 400)
        let hosting = NSHostingView(rootView: content.environment(env))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png: Data = rep.representation(using: .png, properties: [:])!
        try FileManager.default.createDirectory(atPath: "/tmp/ak-ui", withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: "/tmp/ak-ui/probe-health.png"))
    }
```

- [ ] **Step 2: 运行确认失败**

```bash
swift test --filter ProbeRender 2>&1 | tail -8
```

Expected: 编译失败，无 `SkillHealthSection`。

- [ ] **Step 3: 实现组件（新文件）**

`Sources/AgentKeeperUI/SkillHealthSection.swift`：

```swift
import SwiftUI
import AppCore
import DomainKit

/// 详情面板健康区块：客观问题逐条列出 + 体积事实；无问题时只显示事实行（零噪音）。
struct SkillHealthSection: View {
    let skill: Skill
    var l10n: L10n = L10n(lang: .zhHans)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.healthSectionTitle)
                .font(.headline)
            ForEach(skill.issues, id: \.kind) { issue in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(l10n.healthIssueText(issue.kind))
                        .font(.callout)
                }
            }
            Text(factLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var factLine: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(skill.totalBytes), countStyle: .file)
        let md = ByteCountFormatter.string(fromByteCount: Int64(skill.skillMdBytes), countStyle: .file)
        return "\(total) · \(l10n.healthFilesCount(skill.fileCount)) · SKILL.md \(md)"
    }
}
```

（`ForEach(skill.issues, id: \.kind)` 成立的前提是同类 kind 不重复——parseDirectory 保证每类最多一条。）

- [ ] **Step 4: 嵌入详情面板 + 列表行徽章**

`RootView.swift` `SkillDetailContent.body` 的 `scopeBadge(skill)` 之后插入一行：

```swift
                scopeBadge(skill)
                SkillHealthSection(skill: skill, l10n: env.l10n)
                tagsSection(skill)
```

`SkillRowView.body` 的 `Spacer()` 之后、scope 徽章之前插入：

```swift
            Spacer()
            if !skill.issues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help(l10n.healthBadgeHelp)
            }
            Text(l10n.scopeBadge(skill.scope))
```

- [ ] **Step 5: 运行探针确认通过**

```bash
swift test --filter ProbeRender 2>&1 | tail -4
open /tmp/ak-ui/probe-health.png   # 人工目检：徽章黄色、问题文案、事实行
```

Expected: 探针通过 + 目检正常。

- [ ] **Step 6: 提交**

```bash
git add Sources/AgentKeeperUI/SkillHealthSection.swift Sources/AgentKeeperUI/RootView.swift Tests/AgentKeeperTests/ProbeButton.swift
git commit -m "feat(health): 详情健康区块 + 列表行问题徽章"
```

---

### Task 8: 全量验证 + 文档 + 手工验收

- [ ] **Step 1: 全量构建与测试**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift build 2>&1 | grep -cE "error|warning"   # 期望 0
swift test --no-parallel 2>&1 | tail -2        # 期望全绿（约 400+）
```

- [ ] **Step 2: README 更新**

- 功能清单（`## 功能`）追加一条：`- 🩺 **健康检查**：frontmatter 完整性、空文件 / 坏链接等结构异常逐项列出；体积事实一目了然（不做主观阈值判定）`
- Roadmap 勾选：`- [ ] Skill 健康检查（frontmatter / 体积警告）` → `- [x] Skill 健康检查 v1（frontmatter 完整性 / 结构异常 / 体积事实）`

- [ ] **Step 3: 构建安装真机验收**

```bash
scripts/build-app.sh release
osascript -e 'quit app "AgentKeeper"' 2>/dev/null
pkill -9 -f "AgentKeeper.app/Contents/MacOS/AgentKeeper" 2>/dev/null; sleep 1
rm -rf /Applications/AgentKeeper.app; cp -R AgentKeeper.app /Applications/
open /Applications/AgentKeeper.app
```

验收点：
1. 主窗口选一个本机存在问题的 skill（可先 `ak list` 找一个手造问题目录，如缺 description 的 skill）→ 详情面板显示健康区块与问题文案
2. 正常 skill → 只显示体积事实行
3. 列表行有问题 skill 出现黄色 ⚠️

- [ ] **Step 4: 提交推送**

```bash
git add README.md
git commit -m "docs: 功能清单与 Roadmap 补健康检查 v1"
git push
```
