import Foundation
import Testing
@testable import AppCore

/// GitHub Release 查询：JSON 解码、资产选择、URL 安全校验、错误映射。
@Suite struct UpdateServiceTests {
    private static let validJSON = """
    {
      "tag_name": "v0.3.0",
      "html_url": "https://github.com/yangl326-Dylan/agentkeeper/releases/tag/v0.3.0",
      "assets": [
        {
          "name": "AgentKeeper-cli-macos.zip",
          "browser_download_url": "https://github.com/yangl326-Dylan/agentkeeper/releases/download/v0.3.0/AgentKeeper-cli-macos.zip"
        },
        {
          "name": "AgentKeeper-app-macos.zip",
          "browser_download_url": "https://github.com/yangl326-Dylan/agentkeeper/releases/download/v0.3.0/AgentKeeper-app-macos.zip",
          "size": 123456
        }
      ]
    }
    """

    @Test func parsesReleaseAndSelectsAppAsset() throws {
        let release = try GitHubReleaseClient.parse(
            data: Data(Self.validJSON.utf8),
            repository: "yangl326-Dylan/agentkeeper"
        )
        #expect(release.version == AppVersion("0.3.0"))
        #expect(release.tag == "v0.3.0")
        #expect(release.appAssetSize == 123456)
        #expect(release.appAssetURL?.lastPathComponent == "AgentKeeper-app-macos.zip")
        #expect(release.releaseURL.absoluteString.contains("/releases/tag/v0.3.0"))
    }

    @Test func missingAppAssetYieldsNilWithoutThrowing() throws {
        let json = """
        {"tag_name":"v1.0.0","html_url":"https://github.com/x/y/releases/tag/v1.0.0",
         "assets":[{"name":"AgentKeeper-cli-macos.zip","browser_download_url":"https://github.com/x/y/cli.zip"}]}
        """
        let release = try GitHubReleaseClient.parse(data: Data(json.utf8), repository: "x/y")
        #expect(release.appAssetURL == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: UpdateError.malformedResponse) {
            try GitHubReleaseClient.parse(data: Data("{ nope".utf8), repository: "x/y")
        }
    }

    @Test func rejectsInvalidRemoteVersion() {
        let json = """
        {"tag_name":"latest","html_url":"https://github.com/x/y/releases/tag/latest","assets":[]}
        """
        #expect(throws: UpdateError.invalidRemoteVersion("latest")) {
            try GitHubReleaseClient.parse(data: Data(json.utf8), repository: "x/y")
        }
    }

    @Test func rejectsNonHTTPSAssetURL() {
        let json = """
        {"tag_name":"v1.0.0","html_url":"https://github.com/x/y/releases/tag/v1.0.0",
         "assets":[{"name":"AgentKeeper-app-macos.zip","browser_download_url":"http://evil.example/app.zip"}]}
        """
        #expect(throws: UpdateError.invalidAssetURL("http://evil.example/app.zip")) {
            try GitHubReleaseClient.parse(data: Data(json.utf8), repository: "x/y")
        }
    }

    @Test func rejectsForeignHostAssetURL() {
        let json = """
        {"tag_name":"v1.0.0","html_url":"https://github.com/x/y/releases/tag/v1.0.0",
         "assets":[{"name":"AgentKeeper-app-macos.zip","browser_download_url":"https://evil.example/app.zip"}]}
        """
        #expect(throws: UpdateError.invalidAssetURL("https://evil.example/app.zip")) {
            try GitHubReleaseClient.parse(data: Data(json.utf8), repository: "x/y")
        }
    }

    @Test func acceptsGitHubusercontentAssetHost() throws {
        let json = """
        {"tag_name":"v1.0.0","html_url":"https://github.com/x/y/releases/tag/v1.0.0",
         "assets":[{"name":"AgentKeeper-app-macos.zip",
                    "browser_download_url":"https://objects.githubusercontent.com/github-production-release-asset/app.zip"}]}
        """
        let release = try GitHubReleaseClient.parse(data: Data(json.utf8), repository: "x/y")
        #expect(release.appAssetURL != nil)
    }

    @Test func non200ThrowsHTTPStatus() async {
        let client = GitHubReleaseClient(currentVersion: "0.2.0") { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        await #expect(throws: UpdateError.httpStatus(403)) {
            try await client.latestRelease()
        }
    }

    @Test func networkFailureIsWrapped() async {
        let client = GitHubReleaseClient(currentVersion: "0.2.0") { _ in
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: UpdateError.self) {
            try await client.latestRelease()
        }
    }

    @Test func successfulFetchUsesLoaderData() async throws {
        let client = GitHubReleaseClient(currentVersion: "0.2.0") { request in
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "AgentKeeper/0.2.0")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(Self.validJSON.utf8), response)
        }
        let release = try await client.latestRelease()
        #expect(release.version == AppVersion("0.3.0"))
    }
}
