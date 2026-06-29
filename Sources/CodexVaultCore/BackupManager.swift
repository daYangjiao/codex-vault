import Foundation

public struct BackupManager: Sendable {
    public let backupsRoot: URL
    /// 自动保留的备份数量上限，超出的旧备份在每次新建备份后清理，避免占用过多磁盘。
    public let maxBackups: Int

    public init(backupsRoot: URL? = nil, maxBackups: Int = 10) {
        self.backupsRoot = backupsRoot ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Vault/Backups", isDirectory: true)
        self.maxBackups = max(1, maxBackups)
    }

    public func createBackup(root: URL, reason: String, conversationCount: Int) throws -> BackupRecord {
        let id = timestampID()
        let backupDirectory = backupsRoot.appendingPathComponent(id, isDirectory: true)
        let payloadRoot = backupDirectory.appendingPathComponent("codex-root", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
            try copyIfExists(root.appendingPathComponent("sessions", isDirectory: true), to: payloadRoot.appendingPathComponent("sessions", isDirectory: true))
            try copyIfExists(root.appendingPathComponent("archived_sessions", isDirectory: true), to: payloadRoot.appendingPathComponent("archived_sessions", isDirectory: true))
            for fileName in ["session_index.jsonl", "state_5.sqlite", "state_5.sqlite-wal", "state_5.sqlite-shm"] {
                try copyIfExists(root.appendingPathComponent(fileName), to: payloadRoot.appendingPathComponent(fileName))
            }

            let record = BackupRecord(
                id: id,
                createdAt: Date(),
                reason: reason,
                backupDirectory: backupDirectory,
                conversationCount: conversationCount
            )
            try writeManifest(record)
            pruneOldBackups()
            return record
        } catch {
            throw CodexVaultError.backupFailed(error.localizedDescription)
        }
    }

    /// 只保留最近 `maxBackups` 个备份，删除更旧的，避免备份目录无限增长。尽力而为，失败不影响主流程。
    public func pruneOldBackups() {
        let backups = listBackups() // 已按时间从新到旧排序
        guard backups.count > maxBackups else {
            return
        }
        for old in backups.dropFirst(maxBackups) {
            try? FileManager.default.removeItem(at: old.backupDirectory)
        }
    }

    public func listBackups() -> [BackupRecord] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backupsRoot,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries.compactMap(readManifest).sorted { $0.createdAt > $1.createdAt }
    }

    /// 所有备份占用的总字节数。
    public func totalSizeBytes() -> Int64 {
        listBackups().reduce(0) { $0 + directorySize($1.backupDirectory) }
    }

    /// 人类可读的总大小，如 "12.3 MB"。
    public func totalSizeText() -> String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes(), countStyle: .file)
    }

    /// 删除全部备份。
    public func deleteAllBackups() {
        for backup in listBackups() {
            try? FileManager.default.removeItem(at: backup.backupDirectory)
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    public func restore(_ backup: BackupRecord, to root: URL) throws {
        let payloadRoot = backup.backupDirectory.appendingPathComponent("codex-root", isDirectory: true)
        guard FileManager.default.fileExists(atPath: payloadRoot.path) else {
            throw CodexVaultError.backupFailed("Backup payload is missing.")
        }

        for item in ["sessions", "archived_sessions", "session_index.jsonl", "state_5.sqlite", "state_5.sqlite-wal", "state_5.sqlite-shm"] {
            let destination = root.appendingPathComponent(item)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try copyIfExists(payloadRoot.appendingPathComponent(item), to: destination)
        }
    }

    private func copyIfExists(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func writeManifest(_ record: BackupRecord) throws {
        let manifest: [String: Any] = [
            "id": record.id,
            "createdAt": ISO8601DateFormatter().string(from: record.createdAt),
            "reason": record.reason,
            "conversationCount": record.conversationCount
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: record.backupDirectory.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    private func readManifest(_ directory: URL) -> BackupRecord? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let createdAtString = object["createdAt"] as? String,
              let createdAt = DateParsing.parseISO8601(createdAtString),
              let reason = object["reason"] as? String,
              let count = object["conversationCount"] as? Int else {
            return nil
        }
        return BackupRecord(id: id, createdAt: createdAt, reason: reason, backupDirectory: directory, conversationCount: count)
    }

    private func timestampID() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
