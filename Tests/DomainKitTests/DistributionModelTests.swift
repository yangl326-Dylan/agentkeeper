import Foundation
import Testing
import DomainKit

@Suite struct DistributionModelTests {
    @Test func sourceVariantsCodableRoundTrip() throws {
        let sources: [DistributionSource] = [
            .existingSkill(agentID: "claude-code", name: "review", directoryPath: "/a/b/review"),
            .localDirectory(path: "/tmp/import-me"),
            .gitRepository(url: "https://example.com/x/y.git"),
        ]
        let data = try JSONEncoder().encode(sources)
        let decoded = try JSONDecoder().decode([DistributionSource].self, from: data)
        #expect(decoded == sources)
    }

    @Test func conflictDetailStable() throws {
        let conflict = DistributionConflict(
            targetPath: "/x/skills/review",
            existingSha256: "aaa",
            incomingSha256: "bbb"
        )
        let copy = try JSONDecoder().decode(
            DistributionConflict.self,
            from: try JSONEncoder().encode(conflict)
        )
        #expect(copy == conflict)
    }

    @Test func gitCandidateCodableRoundTrip() throws {
        let candidate = GitSkillCandidate(
            repositoryURL: "file:///tmp/repo.git",
            directory: URL(fileURLWithPath: "/tmp/repo"),
            name: "docs-writer",
            sha256: "cafe"
        )
        let copy = try JSONDecoder().decode(
            GitSkillCandidate.self,
            from: try JSONEncoder().encode(candidate)
        )
        #expect(copy == candidate)
    }

    @Test func landingPointIdentity() {
        let a = LandingPoint(agentID: "claude-code", directory: URL(fileURLWithPath: "/x/.claude/skills/review"))
        let b = LandingPoint(agentID: "opencode", directory: URL(fileURLWithPath: "/x/.opencode/skills/review"))
        #expect(a != b)
        #expect(LandingPoint(agentID: "claude-code", directory: URL(fileURLWithPath: "/x/.claude/skills/review")) == a)
    }
}
