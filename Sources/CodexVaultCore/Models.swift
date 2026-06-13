import Foundation

public struct Conversation: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var sessionProvider: String?
    public var databaseProvider: String?
    public var source: String?
    public var threadSource: String?
    public var projectPath: String?
    public var sessionFilePath: URL?
    public var lastUpdatedAt: Date?
    public var isArchived: Bool
    public var status: ConversationStatus

    public init(
        id: String,
        title: String,
        sessionProvider: String?,
        databaseProvider: String?,
        source: String?,
        threadSource: String?,
        projectPath: String?,
        sessionFilePath: URL?,
        lastUpdatedAt: Date?,
        isArchived: Bool,
        status: ConversationStatus
    ) {
        self.id = id
        self.title = title
        self.sessionProvider = sessionProvider
        self.databaseProvider = databaseProvider
        self.source = source
        self.threadSource = threadSource
        self.projectPath = projectPath
        self.sessionFilePath = sessionFilePath
        self.lastUpdatedAt = lastUpdatedAt
        self.isArchived = isArchived
        self.status = status
    }
}

public enum ConversationStatus: String, Codable, Sendable {
    case ok
    case providerMismatch
    case missingDatabaseRow
    case missingSessionFile
    case unreadableSessionFile
    case archived

    public var displayName: String {
        switch self {
        case .ok:
            return "OK"
        case .providerMismatch:
            return "Provider mismatch"
        case .missingDatabaseRow:
            return "Missing database row"
        case .missingSessionFile:
            return "Missing session file"
        case .unreadableSessionFile:
            return "Unreadable session file"
        case .archived:
            return "Archived"
        }
    }
}

public struct ProviderSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationCount: Int
    public let problemCount: Int

    public init(id: String, conversationCount: Int, problemCount: Int) {
        self.id = id
        self.conversationCount = conversationCount
        self.problemCount = problemCount
    }
}

public struct DiagnosticsSummary: Equatable, Sendable {
    public let providerMismatches: Int
    public let missingDatabaseRows: Int
    public let missingSessionFiles: Int
    public let unreadableSessionFiles: Int

    public var totalProblems: Int {
        providerMismatches + missingDatabaseRows + missingSessionFiles + unreadableSessionFiles
    }

    public init(
        providerMismatches: Int,
        missingDatabaseRows: Int,
        missingSessionFiles: Int,
        unreadableSessionFiles: Int
    ) {
        self.providerMismatches = providerMismatches
        self.missingDatabaseRows = missingDatabaseRows
        self.missingSessionFiles = missingSessionFiles
        self.unreadableSessionFiles = unreadableSessionFiles
    }
}

public struct ScanResult: Sendable {
    public let root: URL
    public let conversations: [Conversation]
    public let providerSummaries: [ProviderSummary]
    public let diagnostics: DiagnosticsSummary
    public let scannedAt: Date
    public let databaseAvailable: Bool

    public init(
        root: URL,
        conversations: [Conversation],
        providerSummaries: [ProviderSummary],
        diagnostics: DiagnosticsSummary,
        scannedAt: Date,
        databaseAvailable: Bool
    ) {
        self.root = root
        self.conversations = conversations
        self.providerSummaries = providerSummaries
        self.diagnostics = diagnostics
        self.scannedAt = scannedAt
        self.databaseAvailable = databaseAvailable
    }
}

public struct SessionRecord: Hashable, Sendable {
    public let id: String
    public let provider: String?
    public let projectPath: String?
    public let source: String?
    public let title: String
    public let filePath: URL
    public let lastUpdatedAt: Date?
    public let isArchived: Bool
}

public struct DatabaseThread: Hashable, Sendable {
    public let id: String
    public let provider: String?
    public let projectPath: String?
    public let source: String?
    public let threadSource: String?
    public let title: String
    public let rolloutPath: String?
    public let updatedAt: Date?
    public let isArchived: Bool
}

public struct BackupRecord: Identifiable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let reason: String
    public let backupDirectory: URL
    public let conversationCount: Int

    public init(id: String, createdAt: Date, reason: String, backupDirectory: URL, conversationCount: Int) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.backupDirectory = backupDirectory
        self.conversationCount = conversationCount
    }
}

public struct MigrationReport: Sendable {
    public let migratedCount: Int
    public let targetProvider: String
    public let backup: BackupRecord

    public init(migratedCount: Int, targetProvider: String, backup: BackupRecord) {
        self.migratedCount = migratedCount
        self.targetProvider = targetProvider
        self.backup = backup
    }
}

public struct MigrationScope: Sendable, Equatable {
    public let conversationIDs: [String]
    public let targetProvider: String
    public let sourceProvider: String
    public let usesSelection: Bool

    public init(conversationIDs: [String], targetProvider: String, sourceProvider: String, usesSelection: Bool) {
        self.conversationIDs = conversationIDs
        self.targetProvider = targetProvider
        self.sourceProvider = sourceProvider
        self.usesSelection = usesSelection
    }
}

public enum MigrationScopeResolver {
    public static func resolve(
        conversations: [Conversation],
        checkedIDs: Set<String>,
        targetProvider: String
    ) -> MigrationScope {
        let sourceProvider = targetProvider == "openai" ? "custom" : "openai"
        let candidates = conversations.filter { conversation in
            let checkedMatches = checkedIDs.isEmpty || checkedIDs.contains(conversation.id)
            return checkedMatches && conversation.effectiveProvider == sourceProvider
        }
        return MigrationScope(
            conversationIDs: candidates.map(\.id),
            targetProvider: targetProvider,
            sourceProvider: sourceProvider,
            usesSelection: !checkedIDs.isEmpty
        )
    }
}

public struct DeletionReport: Sendable {
    public let deletedCount: Int
    public let deletedDatabaseRowCount: Int
    public let deletedSessionFileCount: Int
    public let deletedIndexEntryCount: Int
    public let backup: BackupRecord

    public init(
        deletedCount: Int,
        deletedDatabaseRowCount: Int,
        deletedSessionFileCount: Int,
        deletedIndexEntryCount: Int,
        backup: BackupRecord
    ) {
        self.deletedCount = deletedCount
        self.deletedDatabaseRowCount = deletedDatabaseRowCount
        self.deletedSessionFileCount = deletedSessionFileCount
        self.deletedIndexEntryCount = deletedIndexEntryCount
        self.backup = backup
    }
}

public extension Conversation {
    var effectiveProvider: String? {
        sessionProvider ?? databaseProvider
    }
}

public struct RunningProcess: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let command: String

    public init(id: Int32, command: String) {
        self.id = id
        self.command = command
    }
}
