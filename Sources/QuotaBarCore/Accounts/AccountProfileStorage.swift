import Foundation

public enum AccountProfileStorage {
    public static func removeLocalProfile(at url: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
