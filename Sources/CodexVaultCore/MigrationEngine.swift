import Foundation

public struct MigrationEngine: Sendable {
    private let sessionScanner: SessionScanner
    private let sessionFileStore: SessionFileStore
    private let stateDatabase: StateDatabase
    private let backupManager: BackupManager
    private let processGuard: ProcessGuard

    public init(
        sessionScanner: SessionScanner = SessionScanner(),
        sessionFileStore: SessionFileStore = SessionFileStore(),
        stateDatabase: StateDatabase = StateDatabase(),
        backupManager: BackupManager = BackupManager(),
        processGuard: ProcessGuard = ProcessGuard()
    ) {
        self.sessionScanner = sessionScanner
        self.sessionFileStore = sessionFileStore
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

        let records = try sessionScanner.scan(root: root)
        let selectedIDs = Set(conversationIDs)
        let selectedRecords = records.filter { selectedIDs.contains($0.id) }
        let backup = try backupManager.createBackup(
            root: root,
            reason: "Before provider migration to \(targetProvider)",
            conversationCount: records.count
        )

        try sessionFileStore.updateProvider(records: selectedRecords, targetProvider: targetProvider)
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        try stateDatabase.updateProvider(databaseURL: databaseURL, conversationIDs: Array(selectedIDs), targetProvider: targetProvider)

        return MigrationReport(migratedCount: conversationIDs.count, targetProvider: targetProvider, backup: backup)
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
