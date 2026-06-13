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
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 对话管家"
        window.minSize = NSSize(width: 980, height: 600)
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
    @Published var selectedSource: String?
    @Published var checkedConversationIDs = Set<String>()
    @Published var showProblemsOnly = false
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isScanning = false
    @Published var scanMode = "列表模式"

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
            let sourceMatches = selectedSource == nil ||
                conversation.sourceKind == selectedSource
            let problemMatches = !showProblemsOnly ||
                (conversation.status != .ok && conversation.status != .archived)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches = query.isEmpty ||
                conversation.title.lowercased().contains(query) ||
                conversation.id.lowercased().contains(query) ||
                (conversation.projectPath ?? "").lowercased().contains(query)
            return providerMatches && sourceMatches && problemMatches && searchMatches
        }
    }

    var conversationGroups: [ConversationGroup] {
        let grouped = Dictionary(grouping: conversations) { conversation in
            conversation.projectPath?.isEmpty == false ? conversation.projectPath! : "未知项目"
        }
        return grouped.map { path, conversations in
            ConversationGroup(
                id: path,
                title: ProjectTitle.displayName(path),
                path: path,
                conversations: conversations.sorted {
                    ($0.lastUpdatedAt ?? .distantPast, $0.title, $0.id) >
                    ($1.lastUpdatedAt ?? .distantPast, $1.title, $1.id)
                }
            )
        }
        .sorted {
            (($0.conversations.first?.lastUpdatedAt ?? .distantPast), $0.title) >
            (($1.conversations.first?.lastUpdatedAt ?? .distantPast), $1.title)
        }
    }

    var selectedConversation: Conversation? {
        if let selectedConversationID,
           let selected = conversations.first(where: { $0.id == selectedConversationID }) {
            return selected
        }
        return conversations.first
    }

    var totalCount: Int {
        result?.conversations.count ?? 0
    }

    var problemCount: Int {
        result?.diagnostics.totalProblems ?? 0
    }

    var checkedCount: Int {
        checkedIDsInCurrentList().count
    }

    var checkedProviderSummary: String {
        let checked = checkedConversationsInCurrentList()
        guard !checked.isEmpty else {
            return selectedConversation?.effectiveProvider.map(ProviderText.name) ?? "未选择"
        }
        let api = checked.filter { $0.effectiveProvider == "custom" }.count
        let official = checked.filter { $0.effectiveProvider == "openai" }.count
        if api > 0, official > 0 {
            return "API \(api) / 官方 \(official)"
        }
        if api > 0 {
            return "API \(api)"
        }
        if official > 0 {
            return "官方 \(official)"
        }
        return "\(checked.count) 条"
    }

    func providerCount(_ provider: String) -> Int {
        result?.conversations.filter { $0.effectiveProvider == provider }.count ?? 0
    }

    func sourceCount(_ sourceKind: String) -> Int {
        result?.conversations.filter { $0.sourceKind == sourceKind }.count ?? 0
    }

    func setFilter(provider: String? = nil, source: String? = nil, problemsOnly: Bool = false) {
        selectedProvider = provider
        selectedSource = source
        showProblemsOnly = problemsOnly
        pruneCheckedIDs()
        keepSelectionVisible()
    }

    func selectConversation(_ conversation: Conversation) {
        selectedConversationID = conversation.id
    }

    func toggleChecked(_ conversation: Conversation) {
        selectedConversationID = conversation.id
        if checkedConversationIDs.contains(conversation.id) {
            checkedConversationIDs.remove(conversation.id)
        } else {
            checkedConversationIDs.insert(conversation.id)
        }
    }

    func isChecked(_ conversation: Conversation) -> Bool {
        checkedConversationIDs.contains(conversation.id)
    }

    func clearChecked() {
        checkedConversationIDs.removeAll()
    }

    func checkAllVisible() {
        checkedConversationIDs.formUnion(conversations.map(\.id))
        keepSelectionVisible()
    }

    func refresh() {
        Task { await refreshQuick() }
    }

    func syncDeep() {
        Task { await refreshDeep() }
    }

    func createBackup() {
        guard let result else {
            errorMessage = "请先刷新列表，再创建备份。"
            return
        }
        do {
            let backup = try backupManager.createBackup(
                root: root,
                reason: "手动备份",
                conversationCount: result.conversations.count
            )
            infoMessage = "备份完成：\(backup.backupDirectory.path)"
            errorMessage = nil
        } catch {
            errorMessage = readableMessage(error)
        }
    }

    func restoreLatestBackup() {
        do {
            let backup = try migrationEngine.restoreLatestBackup(root: root)
            infoMessage = "已恢复最近备份：\(backup.backupDirectory.path)"
            errorMessage = nil
            Task { await refreshQuick() }
        } catch {
            errorMessage = readableMessage(error)
        }
    }

    func migrateAll(from sourceProvider: String, to targetProvider: String) {
        let ids = result?.conversations
            .filter { $0.effectiveProvider == sourceProvider }
            .map(\.id) ?? []
        performMigration(ids: ids, targetProvider: targetProvider, scopeName: "全部\(ProviderText.name(sourceProvider))会话")
    }

    func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 数据目录"
        panel.message = "请选择本机的 .codex 文件夹。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            root = url
            selectedProvider = nil
            selectedSource = nil
            checkedConversationIDs.removeAll()
            selectedConversationID = nil
            refresh()
        }
    }

    func dismissMessages() {
        infoMessage = nil
        errorMessage = nil
    }

    private func refreshQuick() async {
        isScanning = true
        scanMode = "读取列表"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.quickScan(root: root)
            }.value
            result = scan
            scanMode = "列表模式"
            keepSelection(in: scan)
        } catch {
            result = nil
            selectedConversationID = nil
            checkedConversationIDs.removeAll()
            errorMessage = readableMessage(error)
        }
        isScanning = false
    }

    private func refreshDeep() async {
        isScanning = true
        scanMode = "同步校验"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(root: root)
            }.value
            result = scan
            scanMode = "校验完成"
            keepSelection(in: scan)
        } catch {
            errorMessage = readableMessage(error)
        }
        isScanning = false
    }

    private func performMigration(ids: [String], targetProvider: String, scopeName: String) {
        guard !ids.isEmpty else {
            errorMessage = "没有可转换的会话。"
            infoMessage = nil
            return
        }

        isScanning = true
        scanMode = "正在转换"
        errorMessage = nil
        infoMessage = nil

        let root = self.root
        let engine = self.migrationEngine
        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try engine.migrate(
                        root: root,
                        conversationIDs: ids,
                        targetProvider: targetProvider
                    )
                }.value
                checkedConversationIDs.subtract(ids)
                infoMessage = "\(scopeName)已转换到\(ProviderText.name(report.targetProvider))，共 \(report.migratedCount) 条。已自动备份。"
                await refreshQuick()
            } catch {
                errorMessage = readableMessage(error)
                scanMode = "列表模式"
                isScanning = false
            }
        }
    }

    private func performDeletion(ids: [String], scopeName: String) {
        guard !ids.isEmpty else {
            errorMessage = "没有可删除的会话。"
            infoMessage = nil
            return
        }

        isScanning = true
        scanMode = "正在删除"
        errorMessage = nil
        infoMessage = nil

        let root = self.root
        let engine = self.migrationEngine
        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try engine.delete(root: root, conversationIDs: ids)
                }.value
                checkedConversationIDs.subtract(ids)
                if ids.contains(selectedConversationID ?? "") {
                    selectedConversationID = nil
                }
                infoMessage = "\(scopeName)已删除，共 \(report.deletedCount) 条。清理文件 \(report.deletedSessionFileCount) 个、索引 \(report.deletedIndexEntryCount) 条、数据库 \(report.deletedDatabaseRowCount) 条。已自动备份。"
                await refreshQuick()
            } catch {
                errorMessage = readableMessage(error)
                scanMode = "列表模式"
                isScanning = false
            }
        }
    }

    private func selectedConversationIDsForAction() -> [String] {
        let checked = checkedIDsInCurrentList()
        if !checked.isEmpty {
            return checked
        }
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return [selectedConversationID]
        }
        return selectedConversation.map { [$0.id] } ?? []
    }

    func candidateConversationIDs(to targetProvider: String) -> [String] {
        let sourceProvider = targetProvider == "openai" ? "custom" : "openai"
        let baseIDs = selectedConversationIDsForAction()
        let conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        return baseIDs.filter { id in
            conversationsByID[id]?.effectiveProvider == sourceProvider
        }
    }

    func selectedScopeName(to targetProvider: String) -> String {
        let count = candidateConversationIDs(to: targetProvider).count
        if checkedCount > 0 {
            return "已勾选 \(count) 条会话"
        }
        return "选中会话"
    }

    func migrateSelection(to targetProvider: String) {
        let ids = candidateConversationIDs(to: targetProvider)
        performMigration(ids: ids, targetProvider: targetProvider, scopeName: selectedScopeName(to: targetProvider))
    }

    func deleteSelection() {
        let ids = selectedConversationIDsForAction()
        let scopeName = checkedCount > 0 ? "已勾选 \(ids.count) 条会话" : "当前会话"
        performDeletion(ids: ids, scopeName: scopeName)
    }

    func deleteConversation(_ conversation: Conversation) {
        performDeletion(ids: [conversation.id], scopeName: "当前会话")
    }

    private func keepSelection(in scan: ScanResult) {
        pruneCheckedIDs(scan.conversations)
        if selectedConversationID == nil || !(scan.conversations.contains { $0.id == selectedConversationID }) {
            selectedConversationID = conversations.first?.id ?? scan.conversations.first?.id
        }
    }

    private func keepSelectionVisible() {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return
        }
        selectedConversationID = conversations.first?.id
    }

    private func checkedIDsInCurrentList() -> [String] {
        let visibleIDs = Set(conversations.map(\.id))
        return checkedConversationIDs.filter { visibleIDs.contains($0) }
    }

    private func checkedConversationsInCurrentList() -> [Conversation] {
        let checkedIDs = Set(checkedIDsInCurrentList())
        return conversations.filter { checkedIDs.contains($0.id) }
    }

    private func pruneCheckedIDs(_ source: [Conversation]? = nil) {
        let validIDs = Set((source ?? conversations).map(\.id))
        checkedConversationIDs = checkedConversationIDs.filter { validIDs.contains($0) }
    }

    private func readableMessage(_ error: Error) -> String {
        if let vaultError = error as? CodexVaultError {
            switch vaultError {
            case .missingCodexRoot(let url):
                return "没有找到 Codex 数据目录：\(url.path)"
            case .unreadableFile(let url):
                return "无法读取文件：\(url.path)"
            case .sqliteOpenFailed(let message):
                return "无法打开 Codex 数据库：\(message)"
            case .sqlitePrepareFailed(let message):
                return "无法查询 Codex 数据库：\(message)"
            case .unsupportedDatabaseSchema:
                return "当前 Codex 数据库结构暂不支持。"
            case .codexIsRunning(let processes):
                let details = processes.map { "\($0.id)：\($0.command)" }.joined(separator: "\n")
                return "请先完全退出 Codex，再操作聊天记录。\n\(details)"
            case .backupFailed(let message):
                return "备份失败：\(message)"
            case .migrationFailed(let message):
                return "操作失败：\(message)"
            }
        }
        return error.localizedDescription
    }
}

