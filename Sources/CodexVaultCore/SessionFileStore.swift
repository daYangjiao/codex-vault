import Foundation

public struct SessionFileStore: Sendable {
    public init() {}

    public func updateProvider(records: [SessionRecord], targetProvider: String) throws {
        let recordsByFile = Dictionary(grouping: records, by: \.filePath)
        for (fileURL, records) in recordsByFile {
            try updateProvider(fileURL: fileURL, sessionIDs: Set(records.map(\.id)), targetProvider: targetProvider)
        }
    }

    private func updateProvider(fileURL: URL, sessionIDs: Set<String>, targetProvider: String) throws {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexVaultError.unreadableFile(fileURL)
        }

        var changed = false
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let updatedLines = try lines.map { line -> String in
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  var object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  var payload = object["payload"] as? [String: Any],
                  let id = payload["id"] as? String,
                  sessionIDs.contains(id) else {
                return line
            }

            payload["model_provider"] = targetProvider
            object["payload"] = payload
            let outputData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let output = String(data: outputData, encoding: .utf8) else {
                throw CodexVaultError.migrationFailed("Could not encode updated session metadata.")
            }
            changed = true
            return output
        }

        guard changed else {
            return
        }

        var output = updatedLines.joined(separator: "\n")
        if hadTrailingNewline && !output.hasSuffix("\n") {
            output.append("\n")
        }
        let temporaryURL = fileURL.appendingPathExtension("codex-vault-tmp")
        try output.data(using: .utf8)!.write(to: temporaryURL, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
    }
}
