import Foundation

public struct ProcessGuard: Sendable {
    public init() {}

    public func runningCodexProcesses() -> [RunningProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                return nil
            }
            let pidText = String(trimmed[..<firstSpace]).trimmingCharacters(in: .whitespaces)
            let command = String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(pidText), isCodexProcess(command) else {
                return nil
            }
            return RunningProcess(id: pid, command: command)
        }
    }

    private func isCodexProcess(_ command: String) -> Bool {
        if command.contains("Codex Vault") || command.contains("CodexVault") {
            return false
        }
        return command.contains("/Applications/Codex.app") || command.contains("codex app-server")
    }
}
