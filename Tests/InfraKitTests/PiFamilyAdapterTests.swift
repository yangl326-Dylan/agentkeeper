import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// pi / oh-my-pi 同源 harness：两个轻量 adapter 共享一套引擎配置，各自识别归属，互不串扰。

@Suite struct PiAdapterTests {
    @Test func detectsPiWhenDotPiExists() async {
        let home = makeFakeHome(files: [".pi/skills/one/SKILL.md"])
        defer { cleanup(home) }
        let adapter = PiAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].owners == ["pi"])
        #expect(adapter.id == "pi")
    }

    @Test func notInstalledWhenNoDotPi() async {
        let home = makeFakeHome(files: ["v.txt"])
        defer { cleanup(home) }
        let adapter = PiAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }
}

@Suite struct OhMyPiAdapterTests {
    @Test func detectsOhMyPI() async {
        let home = makeFakeHome(files: [".omp/skills/two/SKILL.md"])
        defer { cleanup(home) }
        let adapter = OhMyPiAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].owners == ["oh-my-pi"])
        #expect(adapter.id == "oh-my-pi")
    }

    @Test func notInstalledWhenNoOMPLayout() async {
        let home = makeFakeHome(files: [".pi/skills/one/SKILL.md"]) // 只有 pi，不算 oh-my-pi
        defer { cleanup(home) }
        let adapter = OhMyPiAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }
}

@Suite struct PiFamilyNoCrossContaminationTests {
    @Test func sameNamedSkillParsedByEachAttributedCorrectly() async {
        let home = makeFakeHome(
            files: [
                ".pi/skills/alpha/SKILL.md",
                ".omp/skills/alpha/SKILL.md",
            ],
            fileContents: [
                ".pi/skills/alpha/SKILL.md": "---\nname: alpha-pi\ndescription: pi 版\n---\nA",
                ".omp/skills/alpha/SKILL.md": "---\nname: alpha-omp\ndescription: omp 版\n---\nB",
            ]
        )
        defer { cleanup(home) }
        let pi = PiAdapter(homeDirectory: home)
        let omp = OhMyPiAdapter(homeDirectory: home)
        let piRoots = await pi.skillRoots()
        let ompRoots = await omp.skillRoots()
        #expect(piRoots[0].path == home.appendingPathComponent(".pi/skills", isDirectory: true))
        #expect(ompRoots[0].path == home.appendingPathComponent(".omp/skills", isDirectory: true))
        let piParsed = await pi.parseSkill(at: home.appendingPathComponent(".pi/skills/alpha", isDirectory: true))
        let ompParsed = await omp.parseSkill(at: home.appendingPathComponent(".omp/skills/alpha", isDirectory: true))
        #expect(piParsed?.frontmatterName == "alpha-pi")
        #expect(ompParsed?.frontmatterName == "alpha-omp")
    }
}
