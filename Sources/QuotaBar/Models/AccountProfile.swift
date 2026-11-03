import Foundation
import QuotaBarCore

struct AccountProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let homePath: String?
    var email: String?

    var homeURL: URL? { homePath.map(URL.init(fileURLWithPath:)) }
    var displayName: String { email ?? (homePath == nil ? AppLocalization.text("Default") : name) }
}