struct MainView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)

            if store.errorMessage != nil || store.infoMessage != nil {
                MessageBanner(store: store)
            }

            Divider()

            HStack(spacing: 0) {
                FilterPanel(store: store)
                    .frame(width: 218)

                Divider()

                VStack(spacing: 0) {
                    ConversionPanel(store: store)
                    Divider()
                    ConversationListView(store: store)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                InspectorPanel(store: store)
                    .frame(width: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func confirmBackup() {
        confirm(
            title: "创建聊天记录备份？",
            message: "备份会保存到应用支持目录，转换前也会自动备份。",
            confirmTitle: "创建备份"
        ) {
            store.createBackup()
        }
    }

    private func confirmRestore() {
        confirm(
            title: "恢复最近一次备份？",
            message: "这会替换当前本机 Codex 聊天记录。操作前请完全退出 Codex。",
            confirmTitle: "恢复备份"
        ) {
            store.restoreLatestBackup()
        }
    }

    private func confirm(title: String, message: String, confirmTitle: String, action: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }
}

struct HeaderView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        HStack(spacing: 14) {
            AppMark()

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 对话管家")
                    .font(.system(size: 18, weight: .semibold))
                Text("Codex 聊天记录转换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HeaderButton(title: "刷新列表", icon: "arrow.clockwise") {
                store.refresh()
            }
            HeaderButton(title: "同步校验", icon: "arrow.triangle.2.circlepath") {
                store.syncDeep()
            }
            HeaderButton(title: "选择目录", icon: "folder") {
                store.chooseCodexRoot()
            }
            HeaderButton(title: "备份", icon: "externaldrive") {
                confirm(
                    title: "创建聊天记录备份？",
                    message: "备份会保存到应用支持目录，转换前也会自动备份。",
                    confirmTitle: "创建备份"
                ) {
                    store.createBackup()
                }
            }
            HeaderButton(title: "恢复", icon: "clock.arrow.circlepath") {
                confirm(
                    title: "恢复最近一次备份？",
                    message: "这会替换当前本机 Codex 聊天记录。操作前请完全退出 Codex。",
                    confirmTitle: "恢复备份"
                ) {
                    store.restoreLatestBackup()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func confirm(title: String, message: String, confirmTitle: String, action: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }
}

struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.black.opacity(0.78))
        }
        .frame(width: 40, height: 40)
    }
}

