import Foundation

public enum CodexVaultError: LocalizedError {
    case missingCodexRoot(URL)
    case unreadableFile(URL)
    case sqliteOpenFailed(String)
    case sqlitePrepareFailed(String)
    case unsupportedDatabaseSchema
    case codexIsRunning([RunningProcess])
    case backupFailed(String)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCodexRoot(let url):
            return "Codex data directory was not found at \(url.path)."
        case .unreadableFile(let url):
            return "Could not read \(url.path)."
        case .sqliteOpenFailed(let message):
            return "Could not open Codex database: \(message)"
        case .sqlitePrepareFailed(let message):
            return "Could not query Codex database: \(message)"
        case .unsupportedDatabaseSchema:
            return "This Codex database schema is not supported yet."
        case .codexIsRunning(let processes):
            let details = processes.map { "\($0.id): \($0.command)" }.joined(separator: "\n")
            return "Codex is still running. Quit Codex completely before changing local history.\n\(details)"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        }
    }
}
