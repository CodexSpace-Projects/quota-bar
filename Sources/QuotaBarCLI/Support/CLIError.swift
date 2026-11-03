import Foundation

enum CLIError: LocalizedError {
    case argument(String)
    case noUsage
    case resetPending

    var errorDescription: String? {
        switch self {
        case .argument(let message): return message
        case .noUsage: return "Codex returned no rate-limit windows."
        case .resetPending: return "The scheduled reset has passed; awaiting updated quota from Codex."
        }
    }
}

