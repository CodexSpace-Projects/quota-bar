import Foundation
import QuotaBarCore

struct ParsedOptions {
    let flags: Set<String>
    let values: [String: String]
}

extension QuotaBarCLI {
    static func intValue(_ raw: String?, flag: String, range: ClosedRange<Int>) throws -> Int? {
        guard let raw else { return nil }
        guard let value = Int(raw), range.contains(value) else {
            throw CLIError.argument("\(flag) requires a value from \(range.lowerBound) to \(range.upperBound).")
        }
        return value
    }

    static func doubleValue(_ raw: String?, flag: String) throws -> Double? {
        guard let raw else { return nil }
        guard let value = Double(raw), value.isFinite, value >= 0 else {
            throw CLIError.argument("\(flag) requires a non-negative number.")
        }
        return value
    }

    static func currencyValue(_ raw: String?) throws -> DisplayCurrency {
        guard let raw else { return .usd }
        guard let currency = DisplayCurrency(rawValue: raw.uppercased()) else {
            throw CLIError.argument("--currency requires USD, AUD, or EUR.")
        }
        return currency
    }

    static func formattedCurrency(_ amount: Double, currency: DisplayCurrency) -> String {
        "\(currency.symbol)\(amount.formatted(.number.precision(.fractionLength(4))))"
    }

    static func parseOptions(_ arguments: [String], booleanFlags: Set<String>, valuedFlags: Set<String>) throws -> ParsedOptions {
        var flags = Set<String>()
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if booleanFlags.contains(argument) {
                guard flags.insert(argument).inserted else { throw CLIError.argument("Duplicate argument: \(argument)") }
                index += 1
                continue
            }
            if valuedFlags.contains(argument) {
                guard values[argument] == nil else { throw CLIError.argument("Duplicate argument: \(argument)") }
                guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.argument("\(argument) requires a value.")
                }
                values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            throw CLIError.argument("Unknown argument: \(argument)")
        }
        return ParsedOptions(flags: flags, values: values)
    }

}
