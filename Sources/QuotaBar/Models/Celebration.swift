import Foundation
import QuotaBarCore

struct Celebration: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}
