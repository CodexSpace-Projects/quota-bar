import Foundation

@main
struct AccountProfileStorageCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("credential placeholder".utf8).write(to: root.appendingPathComponent("auth.json"))

        try AccountProfileStorage.removeLocalProfile(at: root)
        precondition(!FileManager.default.fileExists(atPath: root.path))
        try AccountProfileStorage.removeLocalProfile(at: root)
        print("Account profile deletion checks passed")
    }
}
