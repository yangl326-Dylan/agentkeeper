import Foundation

/// 更新流程错误（UI 直接展示技术细节，外围文案由 L10n 提供）。
public enum UpdateError: Error, Equatable, Sendable, LocalizedError {
    case network(String)
    case httpStatus(Int)
    case malformedResponse
    case invalidRemoteVersion(String)
    case invalidAssetURL(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case notAnAppBundle(String)
    case targetNotWritable(String)
    case unzipFailed(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .network(detail):
            return "网络请求失败：\(detail)"
        case let .httpStatus(code):
            return "GitHub 返回 HTTP \(code)"
        case .malformedResponse:
            return "GitHub Release 响应无法解析"
        case let .invalidRemoteVersion(raw):
            return "远端版本号无法解析：\(raw)"
        case let .invalidAssetURL(url):
            return "更新包地址不合法：\(url)"
        case let .downloadFailed(detail):
            return "下载更新包失败：\(detail)"
        case let .verificationFailed(detail):
            return "更新包校验失败：\(detail)"
        case let .notAnAppBundle(path):
            return "当前运行形态不支持原地更新（不是 .app）：\(path)"
        case let .targetNotWritable(path):
            return "没有写入权限：\(path)"
        case let .unzipFailed(detail):
            return "解压更新包失败：\(detail)"
        case let .installationFailed(detail):
            return "安装更新失败：\(detail)"
        }
    }
}

/// GitHub 最新 Release 的归一化信息。
public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let tag: String
    public let releaseURL: URL
    /// `AgentKeeper-app-macos.zip` 资产地址；缺失时为 nil（仍可打开 Release 页面手动下载）。
    public let appAssetURL: URL?
    public let appAssetSize: Int?

    public init(
        version: AppVersion,
        tag: String,
        releaseURL: URL,
        appAssetURL: URL?,
        appAssetSize: Int? = nil
    ) {
        self.version = version
        self.tag = tag
        self.releaseURL = releaseURL
        self.appAssetURL = appAssetURL
        self.appAssetSize = appAssetSize
    }
}

/// 远端版本查询接口（测试注入 fake）。
public protocol ReleaseFetching: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

/// GitHub Releases API 客户端（仅手动调用；未认证配额 60 次/小时）。
public struct GitHubReleaseClient: ReleaseFetching {
    public static let defaultRepository = "yangl326-Dylan/agentkeeper"
    public static let appAssetName = "AgentKeeper-app-macos.zip"
    public static let fallbackReleasePage = URL(
        string: "https://github.com/yangl326-Dylan/agentkeeper/releases"
    )!

    /// 网络层注入点（测试用；默认 URLSession）。
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let repository: String
    private let currentVersion: String
    private let loader: DataLoader

    public init(
        repository: String = defaultRepository,
        currentVersion: String = AppVersion.currentBundleVersion.description,
        loader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.repository = repository
        self.currentVersion = currentVersion
        self.loader = loader
    }

    public func latestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw UpdateError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentKeeper/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loader(request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.malformedResponse
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try Self.parse(data: data, repository: repository)
    }

    // MARK: - 解析（internal：单测直接覆盖）

    static func parse(data: Data, repository: String) throws -> ReleaseInfo {
        let dto: ReleaseDTO
        do {
            dto = try JSONDecoder().decode(ReleaseDTO.self, from: data)
        } catch {
            throw UpdateError.malformedResponse
        }
        guard let version = AppVersion(dto.tagName) else {
            throw UpdateError.invalidRemoteVersion(dto.tagName)
        }
        let releaseURL = dto.htmlURL
            ?? URL(string: "https://github.com/\(repository)/releases")!

        let asset = (dto.assets ?? []).first { $0.name == appAssetName }
        var appAssetURL: URL?
        if let asset {
            guard Self.isAllowedAssetURL(asset.browserDownloadURL) else {
                throw UpdateError.invalidAssetURL(asset.browserDownloadURL.absoluteString)
            }
            appAssetURL = asset.browserDownloadURL
        }

        return ReleaseInfo(
            version: version,
            tag: dto.tagName,
            releaseURL: releaseURL,
            appAssetURL: appAssetURL,
            appAssetSize: asset?.size
        )
    }

    /// 仅允许 HTTPS + GitHub 域（资产会重定向到 objects.githubusercontent.com）。
    static func isAllowedAssetURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    // MARK: - JSON 结构

    private struct ReleaseDTO: Decodable {
        var tagName: String
        var htmlURL: URL?
        var assets: [AssetDTO]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct AssetDTO: Decodable {
        var name: String
        var browserDownloadURL: URL
        var size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

/// 更新包下载接口（测试注入 fake）。
public protocol UpdateDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

/// URLSession 下载器：把临时文件移动到独立目录，返回本地 zip 路径。
public struct URLSessionUpdateDownloader: UpdateDownloading {
    public init() {}

    public func download(from url: URL) async throws -> URL {
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateError.invalidAssetURL(url.absoluteString)
        }
        let fileManager = FileManager.default
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.httpStatus(http.statusCode)
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("agentkeeper-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("update.zip")
            try fileManager.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
    }
}
