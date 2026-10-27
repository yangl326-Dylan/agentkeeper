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
