import Foundation
#if canImport(QuotaBarCore)
import QuotaBarCore
#endif

@main
struct LiveCheck {
    static func main() async throws {
        let client = CodexAppServerClient()
        let payload = try await client.readRateLimits()
        guard !payload.snapshot.windows.isEmpty,
              payload.snapshot.mostConstrainedRemaining != nil else {
            throw CodexClientError.invalidResponse
        }
        guard try await client.readAccount() != nil else {
            throw CodexClientError.invalidResponse
        }
        await client.stop()
        print("Live Codex account and rate-limit checks passed")
    }
}
