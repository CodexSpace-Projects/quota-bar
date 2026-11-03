import Foundation
import QuotaBarCore

struct StatusOutput: Encodable {
    let schemaVersion = 1
    let fetchedAt: Date
    let planType: String?
    let tightestRemainingPercent: Int
    let windows: [Window]

    struct Window: Encodable {
        let name: String
        let durationMinutes: Int?
        let usedPercent: Int
        let remainingPercent: Int
        let resetsAt: Date?
    }
}

struct ModelEstimate: Encodable {
    let model: String
    let usage: TokenUsage
    let price: ModelPrice?
    let apiEquivalentEstimate: Double?
    let pricing: String
}

extension QuotaBarCLI {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

}
