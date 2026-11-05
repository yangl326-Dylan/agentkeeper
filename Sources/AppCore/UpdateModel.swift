import Foundation
import AppKit

/// 设置页更新状态机（仅手动触发；外部不显示任何角标/红点）。
@MainActor
@Observable
public final class UpdateModel {
    public enum State: Equatable, Sendable {
        case idle
        case checking
        case upToDate(AppVersion)
        case available(ReleaseInfo)
        case downloading(ReleaseInfo)
        case installing(ReleaseInfo)
        case failed(String)
    }

    public private(set) var state: State = .idle

    /// 当前 App 版本（开发态回退 0.0.0）。
    public let currentVersion: AppVersion
    /// 只有以 `.app` 运行时才允许原地替换。
    public let canInstallInPlace: Bool

    private let fetcher: any ReleaseFetching
    private let downloader: any UpdateDownloading
    private let installer: any AppInstalling
    private let bundleURL: URL
    private let terminate: @MainActor () -> Void
    private var lastRelease: ReleaseInfo?

    public init(
        currentVersion: AppVersion = .currentBundleVersion,
        bundleURL: URL = Bundle.main.bundleURL,
        fetcher: any ReleaseFetching = GitHubReleaseClient(),
        downloader: any UpdateDownloading = URLSessionUpdateDownloader(),
        installer: any AppInstalling = AppUpdateInstaller(),
        terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.currentVersion = currentVersion
        self.bundleURL = bundleURL
        self.fetcher = fetcher
        self.downloader = downloader
        self.installer = installer
        self.terminate = terminate
        self.canInstallInPlace = bundleURL.pathExtension.lowercased() == "app"
    }

    /// 检查中/下载中/安装中：禁用重复操作。
    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        case .idle, .upToDate, .available, .failed: return false
        }
    }

    /// 失败时的兜底入口（已取到 Release 则用其页面，否则仓库 Releases 首页）。
    public var releasePageURL: URL {
        lastRelease?.releaseURL ?? GitHubReleaseClient.fallbackReleasePage
    }

    /// 当前可安装的 Release（UI 决定是否显示「立即更新」）。
    public var availableRelease: ReleaseInfo? {
        if case let .available(release) = state { return release }
        return nil
    }

    // MARK: - 操作

    /// 手动检查（唯一的联网入口）。
    public func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await fetcher.latestRelease()
            lastRelease = release
            if release.version > currentVersion {
                state = .available(release)
            } else {
                state = .upToDate(currentVersion)
            }
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// 下载并安装；成功后退出 App，由后台脚本替换并重启。
    public func install() async {
        guard case let .available(release) = state else { return }
        guard canInstallInPlace else {
            state = .failed(Self.message(for: UpdateError.notAnAppBundle(bundleURL.path)))
            return
        }
        guard let assetURL = release.appAssetURL else {
            state = .failed("该 Release 未提供 App 安装包，请打开 Release 页面手动下载。")
            return
        }

        state = .downloading(release)
        do {
            let zipURL = try await downloader.download(from: assetURL)
            state = .installing(release)
            let installer = self.installer
            try await Task.detached(priority: .userInitiated) {
                try installer.install(release: release, zipURL: zipURL)
            }.value
            terminate()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
