import Foundation
import SQLite3
import DomainKit

/// Skill 索引缓存（SQLite）。
/// 设计铁律：文件系统是唯一真相——本索引只加速查询，失真时可全量重建。
public final class SkillIndex: @unchecked Sendable {
    /// Capacities: 每 256 MiB 内的数据库寿命足够 MVP。
    private var db: OpaquePointer?
    private let databaseFile: URL
    private let queue = DispatchQueue(label: "agentkeeper.skillindex")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseDirectory: URL) {
        self.databaseFile = databaseDirectory.appendingPathComponent("skills.db")
        try? FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        openDatabase()
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - 打开/建造

    private func openDatabase() {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseFile.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            self.db = nil
            return
        }
        self.db = db
        exec("PRAGMA journal_mode = WAL")
        exec(
            """
            CREATE TABLE IF NOT EXISTS skills (
                id TEXT PRIMARY KEY,
                payload BLOB NOT NULL
            )
            """
        )
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - 操作

    /// rollback 等失败处理通常无需看结果——加 discardable 防告警。
    @discardableResult
    private func checkedExec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// INSERT statement（同一事务内 prepare 一次、行间 reset 复用、事务末 finalize）。
    /// step 返回码必查——写失败不静默吞行。
    private func insertAndStep(_ skill: Skill, statement: OpaquePointer) -> Bool {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, skill.id, -1, SQLITE_TRANSIENT)
        guard let payload = try? encoder.encode(skill) else { return false }
        let bindOk = payload.withUnsafeBytes { buffer -> Bool in
            return sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                == SQLITE_OK
        }
        guard bindOk else { return false }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func preparedInsert() -> OpaquePointer? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO skills (id, payload) VALUES (?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        return statement
    }

    public func upsert(_ skills: [Skill]) {
        queue.sync {
            guard db != nil else { return }
            guard let statement = preparedInsert() else { return }
            defer { sqlite3_finalize(statement) }
            guard checkedExec("BEGIN TRANSACTION") else { return }
            for skill in skills {
                guard insertAndStep(skill, statement: statement) else {
                    checkedExec("ROLLBACK")
                    return
                }
            }
            if !checkedExec("COMMIT") {
                checkedExec("ROLLBACK")
            }
        }
    }

    public func all() -> [Skill] {
        queue.sync {
            guard let db else { return [] }
            var skills: [Skill] = []
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM skills", -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pointer = sqlite3_column_blob(statement, 0) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: pointer, count: count)
                if let skill = try? decoder.decode(Skill.self, from: data) {
                    skills.append(skill)
                }
            }
            return skills
        }
    }

    /// 同步全量替换（索引纠偏主通道；测试与显式等待场景用）。
    public func replaceAll(_ skills: [Skill]) {
        queue.sync {
            performReplace(skills)
        }
    }

    /// 异步全量替换（生产主通道：CatalogStore.sync 在 MainActor 上调用，写盘不阻塞主线程）。
    /// queue 串行保证与 all() 读天然互斥；多连发收敛于最后一次写入。
    public func replace(_ skills: [Skill]) {
        queue.async { [weak self] in
            self?.performReplace(skills)
        }
    }

    /// 单事务全量替换（DELETE+插入原子——曾拆两段提交，中途可读到空表且崩溃丢全索引）。
    private func performReplace(_ skills: [Skill]) {
        guard db != nil else { return }
        guard let statement = preparedInsert() else { return }
        defer { sqlite3_finalize(statement) }
        guard checkedExec("BEGIN IMMEDIATE TRANSACTION") else { return }
        guard checkedExec("DELETE FROM skills") else {
            checkedExec("ROLLBACK")
            return
        }
        for skill in skills {
            guard insertAndStep(skill, statement: statement) else {
                checkedExec("ROLLBACK")
                return
            }
        }
        if !checkedExec("COMMIT") {
            checkedExec("ROLLBACK")
        }
    }

    /// 完整性检查。
    public func integrity() -> Bool {
        queue.sync {
            guard let db else { return false }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW,
               let cString = sqlite3_column_text(statement, 0) {
                let result = String(cString: cString)
                return result == "ok"
            }
            return false
        }
    }

    /// 重建（drop + recreate）——fs is truth 的根本安全网。伴生 WAL/SHM 一并清理。
    public func rebuild() {
        queue.sync {
            if let db {
                sqlite3_close_v2(db)
                self.db = nil
            }
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: databaseFile.path + suffix)
                try? FileManager.default.removeItem(at: url)
            }
            openDatabase()
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
