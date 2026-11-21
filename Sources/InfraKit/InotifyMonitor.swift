#if os(Linux)
import Foundation
import Glibc
import DomainKit

/// inotify 目录监听（Linux，Ubuntu 24.04）。与 FSEventMonitor（macOS）接口与语义对齐：
/// 事件按 latencySeconds 去抖聚合，以「整批路径数组」经 handler 送达（消费方自行过滤聚合）。
///
/// 线程模型：actor 只负责生命周期与聚合；一个专用 Foundation Thread 阻塞 poll
/// 两个 fd（inotify fd + 自管道唤醒 fd），不占 Swift 并发协作池。
/// fd 竞态：stopAll 只置 stopped 并写自管道唤醒，fd 一律由读取线程在退出路径统一
/// close——「actor 关 fd vs 线程正在 poll/read」的竞态从根上消除（详见 FdBox 注释）。
public actor InotifyMonitor: FileMonitoring {
    private let latencySeconds: Double
    /// 整批回调：一个去抖窗口内累积的全部路径一次交割。
    private let handler: @Sendable ([String]) async -> Void
    /// 当前监听会话（stop 后置 nil；start 可重入，先内部 stop 清理）。
    private var box: FdBox?
    /// 去抖窗口内累积的事件路径。
    private var pending: Set<String> = []
    /// 是否已有 flush 在途（首个事件调度，窗口结束取走整批）。
    private var flushScheduled = false
    /// 当前会话是否存活：停止后迟到投递一律丢弃。
    private var running = false
    /// 会话代号：旧会话迟到的 Task（读取线程投递/已排程 flush）凭它自动作废。
    private var sessionID = 0

    public init(
        latencySeconds: Double = 0.5,
        handler: @escaping @Sendable ([String]) async -> Void
    ) {
        self.latencySeconds = latencySeconds
        self.handler = handler
    }

    // MARK: - 生命周期

    public func start(watchingRoots: [URL]) {
        stopAllInternal()   // 可重入：先清上一轮

        guard !watchingRoots.isEmpty else { return }

        let fd = inotify_init1(Int32(IN_CLOEXEC))
        guard fd >= 0 else { return }
        var pipeFds: [Int32] = [-1, -1]
        guard pipe(&pipeFds) == 0 else {
            close(fd)
            return
        }

        // 递归 watch 目录树（FileManager.enumerator 默认含隐藏目录）
        var wdToPath: [Int32: String] = [:]
        for root in watchingRoots {
            for dir in Self.collectDirectories(root.path) {
                let wd = dir.withCString { inotify_add_watch(fd, $0, Self.watchMask) }
                if wd >= 0 { wdToPath[wd] = dir }
            }
        }

        sessionID += 1
        let session = sessionID
        running = true
        pending.removeAll()
        flushScheduled = false

        let box = FdBox(
            inotifyFd: fd,
            wakeReadFd: pipeFds[0],
            wakeWriteFd: pipeFds[1],
            rootPaths: watchingRoots.map(\.path),
            wdToPath: wdToPath
        )
        self.box = box

        // 弱引用持有 actor：未 stopAll 就释放的 monitor，线程最迟在 poll 超时自检退出并收尾 fd
        let thread = Thread { [weak self] in
            Self.readLoop(box: box, session: session, owner: WeakActorRef(value: self))
        }
        thread.name = "agentkeeper.inotify"
        thread.start()
    }

    public func stopAll() {
        stopAllInternal()
    }

    private func stopAllInternal() {
        if let box {
            box.requestStop()   // 置 stopped + 写自管道唤醒；fd 由线程退出路径关闭
            self.box = nil
        }
        running = false
        pending.removeAll()     // 停止后不再交付积压事件
    }

    // MARK: - 聚合去抖

    /// 读取线程整批投递入口：事件进 pending；首个事件调度一次 flush，窗口内新事件只累积。
    func enqueue(_ paths: [String], session: Int) {
        guard running, session == sessionID else { return }   // 旧会话迟到投递丢弃
        for path in paths where !path.isEmpty {
            pending.insert(path)
        }
        guard !flushScheduled, !pending.isEmpty else { return }
        flushScheduled = true
        Task { await self.flushAfterLatency(session: session) }
    }

    private func flushAfterLatency(session: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(latencySeconds * 1_000_000_000))
        guard session == sessionID else { return }   // 旧会话 flush 作废，不动新会话标志
        flushScheduled = false
        guard running, !pending.isEmpty else { return }
        let batch = pending.sorted()
        pending.removeAll()
        await handler(batch)
    }

    // MARK: - 读取线程（非隔离）

    /// 专用读取线程主循环。非隔离：阻塞 poll 不占 Swift 并发协作池。
    /// poll 带超时：除 stopAll 写自管道即时唤醒外，线程每秒自检一次
    /// （actor 是否已释放 / 是否已 stop），保证无人调 stopAll 也能自行收尾。
    private static func readLoop(box: FdBox, session: Int, owner: WeakActorRef) {
        defer { box.closeAll() }   // fd 只由本线程在退出路径关闭（见 FdBox 注释）

        let fds = box.fdSnapshot()
        guard fds.inotify >= 0, fds.wakeRead >= 0 else { return }
        var watchers: [pollfd] = [
            pollfd(fd: fds.inotify, events: Int16(POLLIN), revents: 0),
            pollfd(fd: fds.wakeRead, events: Int16(POLLIN), revents: 0),
        ]
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while !box.isStopped {
            guard let monitor = owner.value else { break }   // actor 已释放：自检退出
            let rc = poll(&watchers, nfds_t(2), 1000)
            if rc < 0 {
                if errno == EINTR { continue }
                break
            }
            if box.isStopped { break }

            if watchers[1].revents != 0 {
                // 自管道被写：stopAll 请求，排空后退出
                _ = read(fds.wakeRead, &buffer, buffer.count)
                break
            }
            if watchers[0].revents == 0 { continue }   // 超时空醒：回顶重查 stopped/weak

            let count = read(fds.inotify, &buffer, buffer.count)
            if count <= 0 {
                if errno == EINTR { continue }
                break
            }
            let paths = decode(buffer: buffer, byteCount: count, box: box)
            if paths.isEmpty { continue }
            // 整批一枚 Task：曾每事件一枚 Task——风暴时数百 Task/秒压爆并发池
            Task { await monitor.enqueue(paths, session: session) }
        }
    }

    /// 解析一次 read 到的 inotify_event 缓冲区，返回需通知的完整路径。
    /// name 为空（len==0）的自我事件用被监听目录路径本身；IN_Q_OVERFLOW 送全量根路径批。
    private static func decode(buffer: [UInt8], byteCount: Int, box: FdBox) -> [String] {
        guard byteCount > 0 else { return [] }
        var paths: [String] = []
        let headerSize = MemoryLayout<inotify_event>.size
        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            // 内核按 4 字节对齐排布事件（name 补齐到 4 的倍数）；loadUnaligned 兜底
            while offset + headerSize <= byteCount {
                let event = raw.loadUnaligned(fromByteOffset: offset, as: inotify_event.self)
                let mask = event.mask
                let nameLen = Int(event.len)

                if (mask & UInt32(IN_Q_OVERFLOW)) != 0 {
                    // 内核事件队列溢出：watch 表已不可信，整批根路径送出提示消费方全量重扫
                    paths.append(contentsOf: box.rootPaths)
                } else if (mask & UInt32(IN_IGNORED)) != 0 {
                    // watch 被内核移除（目录被删等）：仅维护映射，不通知
                    box.removeWatch(wd: event.wd)
                } else if let dirPath = box.path(for: event.wd) {
                    let name: String
                    if nameLen > 0 {
                        let start = offset + headerSize
                        let end = min(start + nameLen, byteCount)
                        var nameEnd = start
                        while nameEnd < end, raw[nameEnd] != 0 { nameEnd += 1 }
                        name = String(decoding: raw[start..<nameEnd], as: UTF8.self)
                    } else {
                        name = ""   // 自我事件（DELETE_SELF/MOVE_SELF）
                    }
                    // 通知位与 watch mask 相同（IN_ISDIR 只是修饰位）
                    if (mask & Self.watchMask) != 0 {
                        paths.append(name.isEmpty ? dirPath : dirPath + "/" + name)
                    }
                    // 新子目录动态补 watch：mkdir 与 rename 移入都算（否则其内部事件不可见）。
                    // 注：树内 rename 只补了顶层 wd 映射，被移动子树的旧映射路径会过期，
                    // 由消费方按根路径聚合/重扫兜底。
                    if (mask & UInt32(IN_ISDIR)) != 0,
                       (mask & (UInt32(IN_CREATE) | UInt32(IN_MOVED_TO))) != 0,
                       !name.isEmpty {
                        box.watchDirectory(dirPath + "/" + name)
                    }
                }
                offset += headerSize + nameLen
            }
        }
        return paths
    }

    /// 递归收集目录树（含隐藏目录；符号链接不跟随展开，避免重复/环）。
    private static func collectDirectories(_ rootPath: String) -> [String] {
        var result = [rootPath]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }   // 单个子树失败不中断整体
        ) else { return result }
        for case let url as URL in enumerator {
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }
            result.append(url.path)
        }
        return result
    }

    /// watch/通知位集合（与 FSEventMonitor 文件级事件语义对齐）。
    fileprivate static let watchMask = UInt32(
        IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE_SELF | IN_MOVE_SELF
    )
}

