import Foundation

public struct MigrationEngine: Sendable {
    private let sessionScanner: SessionScanner
    private let sessionFileStore: SessionFileStore
    private let sessionIndexStore: SessionIndexStore
    private let stateDatabase: StateDatabase
    private let backupManager: BackupManager
    private let processGuard: ProcessGuard

    public init(
        sessionScanner: SessionScanner = SessionScanner(),
        sessionFileStore: SessionFileStore = SessionFileStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        stateDatabase: StateDatabase = StateDatabase(),
        backupManager: BackupManager = BackupManager(),
        processGuard: ProcessGuard = ProcessGuard()
    ) {
        self.sessionScanner = sessionScanner
        self.sessionFileStore = sessionFileStore
        self.sessionIndexStore = sessionIndexStore
        self.stateDatabase = stateDatabase
        self.backupManager = backupManager
        self.processGuard = processGuard
    }

    public func migrate(
        root: URL,
        conversationIDs: [String],
        targetProvider: String,
        skipProcessCheck: Bool = false
    ) throws -> MigrationReport {
        let targetProvider = targetProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversationIDs.isEmpty else {
            throw CodexVaultError.migrationFailed("No conversations were selected.")
        }
        guard !targetProvider.isEmpty else {
            throw CodexVaultError.migrationFailed("Target provider is empty.")
        }

        if !skipProcessCheck {
            let running = processGuard.runningCodexProcesses()
            if !running.isEmpty {
                throw CodexVaultError.codexIsRunning(running)
            }
        }

        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        let databaseThreads = try stateDatabase.readThreads(databaseURL: databaseURL)
        let selectedIDs = Set(conversationIDs)
        let selectedThreads = databaseThreads.filter { selectedIDs.contains($0.id) }
        let selectedRecords = selectedThreads.compactMap { thread -> SessionRecord? in
            guard let rolloutPath = thread.rolloutPath, !rolloutPath.isEmpty else {
                return nil
            }
            return SessionRecord(
                id: thread.id,
                provider: thread.provider,
                projectPath: thread.projectPath,
                source: thread.source,
                title: thread.title,
                filePath: URL(fileURLWithPath: rolloutPath),
                lastUpdatedAt: thread.updatedAt,
                isArchived: thread.isArchived
            )
        }
        let backup = try backupManager.createBackup(
            root: root,
            reason: "Before provider migration to \(targetProvider)",
            conversationCount: databaseThreads.count
        )

        try sessionFileStore.updateProvider(records: selectedRecords, targetProvider: targetProvider)
        try stateDatabase.updateProvider(databaseURL: databaseURL, conversationIDs: Array(selectedIDs), targetProvider: targetProvider)

        return MigrationReport(migratedCount: conversationIDs.count, targetProvider: targetProvider, backup: backup)
    }

    public func delete(
        root: URL,
        conversationIDs: [String],
        skipProcessCheck: Bool = false
    ) throws -> DeletionReport {
        guard !conversationIDs.isEmpty else {
            throw CodexVaultError.migrationFailed("No conversations were selected.")
        }

        if !skipProcessCheck {
            let running = processGuard.runningCodexProcesses()
            if !running.isEmpty {
                throw CodexVaultError.codexIsRunning(running)
            }
        }

        let selectedIDs = Set(conversationIDs)
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        let databaseThreads = try stateDatabase.readThreads(databaseURL: databaseURL)
        let sessionRecords = try sessionScanner.scan(root: root)
        let recordsByID = Dictionary(uniqueKeysWithValues: sessionRecords.map { ($0.id, $0) })
        let selectedThreads = databaseThreads.filter { selectedIDs.contains($0.id) }
        let recordsFromThreads = selectedThreads.compactMap { thread -> SessionRecord? in
            guard let rolloutPath = thread.rolloutPath, !rolloutPath.isEmpty else {
                return nil
            }
            return SessionRecord(
                id: thread.id,
                provider: thread.provider,
                projectPath: thread.projectPath,
                source: thread.source,
                title: thread.title,
                filePath: URL(fileURLWithPath: rolloutPath),
                lastUpdatedAt: thread.updatedAt,
                isArchived: thread.isArchived
            )
        }
        let selectedRecords = Array(
            Dictionary(
                uniqueKeysWithValues: selectedIDs.compactMap { id -> (String, SessionRecord)? in
                    if let record = recordsByID[id] {
                        return (id, record)
                    }
                    if let record = recordsFromThreads.first(where: { $0.id == id }) {
                        return (id, record)
                    }
                    return nil
                }
            ).values
        )

        let backup = try backupManager.createBackup(
            root: root,
            reason: "Before deleting selected conversations",
            conversationCount: databaseThreads.count
        )

        let deletedIndexEntries = try sessionIndexStore.deleteEntries(
            indexURL: root.appendingPathComponent("session_index.jsonl"),
            conversationIDs: selectedIDs
        )
        let deletedFiles = try sessionFileStore.deleteSessionFiles(records: selectedRecords)
        let deletedRows = try stateDatabase.deleteThreads(databaseURL: databaseURL, conversationIDs: Array(selectedIDs))

        return DeletionReport(
            deletedCount: selectedIDs.count,
            deletedDatabaseRowCount: deletedRows,
            deletedSessionFileCount: deletedFiles,
            deletedIndexEntryCount: deletedIndexEntries,
            backup: backup
        )
    }

    public func restoreLatestBackup(root: URL, skipProcessCheck: Bool = false) throws -> BackupRecord {
        if !skipProcessCheck {
            let running = processGuard.runningCodexProcesses()
            if !running.isEmpty {
                throw CodexVaultError.codexIsRunning(running)
            }
        }

        guard let latest = backupManager.listBackups().first else {
            throw CodexVaultError.backupFailed("No backups found.")
        }
        try backupManager.restore(latest, to: root)
        return latest
    }
}
