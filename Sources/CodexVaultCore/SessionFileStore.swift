import Foundation

public struct SessionFileStore: Sendable {
    public init() {}

    public func updateProvider(records: [SessionRecord], targetProvider: String) throws {
        let recordsByFile = Dictionary(grouping: records, by: \.filePath)
        for (fileURL, records) in recordsByFile {
            try updateProvider(fileURL: fileURL, sessionIDs: Set(records.map(\.id)), targetProvider: targetProvider)
        }
    }

    @discardableResult
    public func deleteSessionFiles(records: [SessionRecord]) throws -> Int {
        var deleted = 0
        let uniqueFileURLs = Set(records.map(\.filePath))
        for fileURL in uniqueFileURLs where FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            deleted += 1
        }
        return deleted
    }

    private func updateProvider(fileURL: URL, sessionIDs: Set<String>, targetProvider: String) throws {
        var changed = false
        let temporaryURL = fileURL.appendingPathExtension("codex-vault-tmp")

        guard let input = try? FileHandle(forReadingFrom: fileURL) else {
            throw CodexVaultError.unreadableFile(fileURL)
        }
        defer { try? input.close() }

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: temporaryURL) else {
            throw CodexVaultError.migrationFailed("Could not create temporary session file.")
        }
        defer { try? output.close() }

        do {
            while let line = try readLineWithTerminator(from: input) {
                let updated = try updatedSessionMetaLine(
                    line,
                    sessionIDs: sessionIDs,
                    targetProvider: targetProvider
                )
                if updated.didChange {
                    changed = true
                }
                try output.write(contentsOf: updated.data)
            }

            guard changed else {
                try? FileManager.default.removeItem(at: temporaryURL)
                return
            }

            try output.close()
            try input.close()
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func readLineWithTerminator(from handle: FileHandle) throws -> Data? {
        var buffer = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newlineIndex = chunk.firstIndex(of: 10) {
                buffer.append(chunk[...newlineIndex])
                let unreadCount = chunk.count - newlineIndex - 1
                if unreadCount > 0 {
                    try handle.seek(toOffset: handle.offsetInFile - UInt64(unreadCount))
                }
                return buffer
            }
            buffer.append(chunk)
        }
        return buffer.isEmpty ? nil : buffer
    }

    private func updatedSessionMetaLine(
        _ line: Data,
        sessionIDs: Set<String>,
        targetProvider: String
    ) throws -> (data: Data, didChange: Bool) {
        let lineEnding: Data
        let jsonData: Data
        if line.last == 10 {
            lineEnding = Data([10])
            jsonData = line.dropLast()
        } else {
            lineEnding = Data()
            jsonData = line
        }
        guard !jsonData.isEmpty,
              var object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              object["type"] as? String == "session_meta",
              var payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              sessionIDs.contains(id) else {
            return (line, false)
        }

        payload["model_provider"] = targetProvider
        object["payload"] = payload
        var outputData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        outputData.append(lineEnding)
        return (outputData, true)
    }
}

public struct SessionIndexStore: Sendable {
    public init() {}

    @discardableResult
    public func deleteEntries(indexURL: URL, conversationIDs: Set<String>) throws -> Int {
        guard !conversationIDs.isEmpty,
              FileManager.default.fileExists(atPath: indexURL.path) else {
            return 0
        }

        var deleted = 0
        let temporaryURL = indexURL.appendingPathExtension("codex-vault-tmp")
        guard let input = try? FileHandle(forReadingFrom: indexURL) else {
            throw CodexVaultError.unreadableFile(indexURL)
        }
        defer { try? input.close() }

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: temporaryURL) else {
            throw CodexVaultError.migrationFailed("Could not create temporary session index.")
        }
        defer { try? output.close() }

        do {
            while let line = try readLineWithTerminator(from: input) {
                if shouldDeleteIndexLine(line, conversationIDs: conversationIDs) {
                    deleted += 1
                } else {
                    try output.write(contentsOf: line)
                }
            }

            try output.close()
            try input.close()
            _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temporaryURL)
            return deleted
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func readLineWithTerminator(from handle: FileHandle) throws -> Data? {
        var buffer = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newlineIndex = chunk.firstIndex(of: 10) {
                buffer.append(chunk[...newlineIndex])
                let unreadCount = chunk.count - newlineIndex - 1
                if unreadCount > 0 {
                    try handle.seek(toOffset: handle.offsetInFile - UInt64(unreadCount))
                }
                return buffer
            }
            buffer.append(chunk)
        }
        return buffer.isEmpty ? nil : buffer
    }

    private func shouldDeleteIndexLine(_ line: Data, conversationIDs: Set<String>) -> Bool {
        let jsonData = line.last == 10 ? line.dropLast() : line[...]
        guard !jsonData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any],
              let id = object["id"] as? String else {
            return false
        }
        return conversationIDs.contains(id)
    }
}
