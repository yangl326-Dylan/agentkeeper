import Foundation
import CoreServices
import DomainKit

/// FSEvents 目录监听。事件在回调里按事件到达节流聚合（latency 由 FSEvents 提供），
/// 交给消费方（AppCore）做增量重扫。失焦降频由消费方调用方控制监控节律。
public actor FSEventMonitor: FileMonitoring {
    private let latencySeconds: Double
    private let handler: @Sendable (FileChangeEvent) async -> Void
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?
    private let callbackQueue: DispatchQueue

    public init(
        latencySeconds: Double = 0.5,
        handler: @escaping @Sendable (FileChangeEvent) async -> Void
    ) {
        self.latencySeconds = latencySeconds
        self.handler = handler
        self.callbackQueue = DispatchQueue(label: "agentkeeper.fsevents")
    }

    public func start(watchingRoots: [URL]) {
        stopAllInternal()

        guard !watchingRoots.isEmpty else { return }
        let box = CallbackBox(handler: handler)
        callbackBox = box
        let context = Unmanaged.passRetained(box).toOpaque()

        var contextStruct = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientInfo, count, eventPaths, _, _ in
            let box = Unmanaged<CallbackBox>.fromOpaque(clientInfo!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            for path in paths {
                let event = FileChangeEvent(rootPath: path)
                Task.detached(priority: .utility) {
                    await box.dispatch(event)
                }
            }
        }

        let pathsToWatch = watchingRoots.map(\.path) as CFArray
        guard let streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &contextStruct,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latencySeconds,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(context).release()
            callbackBox = nil
            return
        }

        self.stream = streamRef
        FSEventStreamSetDispatchQueue(streamRef, callbackQueue)
        FSEventStreamStart(streamRef)
    }

    public func stopAll() {
        stopAllInternal()
    }

    private func stopAllInternal() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            // start 时 passRetained 的 box 找回并 release（invalidated 后不会再有回调）——曾每次 re-attach 泄漏一条捕获链
            if let box = callbackBox {
                Unmanaged.passUnretained(box).release()
                self.callbackBox = nil
            }
        }
    }

    /// C 回调 → actor 边界装箱。
    private final class CallbackBox: @unchecked Sendable {
        let handler: @Sendable (FileChangeEvent) async -> Void
        init(handler: @escaping @Sendable (FileChangeEvent) async -> Void) {
            self.handler = handler
        }
        func dispatch(_ event: FileChangeEvent) async {
            await handler(event)
        }
    }
}
