import Foundation
import QuotaBarCore

@main
struct QuotaBarCLI {
    static func main() async {
        // Keep CLI labels and JSON window names stable for automation.
        AppLocalization.language = .english
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--help") || arguments.contains("-h") {
                printHelp()
                Foundation.exit(0)
            }
            if arguments.first == "history" {
                try await history(Array(arguments.dropFirst()))
            } else {
                try await status(arguments.first == "status" ? Array(arguments.dropFirst()) : arguments)
            }
        } catch {
            FileHandle.standardError.write(Data("quota-bar: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func printHelp() {
        print("""
        quota-bar — local Codex usage for scripts and alerts

        Usage:
          quota-bar status [--json] [--threshold 0...100]
          quota-bar history [--json] [--days 1...90]
                              [--currency USD|AUD|EUR] [--exchange-rate N]
                              [--input-rate N] [--cached-input-rate N] [--output-rate N]

        Exit codes: 0 success, 1 operational/argument error, 2 at or below threshold.
        Known models use bundled official standard API prices. USD is the default; AUD and EUR use dated ECB reference rates.
        --exchange-rate overrides USD-to-selected-currency conversion. Rate flags are fallbacks for unknown models.
        Estimates are API-equivalent and are not ChatGPT subscription spend.
        """)
    }
}
