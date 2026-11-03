import Foundation
import QuotaBarCore

extension QuotaBarCLI {
    static func status(_ arguments: [String]) async throws {
        let options = try parseOptions(arguments, booleanFlags: ["--json"], valuedFlags: ["--threshold"])
        let json = options.flags.contains("--json")
        let threshold = try intValue(options.values["--threshold"], flag: "--threshold", range: 0...100)

        let client = CodexAppServerClient()
        let payload = try await client.readRateLimits()
        await client.stop()
        guard !payload.snapshot.windows.isEmpty else { throw CLIError.noUsage }
        guard let tightest = payload.snapshot.currentMostConstrainedWindow()?.remainingPercent else { throw CLIError.resetPending }

        let output = StatusOutput(
            fetchedAt: payload.fetchedAt,
            planType: payload.snapshot.planType,
            tightestRemainingPercent: tightest,
            windows: payload.snapshot.windows.map {
                .init(name: $0.displayName, durationMinutes: $0.durationMinutes, usedPercent: $0.usedPercent, remainingPercent: $0.remainingPercent, resetsAt: $0.resetsAt)
            }
        )
        if json {
            print(try encode(output))
        } else {
            for window in output.windows {
                let reset = window.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                print("\(window.name): \(window.remainingPercent)% remaining; resets \(reset)")
            }
            print("tightest: \(tightest)% remaining")
        }
        if let threshold, tightest <= threshold { Foundation.exit(2) }
    }

}
