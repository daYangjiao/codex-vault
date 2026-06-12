import Foundation
import SQLite3

public struct StateDatabase: Sendable {
    public init() {}

    public func readThreads(databaseURL: URL) throws -> [DatabaseThread] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            if db != nil {
                sqlite3_close(db)
            }
            throw CodexVaultError.sqliteOpenFailed(message)
        }
        defer { sqlite3_close(db) }

        guard try hasThreadsTable(db) else {
            return []
        }

        let columns = try tableColumns(db, tableName: "threads")
        guard columns.contains("id"), columns.contains("model_provider") else {
            throw CodexVaultError.unsupportedDatabaseSchema
        }

        return try queryThreads(db, columns: columns)
    }

    public func updateProvider(databaseURL: URL, conversationIDs: [String], targetProvider: String) throws {
        guard !conversationIDs.isEmpty else {
            return
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            if db != nil {
                sqlite3_close(db)
            }
            throw CodexVaultError.sqliteOpenFailed(message)
        }
        defer { sqlite3_close(db) }

        let columns = try tableColumns(db, tableName: "threads")
        guard columns.contains("id"), columns.contains("model_provider") else {
            throw CodexVaultError.unsupportedDatabaseSchema
        }

        try exec(db, "BEGIN IMMEDIATE TRANSACTION")
        do {
            let sql = "UPDATE threads SET model_provider = ? WHERE id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw CodexVaultError.sqlitePrepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }

            for id in conversationIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_text(statement, 1, targetProvider, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw CodexVaultError.sqlitePrepareFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
            try exec(db, "COMMIT")
        } catch {
            try? exec(db, "ROLLBACK")
            throw error
        }
    }

    private func hasThreadsTable(_ db: OpaquePointer?) throws -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'threads' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CodexVaultError.sqlitePrepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func tableColumns(_ db: OpaquePointer?, tableName: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(tableName))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CodexVaultError.sqlitePrepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnString(statement, 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func queryThreads(_ db: OpaquePointer?, columns: Set<String>) throws -> [DatabaseThread] {
        let selectedColumns = [
            "id",
            "model_provider",
            columns.contains("rollout_path") ? "rollout_path" : "'' AS rollout_path",
            columns.contains("cwd") ? "cwd" : "'' AS cwd",
            columns.contains("title") ? "title" : "'' AS title",
            columns.contains("source") ? "source" : "'' AS source",
            columns.contains("thread_source") ? "thread_source" : "'' AS thread_source",
            columns.contains("updated_at") ? "updated_at" : "0 AS updated_at",
            columns.contains("updated_at_ms") ? "updated_at_ms" : "0 AS updated_at_ms",
            columns.contains("archived") ? "archived" : "0 AS archived"
        ].joined(separator: ", ")
        let sql = "SELECT \(selectedColumns) FROM threads"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CodexVaultError.sqlitePrepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var threads: [DatabaseThread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let updatedAtSeconds = sqlite3_column_int64(statement, 7)
            let updatedAtMilliseconds = sqlite3_column_int64(statement, 8)
            let updatedAt: Date?
            if updatedAtMilliseconds > 0 {
                updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1000)
            } else if updatedAtSeconds > 0 {
                updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtSeconds))
            } else {
                updatedAt = nil
            }

            threads.append(DatabaseThread(
                id: columnString(statement, 0) ?? "",
                provider: columnString(statement, 1),
                projectPath: columnString(statement, 3),
                source: columnString(statement, 5),
                threadSource: columnString(statement, 6),
                title: columnString(statement, 4) ?? "",
                rolloutPath: columnString(statement, 2),
                updatedAt: updatedAt,
                isArchived: sqlite3_column_int(statement, 9) != 0
            ))
        }
        return threads.filter { !$0.id.isEmpty }
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            throw CodexVaultError.sqlitePrepareFailed(message)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
