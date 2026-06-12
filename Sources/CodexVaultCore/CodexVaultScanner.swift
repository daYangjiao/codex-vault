import Foundation

public struct CodexVaultScanner: Sendable {
    private let sessionScanner: SessionScanner
    private let stateDatabase: StateDatabase

    public init(sessionScanner: SessionScanner = SessionScanner(), stateDatabase: StateDatabase = StateDatabase()) {
        self.sessionScanner = sessionScanner
        self.stateDatabase = stateDatabase
    }

    public func scan(root: URL) throws -> ScanResult {
        let sessionRecords = try sessionScanner.scan(root: root)
        let databaseURL = root.appendingPathComponent("state_5.sqlite")
        let databaseAvailable = FileManager.default.fileExists(atPath: databaseURL.path)
        let databaseThreads = try stateDatabase.readThreads(databaseURL: databaseURL)
        let conversations = merge(sessionRecords: sessionRecords, databaseThreads: databaseThreads)
        let diagnostics = buildDiagnostics(conversations)
        let providers = buildProviderSummaries(conversations)

        return ScanResult(
            root: root,
            conversations: conversations,
            providerSummaries: providers,
            diagnostics: diagnostics,
            scannedAt: Date(),
            databaseAvailable: databaseAvailable
        )
    }

    private func merge(sessionRecords: [SessionRecord], databaseThreads: [DatabaseThread]) -> [Conversation] {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessionRecords.map { ($0.id, $0) })
        let threadsByID = Dictionary(uniqueKeysWithValues: databaseThreads.map { ($0.id, $0) })
        let allIDs = Set(sessionsByID.keys).union(threadsByID.keys)

        return allIDs.map { id in
            let session = sessionsByID[id]
            let thread = threadsByID[id]
            let status = statusFor(session: session, thread: thread)

            return Conversation(
                id: id,
                title: preferredTitle(session: session, thread: thread),
                sessionProvider: session?.provider,
                databaseProvider: thread?.provider,
                projectPath: session?.projectPath ?? thread?.projectPath,
                sessionFilePath: session?.filePath,
                lastUpdatedAt: maxDate(session?.lastUpdatedAt, thread?.updatedAt),
                isArchived: session?.isArchived ?? thread?.isArchived ?? false,
                status: status
            )
        }
        .sorted {
            ($0.lastUpdatedAt ?? .distantPast, $0.title, $0.id) >
            ($1.lastUpdatedAt ?? .distantPast, $1.title, $1.id)
        }
    }

    private func statusFor(session: SessionRecord?, thread: DatabaseThread?) -> ConversationStatus {
        guard let session else {
            return .missingSessionFile
        }
        guard let thread else {
            return .missingDatabaseRow
        }
        if let sessionProvider = session.provider,
           let databaseProvider = thread.provider,
           sessionProvider != databaseProvider {
            return .providerMismatch
        }
        if session.isArchived || thread.isArchived {
            return .archived
        }
        return .ok
    }

    private func preferredTitle(session: SessionRecord?, thread: DatabaseThread?) -> String {
        let title = thread?.title.isEmpty == false ? thread?.title : session?.title
        return title?.isEmpty == false ? title! : session?.id ?? thread?.id ?? "Untitled"
    }

    private func maxDate(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case (.some(let left), .some(let right)):
            return max(left, right)
        case (.some(let left), .none):
            return left
        case (.none, .some(let right)):
            return right
        case (.none, .none):
            return nil
        }
    }

    private func buildDiagnostics(_ conversations: [Conversation]) -> DiagnosticsSummary {
        DiagnosticsSummary(
            providerMismatches: conversations.filter { $0.status == .providerMismatch }.count,
            missingDatabaseRows: conversations.filter { $0.status == .missingDatabaseRow }.count,
            missingSessionFiles: conversations.filter { $0.status == .missingSessionFile }.count,
            unreadableSessionFiles: conversations.filter { $0.status == .unreadableSessionFile }.count
        )
    }

    private func buildProviderSummaries(_ conversations: [Conversation]) -> [ProviderSummary] {
        let providers = Set(conversations.compactMap { $0.sessionProvider ?? $0.databaseProvider })
        return providers.map { provider in
            let providerConversations = conversations.filter { ($0.sessionProvider ?? $0.databaseProvider) == provider }
            return ProviderSummary(
                id: provider,
                conversationCount: providerConversations.count,
                problemCount: providerConversations.filter { $0.status != .ok && $0.status != .archived }.count
            )
        }
        .sorted { $0.id < $1.id }
    }
}
