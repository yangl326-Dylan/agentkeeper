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

    public func upsert(_ skills: [Skill]) {
        queue.sync {
            guard let db else { return }
            exec("BEGIN TRANSACTION")
            for skill in skills {
                guard let payload = try? JSONEncoder().encode(skill) else { continue }
                var statement: OpaquePointer?
                let sql = "INSERT OR REPLACE INTO skills (id, payload) VALUES (?, ?)"
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, skill.id, -1, SQLITE_TRANSIENT)
                payload.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
                sqlite3_step(statement)
            }
            exec("COMMIT")
        }
    }

    public func all() -> [Skill] {
        queue.sync {
            guard let db else { return [] }
            var skills: [Skill] = []
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT payload FROM skills", -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let pointer = sqlite3_column_blob(statement, 0) else { continue }
                let count = Int(sqlite3_column_bytes(statement, 0))
                let data = Data(bytes: pointer, count: count)
                if let skill = try? JSONDecoder().decode(Skill.self, from: data) {
                    skills.append(skill)
                }
            }
            return skills
        }
    }

    /// 全量替换（索引纠偏主通道）。
    public func replaceAll(_ skills: [Skill]) {
        queue.sync {
            guard let db else { return }
            exec("BEGIN TRANSACTION")
            exec("DELETE FROM skills")
            exec("COMMIT")
        }
        upsert(skills)
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
