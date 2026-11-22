import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct AtomicMoverTests {
    @Test func unknownVolumeFallsBackToOptimisticRenameInsteadOfThrowing() throws {
        // 卷判定取不到（st_dev 不可得，如部分容器挂载点/CI runner /tmp）→
        // 不再抛「无法确定所在物理卷」，乐观 rename + EXDEV 兜底（2026-11-22 CI 回归）。
        // source 指向不存在路径 → attributesOfFileSystem 必失败 → 走未知卷分支。
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("nonexistent/skill", isDirectory: true)
        let destination = home.appendingPathComponent("dst/skill", isDirectory: true)

        let strategy = try AtomicMover.volumeStrategy(source: source, destination: destination, fileManager: .default)
        #expect(strategy == .rename)
    }

    @Test func crossDeviceErrorWordingContract() {
        // Foundation Linux 的 EXDEV 报错文案形态契约（execute 兜底依赖此匹配）
        #expect(AtomicMover.isCrossDeviceError(NSError(domain: NSPOSIXErrorDomain, code: 18)))
        #expect(AtomicMover.isCrossDeviceError(AtomicMoverError.underlying(path: "/x", note: "rename failed: cross-device link")))
        #expect(!AtomicMover.isCrossDeviceError(AtomicMoverError.verifyFailed(path: "/x")))
    }

    @Test func sameVolumeMoveIsRenameAtomic() throws {
        let home = makeFakeHome(files: ["src/skill-a/SKILL.md", "src/skill-a/scripts/run.sh"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("src/skill-a", isDirectory: true)
        let destination = home.appendingPathComponent("dst/skill-a", isDirectory: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let mover = AtomicMover()
        let plan = try mover.planMove(source: source, destination: destination)
        try mover.execute(plan)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("scripts/run.sh").path))
    }

    @Test func failedExecuteLeavesRollbackInstruction() throws {
        // 计划成功后环境被破坏（目标父目录被删）→ 执行中断 → 什么都不丢，可回滚
        let home = makeFakeHome(files: ["src/skill-a/SKILL.md"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("src/skill-a", isDirectory: true)
        let destinationParent = home.appendingPathComponent("dst-inner", isDirectory: true)
        let destination = destinationParent.appendingPathComponent("skill-a", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let mover = AtomicMover()
        let plan = try mover.planMove(source: source, destination: destination)

        // 破坏执行前提：目标父目录消失
        try FileManager.default.removeItem(at: destinationParent)
        do {
            try mover.execute(plan)
            Issue.record("expected failure")
        } catch {
            // 回滚是安全幂等的：源必须完好如初
            try mover.rollback(plan)
            #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test func destinationOccupiedIsRejectedByConflictCheck() throws {
        let home = makeFakeHome(files: [
            "src/skill-a/SKILL.md",
            "dst/skill-a/SKILL.md",
        ])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("src/skill-a", isDirectory: true)
        let destination = home.appendingPathComponent("dst/skill-a", isDirectory: true)
        let mover = AtomicMover()
        #expect(throws: AtomicMoverError.destinationOccupied(path: destination.path)) {
            try mover.planMove(source: source, destination: destination)
        }
    }

    @Test func verifyFingerprintMatchesAfterMove() throws {
        let home = makeFakeHome(
            files: ["src/skill-a/SKILL.md", "src/skill-a/b.bin"],
            fileContents: ["src/skill-a/SKILL.md": "内容", "src/skill-a/b.bin": "二进制/内容"]
        )
        defer { cleanup(home) }
        let source = home.appendingPathComponent("src/skill-a", isDirectory: true)
        let destination = home.appendingPathComponent("dst/skill-a", isDirectory: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let mover = AtomicMover()
        let sha = Fingerprint.sha256OfDirectory(source)
        let plan = try mover.planMove(source: source, destination: destination)
        try mover.execute(plan)
        #expect(Fingerprint.sha256OfDirectory(destination) == sha)
    }
}
