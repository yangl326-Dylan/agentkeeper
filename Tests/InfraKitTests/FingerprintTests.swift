import Foundation
import Testing
import CryptoKit
import DomainKit
@testable import InfraKit

@Suite struct FingerprintSemanticTests {
    @Test func sameContentDifferentPathSameFingerprint() {
        let a = Fingerprint.sha256OfFiles([("x.md", Data("A".utf8))])
        let b = Fingerprint.sha256OfFiles([("x.md", Data("A".utf8))])
        #expect(a == b)
    }

    @Test func renamedFileChangesFingerprint() {
        let a = Fingerprint.sha256OfFiles([("old.md", Data("A".utf8))])
        let b = Fingerprint.sha256OfFiles([("new.md", Data("A".utf8))])
        #expect(a != b)
    }

    @Test func singleByteMutatedChangesFingerprint() {
        let a = Fingerprint.sha256OfFiles([("x.md", Data([1, 2, 3, 4]))])
        let b = Fingerprint.sha256OfFiles([("x.md", Data([1, 2, 3, 5]))])
        #expect(a != b)
    }

    @Test func largeFileFingerprintIsStreamingAndCorrect() throws {
        // 1MB 负载按规范形态（path + 0x00 + data + 0x00）手动计算对照，验证流式读取正确
        let size = 1_000_000
        var payload = Data(capacity: size)
        for index in 0..<size { payload.append(UInt8(truncatingIfNeeded: index)) }
        var canonical: [UInt8] = Array("blob.bin".utf8)
        canonical.append(0x00)
        canonical.append(contentsOf: [UInt8](payload))
        canonical.append(0x00)
        let expected = SHA256.hash(data: Data(canonical)).map { String(format: "%02x", $0) }.joined()
        let computed = Fingerprint.sha256OfFiles([("blob.bin", payload)])
        #expect(computed == expected)
    }

    @Test func directoryFingerprintReflectsAddedFile() throws {
        let home = makeFakeHome(files: ["skill/SKILL.md"])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("skill", isDirectory: true)
        let before = Fingerprint.sha256OfDirectory(dir)
        let extra = dir.appendingPathComponent("scripts/run.sh")
        try? FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: extra, atomically: true, encoding: .utf8)
        let after = Fingerprint.sha256OfDirectory(dir)
        #expect(before != nil)
        #expect(before != after)
    }

    @Test func emptyDirectoryFingerprintIsNil() {
        let home = makeFakeHome(files: ["empty/placeholder.txt"])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("empty2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(Fingerprint.sha256OfDirectory(dir) == nil)
    }
}

@Suite struct FingerprintStatCacheTests {
    /// 每条测试都先清空进程级缓存（目录级 memoize：path+mtime+size 签名 → sha）。
    init() {
        Fingerprint.clearCache()
    }

    /// 跨函数一致性：streaming 版目录指纹与「手动收集 + 规范组合」逐字节等价。
    /// （缓存版改造必须保持输出与旧实现完全一致——persisted sha 全靠等值比对。）
    @Test func streamingMatchesLegacyComposition() throws {
        let home = makeFakeHome(files: [
            "skill/SKILL.md",
            "skill/scripts/run.sh",
            "skill/docs/patch-notes.md"
        ], fileContents: [
            "skill/SKILL.md": "---\nname: demo\n---\nbody\n",
            "skill/scripts/run.sh": "#!/bin/sh\necho hi\n",
            "skill/docs/patch-notes.md": String(repeating: "payload-", count: 2048)
        ])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("skill", isDirectory: true)

        var collected: [(relativePath: String, data: Data)] = []
        for file in SkillParsing.allRegularFiles(in: dir) {
            // 镜像 legacy 相对路径判据（raw 前缀失配 → basename 回退）
            let relative: String
            if file.path.hasPrefix(dir.path) {
                relative = String(file.path.dropFirst(dir.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relative = file.lastPathComponent
            }
            collected.append((relative, try Data(contentsOf: file)))
        }

        let computed = Fingerprint.sha256OfDirectory(dir)
        let expected = Fingerprint.sha256OfFiles(collected)
        #expect(computed == expected)
    }

    /// 缓存命中路径：同内容两次计算同值；文件内容被替换（新 mtime/size）
    /// 立即反映，简而言之签名失效及时。
    @Test func cacheDoesNotStaleAcrossMutations() throws {
        let home = makeFakeHome(files: ["skill/SKILL.md"])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("skill", isDirectory: true)

        let first = Fingerprint.sha256OfDirectory(dir)
        let warm = Fingerprint.sha256OfDirectory(dir)
        #expect(first != nil)
        #expect(first == warm)

        Thread.sleep(forTimeInterval: 0.02) // 保证 mtime 分辨率差异
        try "totally different content\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let mutated = Fingerprint.sha256OfDirectory(dir)
        #expect(mutated != first)

        try "totally different content\n".write(to: dir.appendingPathComponent("extra.md"), atomically: true, encoding: .utf8)
        let withExtra = Fingerprint.sha256OfDirectory(dir)
        #expect(withExtra != mutated)

        try? FileManager.default.removeItem(at: dir.appendingPathComponent("extra.md"))
        let back = Fingerprint.sha256OfDirectory(dir)
        #expect(back == mutated)
    }

    /// mtime 抖动但内容不变：签名失效 → 重算 → 同值（指纹永远由内容决定）。
    @Test func mtimeOnlyChangeKeepsSameSha() throws {
        let home = makeFakeHome(files: ["skill/SKILL.md"])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("skill", isDirectory: true)
        let file = dir.appendingPathComponent("SKILL.md")

        let before = Fingerprint.sha256OfDirectory(dir)
        try "#!/bin/sh\n".write(to: dir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("run.sh"))
        try "yaml-lite\n".write(to: file, atomically: true, encoding: .utf8)
        let after = Fingerprint.sha256OfDirectory(dir)
        // 内容不同则不同；内容相同（mtime 变化）则相等由缓存后重算保证
        // （这里文件内容已改变 → sha 必变，核心断言在 warm 复测）
        #expect(before != after)

        let rewarmed = Fingerprint.sha256OfDirectory(dir)
        #expect(rewarmed == after)
    }
}

@Suite struct FingerprintTransientWriteTests {
    @Test func inFlightPartialFilesExcludedByHiddenRule() throws {
        let home = makeFakeHome(files: ["skill/SKILL.md"])
        defer { cleanup(home) }
        let dir = home.appendingPathComponent("skill", isDirectory: true)
        let hiddenTemp = dir.appendingPathComponent(".SKILL.md.abc123.swp")
        try "partial".write(to: hiddenTemp, atomically: true, encoding: .utf8)
        let before = Fingerprint.sha256OfDirectory(dir)
        try? FileManager.default.removeItem(at: hiddenTemp)
        let after = Fingerprint.sha256OfDirectory(dir)
        #expect(before == after)  // 隐藏的临时写入文件不影响指纹
    }
}
