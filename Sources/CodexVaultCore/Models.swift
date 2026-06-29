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
        // 转换到官方(openai)：源是任意「第三方 / API」会话（不限于 "custom"）。
        // 转换到 API(任意第三方 id)：源是官方会话。
        let targetIsOfficial = targetProvider == ProviderCategory.officialID
        let candidates = conversations.filter { conversation in
            let checkedMatches = checkedIDs.isEmpty || checkedIDs.contains(conversation.id)
            let providerMatches = targetIsOfficial ? conversation.isApiProvider : conversation.isOfficialProvider
            return checkedMatches && providerMatches
        }
        return MigrationScope(
            conversationIDs: candidates.map(\.id),
            targetProvider: targetProvider,
            sourceProvider: targetIsOfficial ? "api" : ProviderCategory.officialID,
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

    /// 官方 = Codex 内置的 "openai"。
    var isOfficialProvider: Bool {
        effectiveProvider == ProviderCategory.officialID
    }

    /// API / 第三方 = 任何非空、且不是 "openai" 的 provider（不限于 "custom"）。
    var isApiProvider: Bool {
        guard let provider = effectiveProvider, !provider.isEmpty else {
            return false
        }
        return provider != ProviderCategory.officialID
    }
}

public enum CodexConfig {
    /// 读取 `<root>/config.toml` 顶层的 `model_provider = "x"` 值（即当前激活的 provider id）。
    /// 只看进入第一个 `[table]` 段之前的顶层键，避免误读 `[model_providers.x]` 段内字段。
    public static func currentModelProvider(root: URL) -> String? {
        let url = root.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                break
            }
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard line.hasPrefix("model_provider"), let eq = line.firstIndex(of: "=") else {
                continue
            }
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

public enum ProviderCategory {
    /// Codex 官方 provider 的固定 id。
    public static let officialID = "openai"
    /// 探测不到第三方 provider 时的兜底 id（多数 cc-switch 用户即为此值）。
    public static let fallbackApiID = "custom"

    /// 本机「API / 第三方」provider 的 id。不同用户在 config.toml 里给第三方 provider 起的名字
    /// 不一定叫 "custom"（可能是 "aigocode_team" 等），所以这里按会话里出现最多的非官方 provider 推断，
    /// 作为「转换到 API」时要写入的目标 id。`preferred` 可传入当前配置里的 model_provider 优先采用。
    public static func apiProviderID(conversations: [Conversation], preferred: String? = nil) -> String {
        if let preferred, !preferred.isEmpty, preferred != officialID {
            return preferred
        }
        var counts: [String: Int] = [:]
        for conversation in conversations {
            guard let provider = conversation.effectiveProvider,
                  !provider.isEmpty,
                  provider != officialID else {
                continue
            }
            counts[provider, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? fallbackApiID
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
