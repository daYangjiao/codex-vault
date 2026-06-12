import CodexVaultCore
import Foundation
import SQLite3

@main
struct CodexVaultSmokeTests {
    static func main() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = try SessionScanner().scan(root: root)
        try expect(sessions.count == 3, "expected 3 session records")
        try expect(sessions.contains { $0.id == "11111111-1111-4111-8111-111111111111" && $0.provider == "openai" }, "missing openai session")
        try expect(sessions.contains { $0.id == "33333333-3333-4333-8333-333333333333" && $0.isArchived }, "missing archived session")

        try createDatabase(at: root.appendingPathComponent("state_5.sqlite"))
        let scan = try CodexVaultScanner().scan(root: root)
        try expect(scan.conversations.count == 4, "expected merged conversations")
        try expect(scan.diagnostics.providerMismatches == 1, "expected one provider mismatch")
        try expect(scan.diagnostics.missingSessionFiles == 1, "expected one database-only row")

        let mismatch = scan.conversations.first { $0.id == "22222222-2222-4222-8222-222222222222" }
        try expect(mismatch?.status == .providerMismatch, "expected mismatch status")

        let backupsRoot = root.appendingPathComponent("vault-backups", isDirectory: true)
        let migration = MigrationEngine(backupManager: BackupManager(backupsRoot: backupsRoot))
        let report = try migration.migrate(
            root: root,
            conversationIDs: ["22222222-2222-4222-8222-222222222222"],
            targetProvider: "openai",
            skipProcessCheck: true
        )
        try expect(report.migratedCount == 1, "expected one migrated conversation")
        try expect(FileManager.default.fileExists(atPath: report.backup.backupDirectory.path), "expected backup directory")

        let migratedScan = try CodexVaultScanner().scan(root: root)
        let migrated = migratedScan.conversations.first { $0.id == "22222222-2222-4222-8222-222222222222" }
        try expect(migrated?.sessionProvider == "openai", "expected session provider update")
        try expect(migrated?.databaseProvider == "openai", "expected database provider update")
        try expect(migrated?.status == .ok, "expected migrated conversation to be OK")

        print("CodexVaultSmokeTests passed")
    }

    private static func makeFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexVaultSmokeTests-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions/2026/06/12", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions/2026/06/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)

        try write(
            sessions.appendingPathComponent("rollout-2026-06-12T10-00-00-11111111-1111-4111-8111-111111111111.jsonl"),
            """
            {"timestamp":"2026-06-12T10:00:00.000Z","type":"session_meta","payload":{"id":"11111111-1111-4111-8111-111111111111","timestamp":"2026-06-12T10:00:00.000Z","cwd":"/Users/test/project-a","source":"vscode","model_provider":"openai","cli_version":"0.130.0"}}
            {"timestamp":"2026-06-12T10:00:05.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Build the scanner"}]}}
            """
        )
        try write(
            sessions.appendingPathComponent("rollout-2026-06-12T11-00-00-22222222-2222-4222-8222-222222222222.jsonl"),
            """
            {"timestamp":"2026-06-12T11:00:00.000Z","type":"session_meta","payload":{"id":"22222222-2222-4222-8222-222222222222","timestamp":"2026-06-12T11:00:00.000Z","cwd":"/Users/test/project-b","source":"vscode","model_provider":"custom","cli_version":"0.130.0"}}
            {"timestamp":"2026-06-12T11:00:05.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Migrate this conversation"}]}}
            """
        )
        try write(
            archived.appendingPathComponent("rollout-2026-06-12T12-00-00-33333333-3333-4333-8333-333333333333.jsonl"),
            """
            {"timestamp":"2026-06-12T12:00:00.000Z","type":"session_meta","payload":{"id":"33333333-3333-4333-8333-333333333333","timestamp":"2026-06-12T12:00:00.000Z","cwd":"/Users/test/project-c","source":"vscode","model_provider":"openai","cli_version":"0.130.0"}}
            {"timestamp":"2026-06-12T12:00:05.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Archived conversation"}]}}
            """
        )
        return root
    }

    private static func write(_ url: URL, _ text: String) throws {
        try text.appending("\n").data(using: .utf8)!.write(to: url)
    }

    private static func createDatabase(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw SmokeTestError("sqlite open failed")
        }
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            source TEXT NOT NULL,
            model_provider TEXT NOT NULL,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0
        );
        """)

        try exec(db, """
        INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title, archived)
        VALUES
        ('11111111-1111-4111-8111-111111111111', 'sessions/one.jsonl', 1781268000, 1781268005, 'vscode', 'openai', '/Users/test/project-a', 'Build the scanner', 0),
        ('22222222-2222-4222-8222-222222222222', 'sessions/two.jsonl', 1781271600, 1781271605, 'vscode', 'openai', '/Users/test/project-b', 'Migrate this conversation', 0),
        ('44444444-4444-4444-8444-444444444444', 'sessions/missing.jsonl', 1781275200, 1781275205, 'vscode', 'custom', '/Users/test/project-d', 'Database only', 0);
        """)
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            throw SmokeTestError(message)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SmokeTestError(message)
        }
    }
}

struct SmokeTestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
