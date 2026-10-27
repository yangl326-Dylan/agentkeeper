import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct DeletionGateTests {
    private func skill(name: String, path: String) -> Skill {
        Skill(
            id: "\(name)|test",
            name: name,
            directory: URL(fileURLWithPath: path),
            scope: .agentOnly(agentID: "claude-code"),
            sha256: "sha"
        )
    }

    @Test func confirmedDeletionProceedsAndRemovesDirectory() throws {
        let home = makeFakeHome(files: ["skill/alpha/SKILL.md"])
        defer { cleanup(home) }
        let directory = home.appendingPathComponent("skill/alpha", isDirectory: true)
        let gate = DeletionGate()
        var asked: [Skill] = []
        let plan = try gate.requestDeletion(
            skills: [skill(name: "alpha", path: directory.path)],
            confirm: { skills in
                asked.append(contentsOf: skills)
                return true
            },
            perform: { paths in
                #expect(paths.map(\.path) == [directory.path])
                try FileManager.default.removeItem(at: directory)
            }
        )
        #expect(plan.confirmed)
        #expect(asked.count == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func cancelledDeletionDoesNothing() throws {
        let home = makeFakeHome(files: ["skill/alpha/SKILL.md"])
        defer { cleanup(home) }
        let directory = home.appendingPathComponent("skill/alpha", isDirectory: true)
        let gate = DeletionGate()
        var performed = 0
        let plan = try gate.requestDeletion(
            skills: [skill(name: "alpha", path: directory.path)],
            confirm: { _ in false },
            perform: { _ in performed += 1 }
        )
        #expect(!plan.confirmed)
        #expect(performed == 0)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func confirmationDialogReceivesPathInventory() {
        let gate = DeletionGate()
        let skills = [
            skill(name: "a", path: "/tmp/x/a"),
            skill(name: "b", path: "/tmp/x/b"),
        ]
        var inventory: [String] = []
        _ = try? gate.requestDeletion(
            skills: skills,
            confirm: { list in
                inventory = list.map { $0.directory.path }
                return false
            },
            perform: { _ in }
        )
        #expect(inventory.count == 2)
    }

    @Test func emptySelectionShortCircuitsWithoutAsking() {
        let gate = DeletionGate()
        var asked = false
        let plan = try? gate.requestDeletion(
            skills: [],
            confirm: { _ in
                asked = true
                return true
            },
            perform: { _ in }
        )
        #expect(plan?.confirmed == false)
        #expect(!asked)
    }
}
