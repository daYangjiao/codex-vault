import AppKit
import CodexVaultCore
import SwiftUI

@main
struct CodexVaultApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = VaultStore()
        let contentView = MainView(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Vault"
        window.minSize = NSSize(width: 920, height: 560)
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class VaultStore: ObservableObject {
    @Published var root: URL
    @Published var result: ScanResult?
    @Published var selectedConversationID: String?
    @Published var selectedProvider: String?
    @Published var showProblemsOnly = false
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isScanning = false
    @Published var scanMode = "Quick list"

    private let locator = CodexRootLocator()
    private let scanner = CodexVaultScanner()
    private let migrationEngine = MigrationEngine()
    private let backupManager = BackupManager()

    init() {
        self.root = locator.defaultRoot()
        Task { await refreshQuick() }
    }

    var conversations: [Conversation] {
        guard let result else {
            return []
        }
        return result.conversations.filter { conversation in
            let providerMatches = selectedProvider == nil ||
                conversation.sessionProvider == selectedProvider ||
                conversation.databaseProvider == selectedProvider
            let problemMatches = !showProblemsOnly ||
                (conversation.status != .ok && conversation.status != .archived)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches = query.isEmpty ||
                conversation.title.lowercased().contains(query) ||
                conversation.id.lowercased().contains(query) ||
                (conversation.projectPath ?? "").lowercased().contains(query)
            return providerMatches && problemMatches && searchMatches
        }
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID } ?? conversations.first
    }

    func refresh() {
        Task { await refreshQuick() }
    }

    func syncDeep() {
        Task { await refreshDeep() }
    }

    private func refreshQuick() async {
        isScanning = true
        scanMode = "Loading list"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.quickScan(root: root)
            }.value
            result = scan
            scanMode = "Quick list"
            if selectedConversationID == nil || !(scan.conversations.contains { $0.id == selectedConversationID }) {
                selectedConversationID = scan.conversations.first?.id
            }
        } catch {
            result = nil
            selectedConversationID = nil
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    private func refreshDeep() async {
        isScanning = true
        scanMode = "Syncing files"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(root: root)
            }.value
            result = scan
            scanMode = "Synced"
            if selectedConversationID == nil || !(scan.conversations.contains { $0.id == selectedConversationID }) {
                selectedConversationID = scan.conversations.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    func createBackup() {
        guard let result else {
            errorMessage = "Scan Codex data before creating a backup."
            return
        }
        do {
            let backup = try backupManager.createBackup(
                root: root,
                reason: "Manual backup",
                conversationCount: result.conversations.count
            )
            infoMessage = "Backup created: \(backup.backupDirectory.path)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func migrateSelection(to targetProvider: String) {
        let ids = selectedConversationIDsForAction()
        do {
            let report = try migrationEngine.migrate(
                root: root,
                conversationIDs: ids,
                targetProvider: targetProvider
            )
            infoMessage = "Migrated \(report.migratedCount) conversation(s) to \(report.targetProvider). Backup: \(report.backup.backupDirectory.path)"
            Task { await refreshQuick() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreLatestBackup() {
        do {
            let backup = try migrationEngine.restoreLatestBackup(root: root)
            infoMessage = "Restored backup: \(backup.backupDirectory.path)"
            Task { await refreshQuick() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose Codex Data Directory"
        panel.message = "Select the .codex directory to scan."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            root = url
            selectedProvider = nil
            selectedConversationID = nil
            refresh()
        }
    }

    private func selectedConversationIDsForAction() -> [String] {
        if let selectedConversationID {
            return [selectedConversationID]
        }
        return selectedConversation.map { [$0.id] } ?? []
    }
}

struct MainView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } content: {
            ConversationListView(store: store)
                .navigationSplitViewColumnWidth(min: 420, ideal: 540)
        } detail: {
            ConversationDetailView(conversation: store.selectedConversation, root: store.root)
                .navigationSplitViewColumnWidth(min: 320, ideal: 390)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh the fast SQLite conversation list")

                Button {
                    store.syncDeep()
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Scan session files for deeper provider diagnostics")

                Button {
                    store.chooseCodexRoot()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }
                .help("Choose Codex data directory")

                Button {
                    confirmBackup(store: store)
                } label: {
                    Label("Backup", systemImage: "externaldrive")
                }
                .help("Create a backup of local Codex history")

                Button {
                    promptMigration(store: store)
                } label: {
                    Label("Migrate", systemImage: "arrow.left.arrow.right")
                }
                .help("Migrate the selected conversation to another provider")

                Button {
                    confirmRestore(store: store)
                } label: {
                    Label("Restore", systemImage: "clock.arrow.circlepath")
                }
                .help("Restore the latest Codex Vault backup")
            }
        }
    }

    private func confirmBackup(store: VaultStore) {
        let alert = NSAlert()
        alert.messageText = "Create a Codex history backup?"
        alert.informativeText = "The backup is stored in ~/Library/Application Support/Codex Vault/Backups."
        alert.addButton(withTitle: "Create Backup")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.createBackup()
            showStoreMessage(store)
        }
    }

    private func promptMigration(store: VaultStore) {
        guard store.selectedConversation != nil else {
            showAlert(title: "No conversation selected", message: "Select a conversation before migrating.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Migrate selected conversation"
        alert.informativeText = "Enter the target provider, for example openai or custom. Codex must be fully closed before migration."
        alert.addButton(withTitle: "Migrate")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "custom"
        field.stringValue = store.selectedConversation?.sessionProvider == "openai" ? "custom" : "openai"
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            store.migrateSelection(to: field.stringValue)
            showStoreMessage(store)
        }
    }

    private func confirmRestore(store: VaultStore) {
        let alert = NSAlert()
        alert.messageText = "Restore latest backup?"
        alert.informativeText = "This replaces the current local Codex history files with the latest Codex Vault backup. Codex must be fully closed."
        alert.addButton(withTitle: "Restore Latest")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.restoreLatestBackup()
            showStoreMessage(store)
        }
    }

    private func showStoreMessage(_ store: VaultStore) {
        if let error = store.errorMessage {
            showAlert(title: "Codex Vault", message: error)
        } else if let info = store.infoMessage {
            showAlert(title: "Codex Vault", message: info)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct SidebarView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        List(selection: sidebarSelection) {
            Section("Library") {
                Label("All Conversations", systemImage: "tray.full")
                    .tag(SidebarSelection.all)
                Label("Problems", systemImage: "exclamationmark.triangle")
                    .tag(SidebarSelection.problems)
            }

            if let result = store.result {
                Section("Providers") {
                    ForEach(result.providerSummaries) { provider in
                        HStack {
                            Label(provider.id, systemImage: "shippingbox")
                            Spacer()
                            Text("\(provider.conversationCount)")
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarSelection.provider(provider.id))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.root.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let result = store.result {
                    Text("\(result.conversations.count) conversations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .navigationTitle("Codex Vault")
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding {
            if store.showProblemsOnly {
                return .problems
            }
            if let provider = store.selectedProvider {
                return .provider(provider)
            }
            return .all
        } set: { selection in
            switch selection {
            case .all, .none:
                store.selectedProvider = nil
                store.showProblemsOnly = false
            case .problems:
                store.selectedProvider = nil
                store.showProblemsOnly = true
            case .provider(let provider):
                store.selectedProvider = provider
                store.showProblemsOnly = false
            }
        }
    }
}

enum SidebarSelection: Hashable {
    case all
    case problems
    case provider(String)
}

struct ConversationListView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            SearchHeaderView(store: store)

            if let error = store.errorMessage {
                ContentUnavailableView("Cannot Scan Codex Data", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.conversations.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "tray", description: Text("No conversations matched the current filters."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.conversations, selection: $store.selectedConversationID) {
                    TableColumn("Title") { conversation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title)
                                .lineLimit(1)
                            Text(conversation.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 210, ideal: 260)

                    TableColumn("Provider") { conversation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.sessionProvider ?? conversation.databaseProvider ?? "Unknown")
                            if conversation.sessionProvider != conversation.databaseProvider,
                               conversation.sessionProvider != nil,
                               conversation.databaseProvider != nil {
                                Text("DB: \(conversation.databaseProvider ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("Project") { conversation in
                        Text(conversation.projectPath ?? "Unknown")
                            .lineLimit(1)
                    }
                    .width(min: 160, ideal: 220)

                    TableColumn("Status") { conversation in
                        StatusBadge(status: conversation.status)
                    }
                    .width(min: 110, ideal: 140)
                }
            }
        }
        .navigationTitle("Conversations")
    }
}

struct SearchHeaderView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title, session ID, or project path", text: $store.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let result = store.result {
                HStack(spacing: 16) {
                    MetricView(title: "Total", value: "\(result.conversations.count)")
                    MetricView(title: "Providers", value: "\(result.providerSummaries.count)")
                    MetricView(title: "Problems", value: "\(result.diagnostics.totalProblems)")
                    Spacer()
                    if store.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 18, height: 18)
                    }
                    Text("\(store.scanMode) · \(result.databaseAvailable ? "SQLite" : "Files")")
                        .font(.caption)
                        .foregroundStyle(result.databaseAvailable ? Color.secondary : Color.orange)
                }
            }
        }
        .padding(14)
        .background(.bar)
    }
}

struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ConversationDetailView: View {
    let conversation: Conversation?
    let root: URL

    var body: some View {
        if let conversation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session")
                            .font(.title2)
                            .fontWeight(.semibold)
                        HStack {
                            StatusBadge(status: conversation.status)
                            Text(shortID(conversation.id))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    DetailSection("Preview") {
                        Text(conversation.title)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }

                    DetailSection("Identity") {
                        DetailRow("Session ID", conversation.id, copyable: true)
                        DetailRow("Project", conversation.projectPath ?? "Unknown")
                        DetailRow("Archived", conversation.isArchived ? "Yes" : "No")
                    }

                    DetailSection("Provider") {
                        DetailRow("Session file", conversation.sessionProvider ?? "Missing")
                        DetailRow("Database", conversation.databaseProvider ?? "Missing")
                    }

                    DetailSection("Files") {
                        DetailRow("Codex root", root.path)
                        DetailRow("Session file", conversation.sessionFilePath?.path ?? "Missing")
                    }

                    DetailSection("Actions") {
                        HStack {
                            Button {
                                copy(conversation.id)
                            } label: {
                                Label("Copy ID", systemImage: "doc.on.doc")
                            }

                            Button {
                                reveal(conversation.sessionFilePath ?? root)
                            } label: {
                                Label("Reveal", systemImage: "finder")
                            }
                            .disabled(conversation.sessionFilePath == nil)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select a conversation to inspect it."))
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let copyable: Bool

    init(_ label: String, _ value: String, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .lineLimit(4)
        }
    }
}

struct StatusBadge: View {
    let status: ConversationStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch status {
        case .ok:
            return .green.opacity(0.15)
        case .archived:
            return .gray.opacity(0.18)
        case .providerMismatch:
            return .orange.opacity(0.18)
        case .missingDatabaseRow, .missingSessionFile, .unreadableSessionFile:
            return .red.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch status {
        case .ok:
            return .green
        case .archived:
            return .secondary
        case .providerMismatch:
            return .orange
        case .missingDatabaseRow, .missingSessionFile, .unreadableSessionFile:
            return .red
        }
    }
}
