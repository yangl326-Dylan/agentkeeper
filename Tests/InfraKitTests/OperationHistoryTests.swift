import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct OperationHistoryTests {
    private func makeStore() -> (OperationHistory, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-history-\(UUID().uuidString)", isDirectory: true)
        return (OperationHistory(directory: dir), dir)
    }

    @Test func appendAndReadBackRecords() {
        let (history, _) = makeStore()
        history.append(skillID: "alpha|claude-code", name: "alpha", direction: .disable, result: .success)
        history.append(
            skillID: "beta|opencode",
            name: "beta",
            direction: .enable,
            result: .failure(message: "原路径被占用")
        )
        let records = history.recent(limit: 10)
        #expect(records.count == 2)
        #expect(records[0].direction == .enable)  // 最新的在前面
        #expect(records[1].result == .success)
    }

    @Test func limitReturnsNewestFirst() {
        let (history, _) = makeStore()
        for index in 0..<7 {
            history.append(skillID: "s\(index)", name: "s\(index)", direction: .disable, result: .success)
        }
        let records = history.recent(limit: 3)
        #expect(records.count == 3)
        #expect(records[0].name == "s6")
        #expect(records[2].name == "s4")
    }

    @Test func persistsAcrossInstances() {
        let (history, dir) = makeStore()
        history.append(skillID: "alpha|claude-code", name: "alpha", direction: .disable, result: .success)

        let reloaded = OperationHistory(directory: dir)
        let records = reloaded.recent(limit: 10)
        #expect(records.count == 1)
        #expect(records[0].name == "alpha")
    }

    @Test func corruptHistoryFileFallsBackToEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "NOT JSON".write(to: dir.appendingPathComponent("history.json"), atomically: true, encoding: .utf8)

        let history = OperationHistory(directory: dir)
        #expect(history.recent(limit: 10).isEmpty)
        // 且能继续写入（自愈）
        history.append(skillID: "x", name: "x", direction: .enable, result: .success)
        #expect(history.recent(limit: 10).count == 1)
    }
}
