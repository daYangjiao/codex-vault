import AppKit
import CodexVaultCore
import SwiftUI

@main
@MainActor
struct CodexVaultApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        let store = VaultStore()
        let contentView = MainView(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 对话管家"
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // 设置菜单栏：没有它就没有「退出」(⌘Q)，搜索框也用不了 ⌘C/⌘V/⌘A。
    private func setupMainMenu() {
        let appName = "Codex 对话管家"
        let mainMenu = NSMenu()

        // 应用菜单（含「退出」）
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单（让搜索框支持复制/粘贴/全选等快捷键）
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 窗口菜单
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
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
    @Published var operationLabel: String?
    @Published var dialog: DialogModel?
    /// 上次点击的转换方向（true=转到官方, false=转到 API, nil=未选）。用于高亮被点击的那个方向按钮。
    @Published var selectedToOfficial: Bool?
    @Published var scanMode = "列表模式"
    @Published var showsInspector = false

    private let locator = CodexRootLocator()
    private let scanner = CodexVaultScanner()
    private let migrationEngine = MigrationEngine()
    private let backupManager = BackupManager()
    private let processGuard = ProcessGuard()
    /// 操作进行中的串行闸门（与展示用的 operationLabel 解耦，弹重试框时也不会被释放）。
    private var isOperating = false
    /// 当前确认弹窗的挂起结果，集中管理以保证只 resume 一次、不泄漏。
    private var pendingDialogResult: CheckedContinuation<Bool, Never>?

    init() {
        self.root = locator.defaultRoot()
        Task { await refreshQuick() }
    }

    var conversations: [Conversation] {
        guard let result else {
            return []
        }
        return result.conversations.filter { conversation in
            let providerMatches: Bool
            switch selectedProvider {
            case nil:
                providerMatches = true
            case ProviderCategory.officialID:
                providerMatches = conversation.isOfficialProvider
            default:
                providerMatches = conversation.isApiProvider
            }
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
        guard let selectedConversationID else {
            return nil
        }
        return conversations.first(where: { $0.id == selectedConversationID })
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
            return "默认全部"
        }
        let api = checked.filter { $0.isApiProvider }.count
        let official = checked.filter { $0.isOfficialProvider }.count
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

    /// API / 第三方会话数（任意非官方 provider）。
    var apiCount: Int {
        result?.conversations.filter { $0.isApiProvider }.count ?? 0
    }

    /// 官方会话数。
    var officialCount: Int {
        result?.conversations.filter { $0.isOfficialProvider }.count ?? 0
    }

    /// 本机「转换到 API」时要写入的第三方 provider id。
    /// 优先用 config.toml 里当前激活的 provider，其次按现有会话推断，兼容非 "custom" 的命名。
    var apiProviderID: String {
        ProviderCategory.apiProviderID(
            conversations: result?.conversations ?? [],
            preferred: CodexConfig.currentModelProvider(root: root)
        )
    }

    /// 侧栏「API 会话」筛选用的哨兵值（非 nil、非 "openai" 即触发「按 API 分类」过滤）。
    static let apiFilterID = "__api__"

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
        showsInspector = true
    }

    func toggleChecked(_ conversation: Conversation) {
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

    /// 备份管理：显示数量与占用大小，可打开文件夹或清空全部。
    func manageBackups() {
        let count = backupManager.listBackups().count
        guard count > 0 else {
            present(DialogModel(
                title: "备份管理",
                message: "暂无备份。",
                systemImage: "archivebox",
                buttons: [
                    DialogButton(label: "打开文件夹", role: .normal) { [weak self] in self?.openBackupsFolder() },
                    DialogButton(label: "关闭", role: .cancel) {}
                ]
            ))
            return
        }
        present(DialogModel(
            title: "备份管理",
            message: "共 \(count) 个备份，约 \(backupManager.totalSizeText())。自动保留最近 \(backupManager.maxBackups) 个。",
            systemImage: "archivebox",
            buttons: [
                DialogButton(label: "打开文件夹", role: .normal) { [weak self] in self?.openBackupsFolder() },
                DialogButton(label: "清空全部", role: .destructive) { [weak self] in self?.confirmClearBackups(count: count) },
                DialogButton(label: "关闭", role: .cancel) {}
            ]
        ))
    }

    private func confirmClearBackups(count: Int) {
        Task { @MainActor in
            if await ask(
                title: "清空全部备份？",
                message: "将删除全部 \(count) 个本地备份，不可恢复。",
                confirmLabel: "清空",
                destructive: true,
                systemImage: "trash.fill",
                iconTint: .red
            ) {
                if backupManager.deleteAllBackups() {
                    infoMessage = "已清空全部备份。"
                } else {
                    errorMessage = "部分备份未能删除，可在文件夹中手动清理。"
                }
            }
        }
    }

    private func openBackupsFolder() {
        let dir = backupManager.backupsRoot
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func migrateAll(from sourceProvider: String, to targetProvider: String) {
        let ids = result?.conversations
            .filter { $0.effectiveProvider == sourceProvider }
            .map(\.id) ?? []
        performMigration(ids: ids, targetProvider: targetProvider, scopeName: "全部\(ProviderText.name(sourceProvider))会话")
    }

    func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 记录目录"
        panel.message = "请选择本机 Codex 的记录目录。"
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
            showsInspector = false
            refresh()
        }
    }

    func dismissMessages() {
        infoMessage = nil
        errorMessage = nil
    }

    func closeInspector() {
        showsInspector = false
    }

    private func refreshQuick() async {
        isScanning = true
        scanMode = "正在更新"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.quickScan(root: root)
            }.value
            result = scan
            scanMode = "已就绪"
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
        scanMode = "正在检查"
        errorMessage = nil
        let root = self.root
        let scanner = self.scanner
        do {
            try locator.validate(root: root)
            let scan = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(root: root)
            }.value
            result = scan
            scanMode = "检查完成"
            keepSelection(in: scan)
        } catch {
            errorMessage = readableMessage(error)
        }
        isScanning = false
    }

    /// 操作前先确认 Codex 已完全退出。返回 true 可继续；false 表示用户取消。
    /// 检测在后台线程跑（已修复死锁），不卡 UI；Codex 在运行就弹「重试/取消」，让用户关掉后重试。
    private func ensureCodexClear() async -> Bool {
        let guardChecker = self.processGuard
        while true {
            operationLabel = "正在检查 Codex 是否已退出…"
            let running = await Task.detached(priority: .userInitiated) {
                guardChecker.runningCodexProcesses()
            }.value
            operationLabel = nil
            if running.isEmpty {
                return true
            }
            let retry = await ask(
                title: "Codex 尚未关闭",
                message: "请先完全退出 Codex（包括 VS Code 里的 Codex），再点重试。",
                confirmLabel: "重试",
                systemImage: "exclamationmark.triangle.fill",
                iconTint: .orange
            )
            if !retry {
                return false
            }
        }
    }

    private func performMigration(ids: [String], targetProvider: String, scopeName: String) {
        guard !ids.isEmpty else {
            errorMessage = "没有可转换的会话。"
            infoMessage = nil
            return
        }

        guard !isOperating else { return }
        isOperating = true
        operationLabel = "正在检查 Codex 是否已退出…"
        errorMessage = nil
        infoMessage = nil

        let root = self.root
        let engine = self.migrationEngine
        Task { @MainActor in
            defer { isOperating = false; operationLabel = nil }
            guard await ensureCodexClear() else { return }

            operationLabel = "正在转换 \(ids.count) 条会话…"
            do {
                // 不传 skipProcessCheck：引擎会在写入前再查一次 Codex（防止预检后用户又打开 Codex 的竞态）。
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
                if case CodexVaultError.codexIsRunning = error {
                    errorMessage = "检测到 Codex 仍在运行，请完全退出 Codex 后重试。"
                } else {
                    errorMessage = readableMessage(error)
                }
            }
        }
    }

    private func performDeletion(ids: [String], scopeName: String) {
        guard !ids.isEmpty else {
            errorMessage = "没有可删除的会话。"
            infoMessage = nil
            return
        }

        guard !isOperating else { return }
        isOperating = true
        operationLabel = "正在检查 Codex 是否已退出…"
        errorMessage = nil
        infoMessage = nil

        let root = self.root
        let engine = self.migrationEngine
        Task { @MainActor in
            defer { isOperating = false; operationLabel = nil }
            guard await ensureCodexClear() else { return }

            operationLabel = "正在删除 \(ids.count) 条会话…"
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try engine.delete(root: root, conversationIDs: ids)
                }.value
                checkedConversationIDs.subtract(ids)
                if ids.contains(selectedConversationID ?? "") {
                    selectedConversationID = nil
                }
                infoMessage = "\(scopeName)已删除，共 \(report.deletedCount) 条。已自动备份。"
                await refreshQuick()
            } catch {
                if case CodexVaultError.codexIsRunning = error {
                    errorMessage = "检测到 Codex 仍在运行，请完全退出 Codex 后重试。"
                } else {
                    errorMessage = readableMessage(error)
                }
            }
        }
    }

    func candidateConversationIDs(to targetProvider: String) -> [String] {
        migrationScope(to: targetProvider).conversationIDs
    }

    func selectedScopeName(to targetProvider: String) -> String {
        let scope = migrationScope(to: targetProvider)
        return scope.usesSelection ? "已选 \(scope.conversationIDs.count) 条会话" : "全部\(ProviderText.name(scope.sourceProvider))会话"
    }

    func migrateSelection(to targetProvider: String) {
        let scope = migrationScope(to: targetProvider)
        performMigration(ids: scope.conversationIDs, targetProvider: targetProvider, scopeName: selectedScopeName(to: targetProvider))
    }

    func deleteSelection() {
        let ids = checkedIDsInCurrentList()
        let scopeName = "已勾选 \(ids.count) 条会话"
        performDeletion(ids: ids, scopeName: scopeName)
    }

    func deleteConversation(_ conversation: Conversation) {
        performDeletion(ids: [conversation.id], scopeName: "这条会话")
    }

    private func keepSelection(in scan: ScanResult) {
        pruneCheckedIDs(scan.conversations)
        if selectedConversationID == nil || !(scan.conversations.contains { $0.id == selectedConversationID }) {
            selectedConversationID = nil
            showsInspector = false
        }
    }

    private func keepSelectionVisible() {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return
        }
        selectedConversationID = nil
        showsInspector = false
    }

    private func checkedIDsInCurrentList() -> [String] {
        let visibleIDs = Set(conversations.map(\.id))
        return checkedConversationIDs.filter { visibleIDs.contains($0) }
    }

    func migrationScope(to targetProvider: String) -> MigrationScope {
        MigrationScopeResolver.resolve(
            conversations: conversations,
            checkedIDs: Set(checkedIDsInCurrentList()),
            targetProvider: targetProvider
        )
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
                return "无法打开 Codex 会话列表：\(message)"
            case .sqlitePrepareFailed(let message):
                return "无法查询 Codex 会话列表：\(message)"
            case .unsupportedDatabaseSchema:
                return "当前 Codex 记录格式暂不支持。"
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

    /// Codex 未关闭时的提示弹窗：只显示一句话，给「重试 / 取消」两个按钮。返回是否点了重试。
    /// 展示一个无返回值的多按钮弹窗。覆盖时先了结任何挂起的确认，避免 continuation 泄漏。
    func present(_ model: DialogModel) {
        pendingDialogResult?.resume(returning: false)
        pendingDialogResult = nil
        dialog = model
    }

    /// 关闭当前弹窗，并（若存在挂起的确认）只 resume 一次。按钮点击、背景点击、被覆盖都走这里。
    func finishDialog(_ result: Bool) {
        dialog = nil
        if let cont = pendingDialogResult {
            pendingDialogResult = nil
            cont.resume(returning: result)
        }
    }

    /// 异步确认弹窗：返回用户是否点了确认按钮。
    func ask(
        title: String,
        message: String? = nil,
        confirmLabel: String,
        cancelLabel: String = "取消",
        destructive: Bool = false,
        systemImage: String? = nil,
        iconTint: Color = Theme.accent1
    ) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            pendingDialogResult?.resume(returning: false)
            pendingDialogResult = cont
            dialog = DialogModel(
                title: title,
                message: message,
                systemImage: systemImage,
                iconTint: iconTint,
                buttons: [
                    DialogButton(label: cancelLabel, role: .cancel) { [weak self] in self?.finishDialog(false) },
                    DialogButton(label: confirmLabel, role: destructive ? .destructive : .primary) { [weak self] in self?.finishDialog(true) }
                ]
            )
        }
    }

    func requestMigrate(toOfficial: Bool) {
        let targetProvider = toOfficial ? ProviderCategory.officialID : apiProviderID
        let scope = migrationScope(to: targetProvider)
        guard !scope.conversationIDs.isEmpty else { return }
        selectedToOfficial = toOfficial
        let count = scope.conversationIDs.count
        let dirText = toOfficial ? "官方" : "API"
        Task { @MainActor in
            if await ask(
                title: "把\(scope.usesSelection ? "已选" : "全部") \(count) 条会话转换到\(dirText)？",
                message: "操作前会自动备份。",
                confirmLabel: "转换到\(dirText)",
                systemImage: "arrow.left.arrow.right.circle.fill"
            ) {
                migrateSelection(to: targetProvider)
            }
        }
    }

    func requestDeleteSelection() {
        let count = checkedCount
        guard count > 0 else { return }
        Task { @MainActor in
            if await ask(
                title: "删除 \(count) 条会话？",
                message: "删除前会自动备份。",
                confirmLabel: "删除会话",
                destructive: true,
                systemImage: "trash.fill",
                iconTint: .red
            ) {
                deleteSelection()
            }
        }
    }

    func requestDeleteConversation(_ conversation: Conversation) {
        Task { @MainActor in
            if await ask(
                title: "删除这条会话？",
                message: "删除前会自动备份。",
                confirmLabel: "删除会话",
                destructive: true,
                systemImage: "trash.fill",
                iconTint: .red
            ) {
                deleteConversation(conversation)
            }
        }
    }

    func requestBackup() {
        Task { @MainActor in
            if await ask(
                title: "创建聊天记录备份？",
                message: "备份会保存到应用支持目录，转换前也会自动备份。",
                confirmLabel: "创建备份",
                systemImage: "externaldrive.fill"
            ) {
                createBackup()
            }
        }
    }

    func requestRestore() {
        Task { @MainActor in
            if await ask(
                title: "恢复最近一次备份？",
                message: "这会替换当前本机 Codex 聊天记录。操作前请完全退出 Codex。",
                confirmLabel: "恢复备份",
                destructive: true,
                systemImage: "clock.arrow.circlepath",
                iconTint: .orange
            ) {
                restoreLatestBackup()
            }
        }
    }
}

