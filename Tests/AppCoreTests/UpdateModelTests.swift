import Foundation
import Testing
@testable import AppCore

/// 更新状态机：手动检查、版本对比、安装成功/失败、开发态保护。
@Suite struct UpdateModelTests {
    private static func release(_ version: String, withAsset: Bool = true) -> ReleaseInfo {
        ReleaseInfo(
            version: AppVersion(version)!,
            tag: "v\(version)",
            releaseURL: URL(string: "https://github.com/yangl326-Dylan/agentkeeper/releases/tag/v\(version)")!,
            appAssetURL: withAsset
                ? URL(string: "https://github.com/yangl326-Dylan/agentkeeper/releases/download/v\(version)/AgentKeeper-app-macos.zip")
                : nil
        )
    }

    private struct FakeFetcher: ReleaseFetching {
        var release: ReleaseInfo?
        var error: UpdateError?

        func latestRelease() async throws -> ReleaseInfo {
            if let error { throw error }
            guard let release else { throw UpdateError.malformedResponse }
            return release
        }
    }

    private struct FakeDownloader: UpdateDownloading {
        var error: UpdateError?

        func download(from url: URL) async throws -> URL {
            if let error { throw error }
            return URL(fileURLWithPath: "/tmp/fake-update.zip")
        }
    }

    private final class FakeInstaller: AppInstalling, @unchecked Sendable {
        private let lock = NSLock()
        private var storedCalls = 0
        let error: UpdateError?

        init(error: UpdateError? = nil) {
            self.error = error
        }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCalls
        }

        func install(release: ReleaseInfo, zipURL: URL) throws {
            lock.lock()
            storedCalls += 1
            lock.unlock()
            if let error { throw error }
        }
    }

    @MainActor
    private final class TerminateRecorder {
        var called = false
    }

    @MainActor
    private func makeModel(
        current: String = "0.2.0",
        bundleURL: URL = URL(fileURLWithPath: "/Applications/AgentKeeper.app"),
        fetcher: FakeFetcher,
        downloader: FakeDownloader = FakeDownloader(),
        installer: FakeInstaller = FakeInstaller(),
        recorder: TerminateRecorder = TerminateRecorder()
    ) -> UpdateModel {
        UpdateModel(
            currentVersion: AppVersion(current)!,
            bundleURL: bundleURL,
            fetcher: fetcher,
            downloader: downloader,
            installer: installer,
            terminate: { recorder.called = true }
        )
    }

    @MainActor
    @Test func checkFindsNewerVersion() async {
        let model = makeModel(fetcher: FakeFetcher(release: Self.release("0.3.0")))
        await model.check()
        #expect(model.state == .available(Self.release("0.3.0")))
        #expect(model.releasePageURL.absoluteString.contains("v0.3.0"))
    }

    @MainActor
    @Test func checkSameVersionIsUpToDate() async {
        let model = makeModel(fetcher: FakeFetcher(release: Self.release("0.2.0")))
        await model.check()
        #expect(model.state == .upToDate(AppVersion("0.2.0")!))
    }

    @MainActor
    @Test func checkOlderVersionIsUpToDate() async {
        let model = makeModel(fetcher: FakeFetcher(release: Self.release("0.1.9")))
        await model.check()
        #expect(model.state == .upToDate(AppVersion("0.2.0")!))
    }

    @MainActor
    @Test func checkFailureSurfacesMessage() async {
        let model = makeModel(fetcher: FakeFetcher(error: .httpStatus(403)))
        await model.check()
        guard case let .failed(message) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(message.contains("403"))
    }

    @MainActor
    @Test func installSuccessDownloadsThenTerminates() async {
        let installer = FakeInstaller()
        let recorder = TerminateRecorder()
        let model = makeModel(
            fetcher: FakeFetcher(release: Self.release("0.3.0")),
            installer: installer,
            recorder: recorder
        )
        await model.check()
        await model.install()
        #expect(installer.calls == 1)
        #expect(recorder.called)
        #expect(model.state == .installing(Self.release("0.3.0")))
    }

    @MainActor
    @Test func installWithoutAssetFailsWithoutDownloading() async {
        let installer = FakeInstaller()
        let model = makeModel(
            fetcher: FakeFetcher(release: Self.release("0.3.0", withAsset: false)),
            installer: installer
        )
        await model.check()
        await model.install()
        #expect(installer.calls == 0)
        guard case let .failed(message) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(message.contains("安装包"))
    }

    @MainActor
    @Test func installFailureKeepsAppRunning() async {
        let installer = FakeInstaller(error: .installationFailed("boom"))
        let recorder = TerminateRecorder()
        let model = makeModel(
            fetcher: FakeFetcher(release: Self.release("0.3.0")),
            installer: installer,
            recorder: recorder
        )
        await model.check()
        await model.install()
        #expect(installer.calls == 1)
        #expect(!recorder.called)
        guard case let .failed(message) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(message.contains("boom"))
    }

    @MainActor
    @Test func downloadFailureDoesNotInstall() async {
        let installer = FakeInstaller()
        let model = makeModel(
            fetcher: FakeFetcher(release: Self.release("0.3.0")),
            downloader: FakeDownloader(error: .downloadFailed("offline")),
            installer: installer
        )
        await model.check()
        await model.install()
        #expect(installer.calls == 0)
        #expect(model.state != .installing(Self.release("0.3.0")))
    }

    @MainActor
    @Test func developmentBuildCannotInstallInPlace() async {
        let installer = FakeInstaller()
        let model = makeModel(
            bundleURL: URL(fileURLWithPath: "/tmp/.build/debug/AgentKeeper"),
            fetcher: FakeFetcher(release: Self.release("0.3.0")),
            installer: installer
        )
        #expect(!model.canInstallInPlace)
        await model.check()
        await model.install()
        #expect(installer.calls == 0)
        guard case .failed = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
    }
}
