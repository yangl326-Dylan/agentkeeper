import Foundation
import DomainKit

/// 原子搬移计划：source→destination 的一组步骤，失败按步骤栈反向回滚。
/// 同物理卷：一步 rename（发布前校验目标父目录存在）；
/// 跨物理卷：copy→verify（内容指纹）→delete 源三步，任一步失败回滚。
public enum AtomicMoverError: Error, Hashable {
    case sourceMissing(path: String)
    case destinationOccupied(path: String)
    case destinationParentMissing(path: String)
    case verifyFailed(path: String)
    case backupFailed(path: String)
    case underlying(path: String, note: String)
}

public struct MovePlan: Sendable {
    public enum Strategy: Sendable, Hashable {
        case rename
        case copyVerifyDelete
    }

    public var source: URL
    public var destination: URL
    public var strategy: Strategy
    /// 搬移前的内容指纹（成功后的 verify 基准）。
    public var expectedSha256: String?
}

/// 原子搬移引擎（生命周期操作/快照恢复共用）。
public struct AtomicMover: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - 计划

    /// 制定计划；冲突检测在此把守：目标被占用即拒绝，绝不覆盖。
    /// 平面搬移计划。expectedSha256 可选传入：调用方已持有源指纹时免二次全树哈希
    ///（disable/enable 流程曾算两遍——manifest 一遍、planMove 一遍）。
    public func planMove(source: URL, destination: URL, expectedSha256: String? = nil) throws -> MovePlan {
        guard fileManager.fileExists(atPath: source.path) else {
            throw AtomicMoverError.sourceMissing(path: source.path)
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw AtomicMoverError.destinationOccupied(path: destination.path)
        }
        let parent = destination.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else {
            throw AtomicMoverError.destinationParentMissing(path: parent.path)
        }
        let strategy: MovePlan.Strategy
        do {
            strategy = try Self.volumeStrategy(source: source, destination: destination, fileManager: fileManager)
        } catch {
            throw AtomicMoverError.underlying(path: source.path, note: "\(error)")
        }
        return MovePlan(
            source: source,
            destination: destination,
            strategy: strategy,
            expectedSha256: expectedSha256 ?? Fingerprint.sha256OfDirectory(source) ?? ""
        )
    }

    static func volumeStrategy(source: URL, destination: URL, fileManager: FileManager) throws -> MovePlan.Strategy {
        // 用文件系统设备号比较物理卷（比 URLResourceKey.volumeURL 兼容性更好）。
        func deviceNumber(of url: URL, fallback: URL) throws -> Int {
            for candidate in [url, fallback] {
                if let attrs = try? fileManager.attributesOfFileSystem(forPath: candidate.path),
                   let number = attrs[.systemNumber] as? Int,
                   number != 0 {
                    return number
                }
            }
            throw AtomicMoverError.underlying(path: url.path, note: "无法确定所在物理卷")
        }
        // 判同卷看目标父目录（目标本身可能尚不存在）
        let sourceDevice = try deviceNumber(of: source, fallback: source.deletingLastPathComponent())
        let destinationDevice = try deviceNumber(
            of: destination.deletingLastPathComponent(),
            fallback: destination.deletingLastPathComponent().deletingLastPathComponent()
        )
        return sourceDevice == destinationDevice ? .rename : .copyVerifyDelete
    }

    // MARK: - 执行

    public func execute(_ plan: MovePlan) throws {
        switch plan.strategy {
        case .rename:
            do {
                try fileManager.moveItem(at: plan.source, to: plan.destination)
            } catch {
                throw AtomicMoverError.underlying(path: plan.source.path, note: "\(error)")
            }
        case .copyVerifyDelete:
            do {
                try fileManager.copyItem(at: plan.source, to: plan.destination)
            } catch {
                throw AtomicMoverError.underlying(path: plan.source.path, note: "copy 失败: \(error)")
            }
            let destinationSha = Fingerprint.sha256OfDirectory(plan.destination) ?? ""
            guard destinationSha == plan.expectedSha256 else {
                // 校验失败：撤掉复制品，源不动
                try? fileManager.removeItem(at: plan.destination)
                throw AtomicMoverError.verifyFailed(path: plan.destination.path)
            }
            do {
                try fileManager.removeItem(at: plan.source)
            } catch {
                // 删源失败不算执行失败（副本已就绪并校验）；报告给上层
                try? fileManager.copyItem(at: plan.destination, to: plan.source)
                throw AtomicMoverError.underlying(path: plan.source.path, note: "删除源失败: \(error)")
            }
        }
    }

    // MARK: - 回滚

    /// 反向操作：把 destination 放回 source。失败重复却安全（先复制回较安全）。
    public func rollback(_ plan: MovePlan) throws {
        if fileManager.fileExists(atPath: plan.destination.path) {
            if !fileManager.fileExists(atPath: plan.source.path) {
                switch plan.strategy {
                case .rename:
                    try fileManager.moveItem(at: plan.destination, to: plan.source)
                case .copyVerifyDelete:
                    try fileManager.copyItem(at: plan.destination, to: plan.source)
                }
            }
            try fileManager.removeItem(at: plan.destination)
        }
    }
}
