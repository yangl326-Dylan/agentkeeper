import Foundation
import Testing
@testable import AppCore

/// 版本解析与比较：容忍 `v` 前缀、位数差异与预发布后缀。
@Suite struct AppVersionTests {
    @Test func parsesPlainAndVPrefixedVersions() {
        #expect(AppVersion("0.2.0")?.components == [0, 2])
        #expect(AppVersion("v0.2.0")?.components == [0, 2])
        #expect(AppVersion("V1.10.3")?.components == [1, 10, 3])
        #expect(AppVersion(" 1.2 ")?.components == [1, 2])
    }

    @Test func normalizesTrailingZeros() {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1.0.0.0") == AppVersion("1"))
    }

    @Test func ignoresPrereleaseAndBuildSuffix() {
        #expect(AppVersion("1.2.3-beta.1")?.components == [1, 2, 3])
        #expect(AppVersion("1.2.3+build.9")?.components == [1, 2, 3])
    }

    @Test func rejectsInvalidInput() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("1.2.a") == nil)
        #expect(AppVersion("release-1.2") == nil)
        #expect(AppVersion("-1.2") == nil)
    }

    @Test func comparesNumericallyNotLexically() {
        #expect(AppVersion("0.9.0")! < AppVersion("0.10.0")!)
        #expect(AppVersion("1.2.9")! < AppVersion("1.3.0")!)
        #expect(AppVersion("2.0")! > AppVersion("1.99.99")!)
        #expect(!(AppVersion("1.2.0")! < AppVersion("1.2")!))
        #expect(AppVersion("1.2.0")! <= AppVersion("1.2")!)
    }

    @Test func descriptionRoundTrips() {
        #expect(AppVersion("v1.2.0")?.description == "1.2")
        #expect(AppVersion("0.2.0")?.description == "0.2")
    }
}