struct HeaderButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct MessageBanner: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.errorMessage == nil ? .green : .orange)
            Text(store.errorMessage ?? store.infoMessage ?? "")
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button {
                store.dismissMessages()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(store.errorMessage == nil ? Color.green.opacity(0.08) : Color.orange.opacity(0.10))
    }
}

struct FilterPanel: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("会话范围")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                FilterRow(
                    title: "全部会话",
                    icon: "tray.full",
                    count: store.totalCount,
                    selected: store.selectedProvider == nil && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: nil)
                }

                FilterRow(
                    title: "API 会话",
                    icon: "network",
                    count: store.providerCount("custom"),
                    selected: store.selectedProvider == "custom" && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: "custom")
                }

                FilterRow(
                    title: "官方会话",
                    icon: "checkmark.seal",
                    count: store.providerCount("openai"),
                    selected: store.selectedProvider == "openai" && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: "openai")
                }

                FilterRow(
                    title: "异常会话",
                    icon: "exclamationmark.triangle",
                    count: store.problemCount,
                    selected: store.showProblemsOnly
                ) {
                    store.setFilter(provider: nil, problemsOnly: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("使用方式")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                FilterRow(
                    title: "桌面会话",
                    icon: "macwindow",
                    count: store.sourceCount("desktop"),
                    selected: store.selectedSource == "desktop"
                ) {
                    store.setFilter(source: "desktop")
                }

                FilterRow(
                    title: "CLI 会话",
                    icon: "terminal",
                    count: store.sourceCount("cli"),
                    selected: store.selectedSource == "cli"
                ) {
                    store.setFilter(source: "cli")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("当前目录")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(store.root.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text(store.scanMode)
                    .font(.caption)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    if store.isScanning {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    }
                    Text(store.result?.databaseAvailable == true ? "读取 SQLite 列表" : "等待数据")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }
}

struct FilterRow: View {
    let title: String
    let icon: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(selected ? Color.black.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct ConversionPanel: View {
    @ObservedObject var store: VaultStore

    var selectedProvider: String? {
        store.selectedConversation?.effectiveProvider
    }

    var apiCandidateCount: Int {
        store.candidateConversationIDs(to: "openai").count
    }

    var officialCandidateCount: Int {
        store.candidateConversationIDs(to: "custom").count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("一键转换")
                        .font(.system(size: 20, weight: .semibold))
                    Text("勾选多条后批量转换；不勾选时只转换当前选中会话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(store.checkedCount > 0 ? "已勾选" : "当前会话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.checkedProviderSummary)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
            }

            HStack(spacing: 10) {
                DirectionButton(
                    title: "API → 官方",
                    subtitle: apiCandidateCount > 0 ? "\(apiCandidateCount) 条转到官方" : "没有可转换的 API 会话",
                    icon: "arrow.right.circle.fill",
                    prominent: true,
                    disabled: apiCandidateCount == 0
                ) {
                    confirmMigration(
                        title: "把 \(apiCandidateCount) 条会话转换到官方？",
                        message: "会自动备份本机聊天记录。操作前请完全退出 Codex。",
                        confirmTitle: "转换到官方"
                    ) {
                        store.migrateSelection(to: "openai")
                    }
                }

                DirectionButton(
                    title: "官方 → API",
                    subtitle: officialCandidateCount > 0 ? "\(officialCandidateCount) 条转到 API" : "没有可转换的官方会话",
                    icon: "arrow.left.circle",
                    prominent: false,
                    disabled: officialCandidateCount == 0
                ) {
                    confirmMigration(
                        title: "把 \(officialCandidateCount) 条会话转换到 API？",
                        message: "会自动备份本机聊天记录。操作前请完全退出 Codex。",
                        confirmTitle: "转换到 API"
                    ) {
                        store.migrateSelection(to: "custom")
                    }
                }

                VStack(spacing: 8) {
                    BatchButton(
                        title: "全部 API → 官方",
                        count: store.providerCount("custom"),
                        disabled: store.providerCount("custom") == 0
                    ) {
                        confirmMigration(
                            title: "把全部 API 会话转换到官方？",
                            message: "共 \(store.providerCount("custom")) 条。会自动备份。操作前请完全退出 Codex。",
                            confirmTitle: "全部转官方"
                        ) {
                            store.migrateAll(from: "custom", to: "openai")
                        }
                    }

                    BatchButton(
                        title: "全部官方 → API",
                        count: store.providerCount("openai"),
                        disabled: store.providerCount("openai") == 0
                    ) {
                        confirmMigration(
                            title: "把全部官方会话转换到 API？",
                            message: "共 \(store.providerCount("openai")) 条。会自动备份。操作前请完全退出 Codex。",
                            confirmTitle: "全部转 API"
                        ) {
                            store.migrateAll(from: "openai", to: "custom")
                        }
                    }

                    BatchButton(
                        title: store.checkedCount > 0 ? "删除已勾选" : "删除当前会话",
                        count: store.checkedCount > 0 ? store.checkedCount : min(store.conversations.count, 1),
                        disabled: store.conversations.isEmpty,
                        destructive: true
                    ) {
                        let count = store.checkedCount > 0 ? store.checkedCount : 1
                        confirmMigration(
                            title: "删除 \(count) 条会话？",
                            message: "会先自动备份，再删除会话文件、列表索引和数据库记录。操作前请完全退出 Codex。",
                            confirmTitle: "删除会话"
                        ) {
                            store.deleteSelection()
                        }
                    }
                }
                .frame(width: 190)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func confirmMigration(title: String, message: String, confirmTitle: String, action: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        if confirmTitle.contains("删除") {
            alert.alertStyle = .warning
        }
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }
}

struct DirectionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let prominent: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(prominent ? Color.white.opacity(0.72) : Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 68)
            .background(prominent ? Color.black : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(prominent ? Color.clear : Color.black.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(disabled ? 0.38 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct BatchButton: View {
    let title: String
    let count: Int
    let disabled: Bool
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(destructive ? Color.red.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(destructive ? Color.red.opacity(0.25) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(disabled ? 0.38 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct ConversationListView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            ListHeaderView(store: store)

            if let error = store.errorMessage {
                ContentUnavailableView("无法读取会话列表", systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.conversations.isEmpty {
                ContentUnavailableView("没有匹配的会话", systemImage: "tray", description: Text("请调整搜索或范围。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.conversationGroups) { group in
                            ConversationGroupView(group: group, store: store)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }
}

struct ListHeaderView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、会话 ID 或项目路径", text: $store.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                MetricView(title: "总数", value: "\(store.totalCount)")
                MetricView(title: "API", value: "\(store.providerCount("custom"))")
                MetricView(title: "官方", value: "\(store.providerCount("openai"))")
                MetricView(title: "异常", value: "\(store.problemCount)")

                Divider()
                    .frame(height: 28)

                Button {
                    store.checkAllVisible()
                } label: {
                    Label("全选当前列表", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.clearChecked()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.checkedCount == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ConversationGroupView: View {
    let group: ConversationGroup
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(group.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(group.conversations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .help(group.path)

            VStack(spacing: 2) {
                ForEach(group.conversations) { conversation in
                    ConversationRowView(
                        conversation: conversation,
                        selected: store.selectedConversationID == conversation.id,
                        checked: store.isChecked(conversation),
                        toggleChecked: { store.toggleChecked(conversation) },
                        select: { store.selectConversation(conversation) }
                    )
                }
            }
        }
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let selected: Bool
    let checked: Bool
    let toggleChecked: () -> Void
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Button(action: toggleChecked) {
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(checked ? Color.black : Color.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(checked ? "取消勾选" : "勾选会话")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(conversation.title)
                            .font(.system(size: 14, weight: selected ? .semibold : .medium))
                            .lineLimit(1)

                        SourcePill(sourceKind: conversation.sourceKind)
                        ProviderPill(provider: conversation.effectiveProvider)
                    }

                    Text(conversation.projectPath ?? conversation.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(RelativeTimeText.string(from: conversation.lastUpdatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    StatusBadge(status: conversation.status)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 54)
            .background(selected ? Color.black.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 48, alignment: .leading)
    }
}

struct InspectorPanel: View {
    @ObservedObject var store: VaultStore

    var conversation: Conversation? {
        store.selectedConversation
    }

    var body: some View {
        if let conversation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("会话信息")
                            .font(.system(size: 20, weight: .semibold))
                        HStack {
                            StatusBadge(status: conversation.status)
                            SourcePill(sourceKind: conversation.sourceKind)
                            ProviderPill(provider: conversation.effectiveProvider)
                            Text(shortID(conversation.id))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    DetailSection("归属") {
                        DetailRow("当前归属", ProviderText.name(conversation.effectiveProvider))
                        DetailRow("数据库归属", ProviderText.name(conversation.databaseProvider))
                        DetailRow("文件归属", ProviderText.name(conversation.sessionProvider))
                    }

                    DetailSection("标识") {
                        DetailRow("会话 ID", conversation.id, copyable: true)
                        DetailRow("使用方式", SourceText.name(conversation.sourceKind))
                        DetailRow("项目路径", conversation.projectPath ?? "未知")
                        DetailRow("归档状态", conversation.isArchived ? "已归档" : "未归档")
                    }

                    DetailSection("文件") {
                        DetailRow("Codex 目录", store.root.path)
                        DetailRow("记录文件", conversation.sessionFilePath?.path ?? "未找到")
                    }

                    DetailSection("操作") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button {
                                    copy(conversation.id)
                                } label: {
                                    Label("复制 ID", systemImage: "doc.on.doc")
                                }

                                Button {
                                    reveal(conversation.sessionFilePath ?? store.root)
                                } label: {
                                    Label("在访达中显示", systemImage: "finder")
                                }
                                .disabled(conversation.sessionFilePath == nil)
                            }

                            Button {
                                confirmDelete(conversation)
                            } label: {
                                Label("删除这条会话", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .tint(.red)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            ContentUnavailableView("未选择会话", systemImage: "sidebar.right", description: Text("从列表中选择一条会话。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func confirmDelete(_ conversation: Conversation) {
        let alert = NSAlert()
        alert.messageText = "删除这条会话？"
        alert.informativeText = "会先自动备份，再删除会话文件、列表索引和数据库记录。操作前请完全退出 Codex。"
        alert.addButton(withTitle: "删除会话")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteConversation(conversation)
        }
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

struct ProviderPill: View {
    let provider: String?

    var body: some View {
        Text(ProviderText.name(provider))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch provider {
        case "openai":
            return .black.opacity(0.08)
        case "custom":
            return .blue.opacity(0.12)
        default:
            return .gray.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch provider {
        case "openai":
            return .primary
        case "custom":
            return .blue
        default:
            return .secondary
        }
    }
}

struct SourcePill: View {
    let sourceKind: String

    var body: some View {
        Text(SourceText.name(sourceKind))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(sourceKind == "desktop" ? Color.teal.opacity(0.12) : Color.purple.opacity(0.10))
            .foregroundStyle(sourceKind == "desktop" ? Color.teal : Color.purple)
            .clipShape(Capsule())
    }
}

struct StatusBadge: View {
    let status: ConversationStatus

    var body: some View {
        Text(status.chineseName)
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

enum ProviderText {
    static func name(_ provider: String?) -> String {
        switch provider {
        case "openai":
            return "官方"
        case "custom":
            return "API"
        case .some(let provider):
            return provider
        case .none:
            return "未知"
        }
    }
}

enum SourceText {
    static func name(_ sourceKind: String) -> String {
        switch sourceKind {
        case "desktop":
            return "桌面"
        case "cli":
            return "CLI"
        default:
            return "未知"
        }
    }
}

enum ProjectTitle {
    static func displayName(_ path: String) -> String {
        guard path != "未知项目" else {
            return path
        }
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        if last.isEmpty {
            return path
        }
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty || parent == "/" {
            return last
        }
        return "\(parent)/\(last)"
    }
}

enum RelativeTimeText {
    static func string(from date: Date?) -> String {
        guard let date else {
            return "-"
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "刚刚"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时"
        }
        let days = hours / 24
        if days < 7 {
            return "\(days) 天"
        }
        let weeks = days / 7
        if weeks < 5 {
            return "\(weeks) 周"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

struct ConversationGroup: Identifiable {
    let id: String
    let title: String
    let path: String
    let conversations: [Conversation]
}

extension Conversation {
    var effectiveProvider: String? {
        sessionProvider ?? databaseProvider
    }

    var sourceKind: String {
        switch source {
        case "exec", "cli", "terminal":
            return "cli"
        case "vscode", "desktop", "app":
            return "desktop"
        default:
            return "desktop"
        }
    }
}

extension ConversationStatus {
    var chineseName: String {
        switch self {
        case .ok:
            return "正常"
        case .providerMismatch:
            return "归属不一致"
        case .missingDatabaseRow:
            return "缺少数据库"
        case .missingSessionFile:
            return "缺少文件"
        case .unreadableSessionFile:
            return "无法读取"
        case .archived:
            return "已归档"
        }
    }
}
