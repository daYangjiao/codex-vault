import Foundation

public struct CodexRootLocator: Sendable {
    public init() {}

    public func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    public func validate(root: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexVaultError.missingCodexRoot(root)
        }
    }
}