enum Theme {
    static let accent1 = Color(red: 0.416, green: 0.471, blue: 1.0)   // #6a78ff
    static let accent2 = Color(red: 0.667, green: 0.337, blue: 0.949) // #aa56f2
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent1, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 自适应颜色：浅色模式用柔和浅灰底 + 纯白卡片，深色模式用深灰，避免原生底色过深。
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    static let page = dynamic(NSColor(red: 0.957, green: 0.961, blue: 0.976, alpha: 1), NSColor(white: 0.11, alpha: 1))
    static let card = dynamic(.white, NSColor(white: 0.17, alpha: 1))
    static let hairline = Color.primary.opacity(0.07)
    static let cardRadius: CGFloat = 14
    static var cardShadow: Color { Color.black.opacity(0.06) }
    static var accentSoft: Color { accent1.opacity(0.12) }
}

/// logo 里的双向交换箭头（上箭头向右、下箭头向左），与预览的 SVG 一致。
struct SwapArrows: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        p.move(to: pt(0.06, 0.30)); p.addLine(to: pt(0.82, 0.30))      // 上 横线
        p.move(to: pt(0.66, 0.08)); p.addLine(to: pt(0.93, 0.30)); p.addLine(to: pt(0.66, 0.52)) // 上 箭头→
        p.move(to: pt(0.94, 0.70)); p.addLine(to: pt(0.18, 0.70))      // 下 横线
        p.move(to: pt(0.34, 0.48)); p.addLine(to: pt(0.07, 0.70)); p.addLine(to: pt(0.34, 0.92)) // 下 箭头←
        return p
    }
}