// MARK: - fd/监听表共享盒

/// actor 与读取线程之间的会话状态盒（@unchecked Sendable）。
/// 设计要点：fd 的 close 只发生在读取线程退出路径（closeAll）；requestStop 只置
/// stopped 并写自管道唤醒——关闭别线程正 poll/read 的 fd 既不可靠唤醒它，fd 号还
/// 可能被复用造成读写错位，这里从根上消除该竞态。NSLock 保护 stopped、fd 与
/// wd→路径映射（动态补 watch 在读取线程内即时生效，不绕 actor）。
private final class FdBox: @unchecked Sendable {
    /// 本次会话监听的根路径（start 后只读；IN_Q_OVERFLOW 全量重扫提示用）。
    let rootPaths: [String]

    private let lock = NSLock()
    private var inotifyFd: Int32
    private var wakeReadFd: Int32
    private var wakeWriteFd: Int32
    private var stopped = false
    private var wdToPath: [Int32: String]

    init(
        inotifyFd: Int32,
        wakeReadFd: Int32,
        wakeWriteFd: Int32,
        rootPaths: [String],
        wdToPath: [Int32: String]
    ) {
        self.inotifyFd = inotifyFd
        self.wakeReadFd = wakeReadFd
        self.wakeWriteFd = wakeWriteFd
        self.rootPaths = rootPaths
        self.wdToPath = wdToPath
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// 线程启动时取 fd 快照（此后 close 只发生在线程自身退出路径，快照值全程有效）。
    func fdSnapshot() -> (inotify: Int32, wakeRead: Int32) {
        lock.lock()
        defer { lock.unlock() }
        return (inotifyFd, wakeReadFd)
    }

    func path(for wd: Int32) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return wdToPath[wd]
    }

