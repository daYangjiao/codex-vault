import CodexVaultCore
import Foundation
import SQLite3

@main
struct CodexVaultSmokeTests {
    static func main() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let indexURL = root.appendingPathComponent("session_index.jsonl")

        let sessions = try SessionScanner().scan(root: root)
        try expect(sessions.count == 3, "expected 3 session records")
        try expect(sessions.contains { $0.id == "11111111-1111-4111-8111-111111111111" && $0.provider == "openai" }, "missing openai session")
        try expect(sessions.contains { $0.id == "33333333-3333-4333-8333-333333333333" && $0.isArchived }, "missing archived session")

        try createDatabase(at: root.appendingPathComponent("state_5.sqlite"))
        let scan = try CodexVaultScanner().scan(root: root)
        try expect(scan.conversations.count == 4, "expected merged conversations")
        try expect(scan.diagnostics.providerMismatches == 1, "expected one provider mismatch")
        try expect(scan.diagnostics.missingSessionFiles == 1, "expected one database-only row")
        let desktop = scan.conversations.first { $0.id == "11111111-1111-4111-8111-111111111111" }
        let cli = scan.conversations.first { $0.id == "44444444-4444-4444-8444-444444444444" }
        try expect(desktop?.source == "vscode", "expected desktop source")
        try expect(cli?.source == "exec", "expected CLI source")

        let mismatch = scan.conversations.first { $0.id == "22222222-2222-4222-8222-222222222222" }
        try expect(mismatch?.status == .providerMismatch, "expected mismatch status")
        try expectMigrationScopeUsesAllWhenNothingIsChecked(scan.conversations)
        try expectMigrationScopeUsesCheckedItemsWhenPresent(scan.conversations)

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

        try expectLargePayloadLineSurvivesMigration(root: root, backupsRoot: backupsRoot)

        let deletion = try migration.delete(
            root: root,
            conversationIDs: ["11111111-1111-4111-8111-111111111111"],
            skipProcessCheck: true
        )
        try expect(deletion.deletedCount == 1, "expected one deleted conversation")
        try expect(deletion.deletedSessionFileCount == 1, "expected one deleted session file")
        try expect(FileManager.default.fileExists(atPath: deletion.backup.backupDirectory.path), "expected deletion backup directory")

        let deletedScan = try CodexVaultScanner().scan(root: root)
        try expect(!deletedScan.conversations.contains { $0.id == "11111111-1111-4111-8111-111111111111" }, "deleted conversation should not scan")
        let deletedSessionURL = root.appendingPathComponent("sessions/2026/06/12/rollout-2026-06-12T10-00-00-11111111-1111-4111-8111-111111111111.jsonl")
        try expect(!FileManager.default.fileExists(atPath: deletedSessionURL.path), "deleted session file should be removed")
        let indexText = try String(contentsOf: indexURL, encoding: .utf8)
        try expect(!indexText.contains("11111111-1111-4111-8111-111111111111"), "deleted conversation should be removed from session index")

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
        try write(
            root.appendingPathComponent("session_index.jsonl"),
            """
            {"id":"11111111-1111-4111-8111-111111111111","thread_name":"Build the scanner","updated_at":"2026-06-12T10:00:05.000Z"}
            {"id":"22222222-2222-4222-8222-222222222222","thread_name":"Migrate this conversation","updated_at":"2026-06-12T11:00:05.000Z"}
            {"id":"33333333-3333-4333-8333-333333333333","thread_name":"Archived conversation","updated_at":"2026-06-12T12:00:05.000Z"}
            """
        )
        return root
    }

    private static func expectLargePayloadLineSurvivesMigration(root: URL, backupsRoot: URL) throws {
        let fileURL = root.appendingPathComponent("sessions/2026/06/12/rollout-2026-06-12T11-00-00-22222222-2222-4222-8222-222222222222.jsonl")
        let imagePayloadLine = Data("""
        {"timestamp":"2026-06-12T11:00:10.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_image","image_url":"data:image/png;base64,\(String(repeating: "A", count: 1_200_000))"}]}}
        """.utf8)
        let corruptPayloadLine = Data([0xff, 0x00, 0x61, 0x62, 0x63, 0x0a])
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: imagePayloadLine)
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.write(contentsOf: corruptPayloadLine)
        try handle.close()

        let records = try SessionScanner().scan(root: root)
        let migration = MigrationEngine(backupManager: BackupManager(backupsRoot: backupsRoot))
        _ = try migration.migrate(
            root: root,
            conversationIDs: ["22222222-2222-4222-8222-222222222222"],
            targetProvider: "custom",
            skipProcessCheck: true
        )

        let data = try Data(contentsOf: fileURL)
        try expect(data.range(of: imagePayloadLine) != nil, "image payload line should remain byte-for-byte intact")
        try expect(data.range(of: corruptPayloadLine) != nil, "unparseable payload line should remain byte-for-byte intact")
        let migrated = try SessionScanner().scan(root: root)
        try expect(records.count == migrated.count, "large payload migration should not change session count")
    }

    private static func expectMigrationScopeUsesAllWhenNothingIsChecked(_ conversations: [Conversation]) throws {
        let scope = MigrationScopeResolver.resolve(
            conversations: conversations,
            checkedIDs: [],
            targetProvider: "openai"
        )
        try expect(scope.usesSelection == false, "empty checked set should use all matching conversations")
        try expect(scope.sourceProvider == "custom", "openai target should migrate from custom")
        try expect(Set(scope.conversationIDs) == Set([
            "22222222-2222-4222-8222-222222222222",
            "44444444-4444-4444-8444-444444444444"
        ]), "empty checked set should include all API conversations")
    }

    private static func expectMigrationScopeUsesCheckedItemsWhenPresent(_ conversations: [Conversation]) throws {
        let scope = MigrationScopeResolver.resolve(
            conversations: conversations,
            checkedIDs: [
                "11111111-1111-4111-8111-111111111111",
                "22222222-2222-4222-8222-222222222222",
                "44444444-4444-4444-8444-444444444444"
            ],
            targetProvider: "openai"
        )
        try expect(scope.usesSelection == true, "non-empty checked set should use checked conversations")
        try expect(Set(scope.conversationIDs) == Set([
            "22222222-2222-4222-8222-222222222222",
            "44444444-4444-4444-8444-444444444444"
        ]), "checked scope should only include checked API conversations")
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
            thread_source TEXT,
            model_provider TEXT NOT NULL,
            cwd TEXT NOT NULL,
            title TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0
        );
        """)

        try exec(db, """
        INSERT INTO threads (id, rollout_path, created_at, updated_at, source, thread_source, model_provider, cwd, title, archived)
        VALUES
        ('11111111-1111-4111-8111-111111111111', '\(url.deletingLastPathComponent().path)/sessions/2026/06/12/rollout-2026-06-12T10-00-00-11111111-1111-4111-8111-111111111111.jsonl', 1781268000, 1781268005, 'vscode', 'user', 'openai', '/Users/test/project-a', 'Build the scanner', 0),
        ('22222222-2222-4222-8222-222222222222', '\(url.deletingLastPathComponent().path)/sessions/2026/06/12/rollout-2026-06-12T11-00-00-22222222-2222-4222-8222-222222222222.jsonl', 1781271600, 1781271605, 'vscode', 'user', 'openai', '/Users/test/project-b', 'Migrate this conversation', 0),
        ('44444444-4444-4444-8444-444444444444', '\(url.deletingLastPathComponent().path)/sessions/missing.jsonl', 1781275200, 1781275205, 'exec', 'user', 'custom', '/Users/test/project-d', 'Database only', 0);
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