enum DialogRole {
    case primary, normal, destructive, cancel
}

struct DialogButton: Identifiable {
    let id = UUID()
    let label: String
    let role: DialogRole
    let action: () -> Void
}

struct DialogModel: Identifiable {
    let id = UUID()
    let title: String
    var message: String? = nil
    var systemImage: String? = nil
    var iconTint: Color = Theme.accent1
    let buttons: [DialogButton]
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

                ZStack(alignment: .trailing) {
                    VStack(spacing: 0) {
                        ConversionPanel(store: store)
                        Divider()
                        ConversationListView(store: store)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if store.showsInspector {
                        HStack(spacing: 0) {
                            Divider()
                            InspectorPanel(store: store)
                                .frame(width: 340)
                        }
                        .background(Theme.card)
                        .shadow(color: .black.opacity(0.12), radius: 18, x: -4, y: 0)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.page)
        .overlay {
            if let label = store.operationLabel {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                        Text("处理中，请勿退出应用或打开 Codex")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.card)
                            .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: store.operationLabel)
        .overlay {
            if let dialog = store.dialog {
                DialogOverlay(store: store, model: dialog)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.14), value: store.dialog?.id)
    }

}

struct DialogOverlay: View {
    @ObservedObject var store: VaultStore
    let model: DialogModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { store.finishDialog(false) }

