import Foundation

public struct SessionScanner: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func scan(root: URL) throws -> [SessionRecord] {
        var records: [SessionRecord] = []
        for directoryName in ["sessions", "archived_sessions"] {
            let directory = root.appendingPathComponent(directoryName, isDirectory: true)
            let isArchived = directoryName == "archived_sessions"
            records.append(contentsOf: try scanDirectory(directory, isArchived: isArchived))
        }
        return records.sorted {
            ($0.lastUpdatedAt ?? .distantPast, $0.id) > ($1.lastUpdatedAt ?? .distantPast, $1.id)
        }
    }

    private func scanDirectory(_ directory: URL, isArchived: Bool) throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [SessionRecord] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            if let record = try parseSessionFile(fileURL, isArchived: isArchived) {
                records.append(record)
            }
        }
        return records
    }

    private func parseSessionFile(_ fileURL: URL, isArchived: Bool) throws -> SessionRecord? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw CodexVaultError.unreadableFile(fileURL)
        }
        defer { try? handle.close() }

        var meta: SessionMetaPayload?
        var firstUserMessage: String?
        var newestTimestamp: Date?
        var lineCount = 0

        while let line = try readLine(from: handle), lineCount < 200 {
            lineCount += 1
            consumeLine(
                line,
                meta: &meta,
                firstUserMessage: &firstUserMessage,
                newestTimestamp: &newestTimestamp
            )
            if meta != nil, firstUserMessage != nil {
                break
            }
        }

        guard let meta else {
            return nil
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let fallbackDate = resourceValues?.contentModificationDate

        return SessionRecord(
            id: meta.id,
            provider: meta.modelProvider,
            projectPath: meta.cwd,
            source: meta.source,
            title: firstUserMessage ?? fileURL.deletingPathExtension().lastPathComponent,
            filePath: fileURL,
            lastUpdatedAt: newestTimestamp ?? fallbackDate ?? meta.timestampDate,
            isArchived: isArchived
        )
    }

    private func readLine(from handle: FileHandle) throws -> Data? {
        var buffer = Data()
        while let data = try handle.read(upToCount: 4096), !data.isEmpty {
            if let newlineIndex = data.firstIndex(of: 10) {
                buffer.append(data[..<newlineIndex])
                let offset = UInt64(data.count - newlineIndex - 1)
                if offset > 0 {
                    try handle.seek(toOffset: handle.offsetInFile - offset)
                }
                return buffer
            }
            buffer.append(data)
            if buffer.count > 2_000_000 {
                return buffer
            }
        }
        return buffer.isEmpty ? nil : buffer
    }

    private func consumeLine(
        _ data: Data,
        meta: inout SessionMetaPayload?,
        firstUserMessage: inout String?,
        newestTimestamp: inout Date?
    ) {
        guard !data.isEmpty else {
            return
        }

        guard let event = try? decoder.decode(SessionEvent.self, from: data) else {
            return
        }

        if let timestamp = event.timestampDate {
            newestTimestamp = max(newestTimestamp ?? timestamp, timestamp)
        }

        if event.type == "session_meta", meta == nil {
            meta = event.payload.sessionMeta
        }

        if firstUserMessage == nil,
           event.type == "response_item",
           event.payload.role == "user" {
            firstUserMessage = event.payload.firstInputText
        }
    }
}

private struct SessionEvent: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload

    var timestampDate: Date? {
        timestamp.flatMap(DateParsing.parseISO8601)
    }
}

private struct Payload: Decodable {
    let id: String?
    let timestamp: String?
    let cwd: String?
    let source: String?
    let modelProvider: String?
    let type: String?
    let role: String?
    let content: [ContentItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case cwd
        case source
        case modelProvider = "model_provider"
        case type
        case role
        case content
    }

    var sessionMeta: SessionMetaPayload? {
        guard let id else {
            return nil
        }
        return SessionMetaPayload(id: id, timestamp: timestamp, cwd: cwd, source: source, modelProvider: modelProvider)
    }

    var firstInputText: String? {
        content?.first { $0.type == "input_text" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.text
    }
}

private struct ContentItem: Decodable {
    let type: String
    let text: String
}

private struct SessionMetaPayload {
    let id: String
    let timestamp: String?
    let cwd: String?
    let source: String?
    let modelProvider: String?

    var timestampDate: Date? {
        timestamp.flatMap(DateParsing.parseISO8601)
    }
}