    /// 动态补 watch（读取线程解析 IN_CREATE|ISDIR / IN_MOVED_TO|ISDIR 时调用）。
    func watchDirectory(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, inotifyFd >= 0 else { return }
        let wd = path.withCString { inotify_add_watch(inotifyFd, $0, InotifyMonitor.watchMask) }
        if wd >= 0 { wdToPath[wd] = path }
    }

    func removeWatch(wd: Int32) {
        lock.lock()
        defer { lock.unlock() }
        wdToPath[wd] = nil
    }

    /// 请求停止：置 stopped 并写 1 字节自管道，唤醒阻塞中的 poll。
    func requestStop() {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        if wakeWriteFd >= 0 {
            var byte: UInt8 = 1
            _ = write(wakeWriteFd, &byte, 1)
        }
    }

    /// 关闭全部 fd。只允许读取线程在退出路径调用一次；与 requestStop 同锁串行，
    /// 写管道不会落在已关闭的 fd 上。
    func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        for fd in [inotifyFd, wakeReadFd, wakeWriteFd] where fd >= 0 {
            close(fd)
        }
        inotifyFd = -1
        wakeReadFd = -1
        wakeWriteFd = -1
        wdToPath.removeAll()
    }
}

/// actor 弱引用盒（Sendable）：读取线程不强持 actor，monitor 未 stopAll 即释放时线程可自检退出。
private struct WeakActorRef: Sendable {
    weak var value: InotifyMonitor?
}

#endif