            VStack(spacing: 0) {
                VStack(spacing: 11) {
                    if let icon = model.systemImage {
                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(model.iconTint)
                    }
                    Text(model.title)
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                    if let message = model.message {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 20)

                Divider()

                if model.buttons.count > 2 {
                    VStack(spacing: 0) {
                        ForEach(Array(model.buttons.enumerated()), id: \.element.id) { index, button in
                            if index > 0 { Divider() }
                            DialogButtonView(button: button) { store.dialog = nil; button.action() }
                                .frame(height: 46)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(model.buttons.enumerated()), id: \.element.id) { index, button in
                            if index > 0 { Divider().frame(height: 46) }
                            DialogButtonView(button: button) { store.dialog = nil; button.action() }
                        }
                    }
                    .frame(height: 46)
                }
            }
            .frame(width: 324)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
        }
    }
}

struct DialogButtonView: View {
    let button: DialogButton
    let tap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: tap) {
            Text(button.label)
                .font(.system(size: 13.5, weight: button.role == .cancel ? .medium : .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var tint: Color {
        switch button.role {
        case .primary: return Theme.accent1
        case .destructive: return .red
        case .normal: return .primary
        case .cancel: return .secondary
        }
    }
}

struct HeaderView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        HStack(spacing: 14) {
            AppMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("Codex 对话管家")
                    .font(.system(size: 17, weight: .bold))
                Text("Codex 聊天记录转换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HeaderButton(title: "刷新列表", icon: "arrow.clockwise") {
                store.refresh()
            }
            HeaderButton(title: "检查记录", icon: "arrow.triangle.2.circlepath") {
                store.syncDeep()
            }
            HeaderButton(title: "选择目录", icon: "folder") {
                store.chooseCodexRoot()
            }
            HeaderButton(title: "备份", icon: "externaldrive") {
                store.requestBackup()
            }
            HeaderButton(title: "恢复", icon: "clock.arrow.circlepath") {
                store.requestRestore()
            }
            HeaderButton(title: "备份管理", icon: "archivebox") {
                store.manageBackups()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .background(Theme.card)
    }
}

struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.accentGradient)
                .shadow(color: Theme.accent1.opacity(0.45), radius: 8, y: 4)
            SwapArrows()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 23, height: 21)
        }
        .frame(width: 40, height: 40)
    }
}

struct HeaderButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .opacity(0.85)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(hovering ? Theme.hairline : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
                    selected: store.selectedProvider == nil && store.selectedSource == nil && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: nil)
                }

                FilterRow(
                    title: "API 会话",
                    icon: "network",
                    count: store.apiCount,
                    selected: store.selectedProvider == VaultStore.apiFilterID && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: VaultStore.apiFilterID)
                }

                FilterRow(
                    title: "官方会话",
                    icon: "checkmark.seal",
                    count: store.officialCount,
                    selected: store.selectedProvider == ProviderCategory.officialID && !store.showProblemsOnly
                ) {
                    store.setFilter(provider: ProviderCategory.officialID)
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
                    Text(store.result?.databaseAvailable == true ? "本机会话列表" : "等待数据")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
    }
}

struct FilterRow: View {
    let title: String
    let icon: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary))
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.accent1 : Color.primary.opacity(0.85))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent1 : Color.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? AnyShapeStyle(Theme.accentSoft) : AnyShapeStyle(hovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ConversionPanel: View {
    @ObservedObject var store: VaultStore

    var apiScope: MigrationScope {
        store.migrationScope(to: ProviderCategory.officialID)
    }

    var officialScope: MigrationScope {
        store.migrationScope(to: store.apiProviderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex 聊天记录转换")
                        .font(.system(size: 20, weight: .semibold))
                    Text(store.checkedCount > 0 ? "勾选后只转移选中的会话。" : "未勾选时默认转移当前列表里的全部可转移会话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(store.checkedCount > 0 ? "已勾选" : "默认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.checkedProviderSummary)
                        .font(.callout)
                        .fontWeight(.semibold)
                }
            }

            HStack(spacing: 10) {
                DirectionButton(
                    fromLabel: "API",
                    toLabel: "官方",
                    subtitle: scopeSubtitle(apiScope, emptyText: "没有可转换的 API 会话"),
                    prominent: store.selectedToOfficial == true,
                    disabled: apiScope.conversationIDs.isEmpty
                ) {
                    store.requestMigrate(toOfficial: true)
                }

                DirectionButton(
                    fromLabel: "官方",
                    toLabel: "API",
                    subtitle: scopeSubtitle(officialScope, emptyText: "没有可转换的官方会话"),
                    prominent: store.selectedToOfficial == false,
                    disabled: officialScope.conversationIDs.isEmpty
                ) {
                    store.requestMigrate(toOfficial: false)
                }

                if store.checkedCount > 0 {
                    VStack(spacing: 8) {
                        BatchButton(
                            title: "删除已勾选",
                            count: store.checkedCount,
                            disabled: false,
                            destructive: true
                        ) {
                            store.requestDeleteSelection()
                        }
                    }
                    .frame(width: 150)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
    }

    private func scopeSubtitle(_ scope: MigrationScope, emptyText: String) -> String {
        if scope.conversationIDs.isEmpty { return emptyText }
        return scope.usesSelection ? "转移已选 \(scope.conversationIDs.count) 条" : "全部 \(scope.conversationIDs.count) 条"
    }
}

struct DirectionButton: View {
    let fromLabel: String
    let toLabel: String
    let subtitle: String
    let prominent: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(fromLabel)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.9)
                    Text(toLabel)
                }
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(prominent ? Color.white.opacity(0.78) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background {
                if prominent {
                    Theme.accentGradient
                } else {
                    (hovering ? Theme.accent1.opacity(0.12) : Color.primary.opacity(0.05))
                }
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(prominent ? Color.clear : (hovering ? Theme.accent1.opacity(0.5) : Theme.hairline), lineWidth: prominent ? 0 : 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: prominent ? Theme.accent1.opacity(0.32) : Color.clear, radius: 12, y: 6)
            .scaleEffect(hovering && !disabled ? 1.012 : 1)
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 && !disabled }
        .animation(.easeOut(duration: 0.18), value: prominent)
        .animation(.easeOut(duration: 0.12), value: hovering)
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
                    LazyVStack(alignment: .leading, spacing: 13) {
                        ForEach(store.conversationGroups) { group in
                            ConversationGroupView(group: group, store: store)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .background(Theme.page)
            }
        }
        .background(Theme.page)
    }
}

struct ListHeaderView: View {
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、会话编号或项目", text: $store.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.card)
                        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )

                MetricView(title: "总数", value: "\(store.totalCount)")
                MetricView(title: "API", value: "\(store.apiCount)")
                MetricView(title: "官方", value: "\(store.officialCount)")
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.page)
    }
}

struct ConversationGroupView: View {
    let group: ConversationGroup
    @ObservedObject var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text(group.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text("\(group.conversations.count)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .help(group.path)

            Divider().opacity(0.6)

            VStack(spacing: 0) {
                ForEach(Array(group.conversations.enumerated()), id: \.element.id) { index, conversation in
                    if index > 0 {
                        Divider().opacity(0.45).padding(.leading, 46)
                    }
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
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.cardShadow, radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let selected: Bool
    let checked: Bool
    let toggleChecked: () -> Void
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                if checked {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.accentGradient)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1.6)
                }
            }
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { toggleChecked() }
            .help(checked ? "取消勾选" : "勾选会话")

            HStack(spacing: 9) {
                Text(conversation.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SourcePill(sourceKind: conversation.sourceKind)
                    .fixedSize()
                ProviderPill(provider: conversation.effectiveProvider)
                    .fixedSize()
                Text(RelativeTimeText.string(from: conversation.lastUpdatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 48, alignment: .trailing)
                StatusBadge(status: conversation.status)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { select() }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            selected
                ? AnyShapeStyle(LinearGradient(colors: [Theme.accent1.opacity(0.10), Theme.accent2.opacity(0.06)], startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(hovering ? Color.primary.opacity(0.035) : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}

struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 50)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.cardShadow, radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
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
                        HStack {
                            Text("会话详情")
                                .font(.system(size: 20, weight: .semibold))
                            Spacer()
                            Button {
                                store.closeInspector()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .help("关闭详情")
                        }
                        Text(conversation.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                        HStack {
                            StatusBadge(status: conversation.status)
                            SourcePill(sourceKind: conversation.sourceKind)
                            ProviderPill(provider: conversation.effectiveProvider)
                        }
                    }

                    DetailSection("基础信息") {
                        DetailRow("当前位置", ProviderText.detail(conversation.effectiveProvider))
                        DetailRow("使用方式", SourceText.name(conversation.sourceKind))
                        DetailRow("项目路径", conversation.projectPath ?? "未知")
                        DetailRow("更新时间", RelativeTimeText.string(from: conversation.lastUpdatedAt))
                    }

                    DetailSection("标识") {
                        DetailRow("会话编号", conversation.id, copyable: true)
                        DetailRow("归档状态", conversation.isArchived ? "已归档" : "未归档")
                    }

                    DetailSection("操作") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                copy(conversation.id)
                            } label: {
                                Label("复制会话编号", systemImage: "doc.on.doc")
                            }

                            Button {
                                store.requestDeleteConversation(conversation)
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
            .background(Theme.card)
        } else {
            ContentUnavailableView("未选择会话", systemImage: "sidebar.right", description: Text("从列表中选择一条会话。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

    private var isOfficial: Bool { provider == ProviderCategory.officialID }
    private var isApi: Bool {
        guard let provider, !provider.isEmpty else { return false }
        return provider != ProviderCategory.officialID
    }

    private var background: Color {
        if isOfficial { return .black.opacity(0.08) }
        if isApi { return .blue.opacity(0.12) }
        return .gray.opacity(0.15)
    }

    private var foreground: Color {
        if isOfficial { return .primary }
        if isApi { return .blue }
        return .secondary
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
        case ProviderCategory.officialID:
            return "官方"
        case .some(let provider) where !provider.isEmpty:
            return "API"
        default:
            return "未知"
        }
    }

    /// 详情里展示分类时带上真实 provider id，方便核对实际写入的是哪个第三方。
    static func detail(_ provider: String?) -> String {
        switch provider {
        case ProviderCategory.officialID:
            return "官方（openai）"
        case .some(let provider) where !provider.isEmpty:
            return "API（\(provider)）"
        default:
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
            return "记录不完整"
        case .missingSessionFile:
            return "缺少文件"
        case .unreadableSessionFile:
            return "无法读取"
        case .archived:
            return "已归档"
        }
    }
}
