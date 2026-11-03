import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(QuotaBarCore)
import QuotaBarCore
#endif

@main
struct AppServerHandshakeCheck {
    static func main() async throws {
        AppLocalization.language = .english
        if CommandLine.arguments.dropFirst().first == "app-server" {
            try runFakeServer()
            return
        }
        if CommandLine.arguments.dropFirst().first == "hold-stdout" {
            try holdOldStdout(home: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-handshake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer {
            cleanupHeldStdout(home: fixtureRoot.appendingPathComponent("exit-with-pending-read"))
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let client = CodexAppServerClient(executableURL: executable)
        // Old stdout callbacks must not disconnect a replacement process.
        for _ in 0..<5 {
            // Polling must reuse an initialized connection without another handshake.
            for _ in 0..<2 {
                checkPayload(try await client.readRateLimits())
                let before = try await client.readAccount()
                let usage = try await client.readAccountUsage()
                let after = try await client.readAccount()
                precondition(before == after && before?.email == "fixture@example.invalid")
                precondition(usage.summary.lifetimeTokens == 123_456)
                precondition(usage.days?.first?.day == "2026-10-20")
                precondition(usage.days?.first?.tokens == 42)
            }
            await client.stop()
        }
        try await checkPackagedDesktopLayouts(root: fixtureRoot, executable: executable)
        try await checkUsageReads(root: fixtureRoot, executable: executable)
        try await checkWebUsageReads(root: fixtureRoot, executable: executable)
        try await checkStopDuringLogin(root: fixtureRoot, executable: executable)

        for (scenario, expected) in [
            ("initialize-error", CodexClientError.server("Unsupported client capabilities")),
            ("invalid-initialize", CodexClientError.invalidResponse),
            ("exit-before-initialize", CodexClientError.disconnected)
        ] {
            let home = fixtureRoot.appendingPathComponent(scenario, isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let failedClient = CodexAppServerClient(
                codexHome: home,
                executableURL: executable
            )
            do {
                _ = try await failedClient.readRateLimits()
                preconditionFailure("Rejected initialization must fail: " + scenario)
            } catch let error as CodexClientError {
                precondition(error == expected, "Unexpected initialization error: \(error)")
            }
            if scenario == "exit-before-initialize" {
                var diagnostics = await failedClient.diagnosticSummary()
                for _ in 0..<20 {
                    if diagnostics.contains("Process exit status: 47") && diagnostics.contains("synthetic invalid model provider") { break }
                    try await Task.sleep(for: .milliseconds(50))
                    diagnostics = await failedClient.diagnosticSummary()
                }
                precondition(diagnostics.contains("Process exit status: 47"))
                precondition(diagnostics.contains("synthetic invalid model provider"))
            }
            await failedClient.stop()
        }
        try await checkRestartDuringInitialize(root: fixtureRoot, executable: executable)
        try await checkReplaceDeadProcess(root: fixtureRoot, executable: executable)
        print("App-server handshake, quota/analytics reads, unsupported analytics, pending-read cleanup and reconnect checks passed")
    }

    private static func checkPackagedDesktopLayouts(root: URL, executable: URL) async throws {
        for (appName, withLauncher) in [("Codex.app", true), ("ChatGPT.app", false)] {
            let app = root.appendingPathComponent("Packaged Desktop With Spaces/\(appName)", isDirectory: true)
            let nested = app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: executable, to: nested)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.path)
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "com.openai.codex"], format: .xml, options: 0
            )
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
            var expected = nested
            if withLauncher {
                let launcher = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
                try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
                let script = """
                #!/bin/sh
                set -eu
                bin_dir=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd)
                exec "$bin_dir/../CodexCLI.app/Contents/MacOS/codex" "$@"

                """
                try Data(script.utf8).write(to: launcher)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
                expected = launcher
            }
            guard CodexAppServerClient.locateExecutable(appBundleURLs: [app]) == expected else {
                // Never launch a real user's CODEX_PATH override during this fixture.
                throw FixtureError.unexpectedExecutable
            }
            let home = root.appendingPathComponent("packaged-profile-\(appName)", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let packagedClient = CodexAppServerClient(codexHome: home, appBundleURLs: [app])
            do {
                for _ in 0..<2 { checkPayload(try await packagedClient.readRateLimits()) }
                await packagedClient.stop()
            } catch {
                await packagedClient.stop()
                throw error
            }
        }
    }

    private static func checkUsageReads(root: URL, executable: URL) async throws {
        for (scenario, expected) in [
            ("usage-unsupported", AccountUsageError.unsupported),
            ("usage-invalid", AccountUsageError.invalidResponse)
        ] {
            let home = root.appendingPathComponent(scenario, isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let client = CodexAppServerClient(codexHome: home, executableURL: executable)
            do {
                _ = try await client.readAccountUsage()
                preconditionFailure("Analytics failure was ignored")
            } catch let error as AccountUsageError {
                precondition(error == expected)
            }
            // Older/failed analytics must leave ordinary quota polling usable.
            checkPayload(try await client.readRateLimits())
            await client.stop()
        }
        let home = root.appendingPathComponent("stop-during-usage", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let client = CodexAppServerClient(codexHome: home, executableURL: executable)
        let read = Task { try await client.readAccountUsage() }
        do {
            try await waitForMarker("usage-read-started", home: home)
            // A slow history response must not serialize or block quota reads.
            checkPayload(try await client.readRateLimits())
            await client.stop()
            do {
                _ = try await read.value
                throw FixtureError.oldReadSucceeded
            } catch let error as CodexClientError {
                precondition(error == .disconnected)
            }
            checkPayload(try await client.readRateLimits())
            await client.stop()
        } catch {
            read.cancel()
            await client.stop()
            throw error
        }
    }

    private static func checkStopDuringLogin(root: URL, executable: URL) async throws {
        let home = root.appendingPathComponent("stop-during-login", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let client = CodexAppServerClient(codexHome: home, executableURL: executable)
        let login = try await client.startChatGPTLogin()
        let wait = Task { try await client.waitForLogin(id: login.id) }
        // Stopping is also valid if the continuation has not registered yet.
        try await Task.sleep(for: .milliseconds(50))
        await client.stop()
        do {
            try await wait.value
            preconditionFailure("A stopped login must not complete successfully")
        } catch let error as CodexClientError {
            precondition(error == .disconnected)
        }
        do {
            try await client.waitForLogin(id: login.id)
            preconditionFailure("Registering a login wait after stop must fail immediately")
        } catch let error as CodexClientError {
            precondition(error == .disconnected)
        }
        checkPayload(try await client.readRateLimits())
        await client.stop()
    }

    private static func checkWebUsageReads(root: URL, executable: URL) async throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        for scenario in ["web-usage", "web-zero", "web-unauthorized", "web-missing-today", "web-invalid", "web-auth-unsupported"] {
            let home = root.appendingPathComponent(scenario, isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [HandshakeUsageProtocol.self]
            let client = CodexAppServerClient(codexHome: home, executableURL: executable,
                webUsageClient: ChatGPTUsageClient(session: URLSession(configuration: config)))
            let before = try await client.readAccount()
            let usage = try await client.readAccountUsageIncludingToday(now: now, calendar: AccountUsageDay.calendar)
            let after = try await client.readAccount()
            precondition(before == after)
            precondition(usage.summary.lifetimeTokens == 123_456)
            if scenario == "web-usage" || scenario == "web-zero" {
                precondition(usage.dailySource == .chatGPT)
                precondition(usage.days?.last?.tokens == (scenario == "web-zero" ? 0 : 321))
                precondition(usage.days?.first?.day == "2026-10-19" && usage.days?.first?.tokens == 123)
            } else {
                precondition(usage.dailySource == .codex)
                precondition(usage.days?.count == 1 && usage.days?.first?.tokens == 42)
            }
            checkPayload(try await client.readRateLimits())
            await client.stop()
        }
        let home = root.appendingPathComponent("web-stopped-auth", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let client = CodexAppServerClient(codexHome: home, executableURL: executable)
        let read = Task { try await client.readAccountUsageIncludingToday(now: now) }
        do {
            try await waitForMarker("usage-auth-started", home: home)
            checkPayload(try await client.readRateLimits())
            await client.stop()
            do { _ = try await read.value; preconditionFailure("Stopped analytics request returned old history") }
            catch let error as CodexClientError { precondition(error == .disconnected) }
            checkPayload(try await client.readRateLimits())
            await client.stop()
        } catch {
            read.cancel()
            await client.stop()
            throw error
        }
    }

    private static func checkRestartDuringInitialize(root: URL, executable: URL) async throws {
        let home = root.appendingPathComponent("restart-during-initialize", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let client = CodexAppServerClient(codexHome: home, executableURL: executable)
        let oldRead = Task { try await client.readRateLimits() }
        do {
            try await waitForMarker("initialize-started", home: home)
            await client.stop()
            let replacementRead = Task { try await client.readRateLimits() }
            try await expectDisconnected(oldRead)
            checkPayload(try await replacementRead.value)
            await client.stop()
        } catch {
            oldRead.cancel()
            await client.stop()
            throw error
        }
    }

    private static func checkReplaceDeadProcess(root: URL, executable: URL) async throws {
        let home = root.appendingPathComponent("exit-with-pending-read", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let client = CodexAppServerClient(codexHome: home, executableURL: executable)
        let oldRead = Task { try await client.readRateLimits() }
        do {
            try await waitForMarker("first-read-started", home: home)
            try mark("exit-now", home: home)
            let deadline = ContinuousClock.now + .seconds(5)
            while !(await client.diagnosticSummary()).contains("Process exit status: 48") {
                guard ContinuousClock.now < deadline else { throw FixtureError.timedOut("process exit") }
                try await Task.sleep(for: .milliseconds(10))
            }
            // The helper still holds old stdout open, so pending requests must be
            // completed by replacement cleanup rather than waiting for old EOF.
            let replacementRead = Task { try await client.readRateLimits() }
            try await expectDisconnected(oldRead)
            checkPayload(try await replacementRead.value)
            await client.stop()
            try mark("release-stdout", home: home)
            try await waitForMarker("stdout-released", home: home)
        } catch {
            oldRead.cancel()
            await client.stop()
            cleanupHeldStdout(home: home)
            throw error
        }
    }

    private static func expectDisconnected(_ task: Task<RateLimitPayload, Error>) async throws {
        let started = ContinuousClock.now
        do {
            _ = try await task.value
            throw FixtureError.oldReadSucceeded
        } catch let error as CodexClientError {
            guard started.duration(to: .now) < .seconds(2) else {
                throw FixtureError.timedOut("old request cleanup")
            }
            guard error == .disconnected else { throw error }
        }
    }

    private static func checkPayload(_ payload: RateLimitPayload) {
        precondition(payload.snapshot.limitID == "codex")
        precondition(payload.snapshot.secondary?.remainingPercent == 56)
    }

    private static func runFakeServer() throws {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
        let scenario = home?.lastPathComponent ?? "normal"
        var step = 0
        while let line = readLine() {
            let data = Data(line.utf8)
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = message["method"] as? String else { exit(20) }
            switch (step, method) {
            case (0, "initialize"):
                guard let id = message["id"] else { exit(21) }
                if scenario == "initialize-error" {
                    write(["id": id, "error": ["code": -32600, "message": "Unsupported client capabilities"]])
                    step = -1
                } else if scenario == "invalid-initialize" {
                    write(["id": id, "result": "invalid"])
                    step = -1
                } else if scenario == "exit-before-initialize" {
                    FileHandle.standardError.write(Data("configuration error: synthetic invalid model provider\n".utf8))
                    exit(47)
                } else if scenario == "restart-during-initialize", let home,
                          !hasMarker("initialize-started", home: home) {
                    try mark("initialize-started", home: home)
                    // stop() closes stdin; no response is sent by the first process.
                    while readLine() != nil { exit(23) }
                    return
                } else {
                    write(["id": id, "result": [:]])
                    step = 1
                }
            case (1, "initialized"):
                step = 2
            case (2, "account/login/start"):
                guard let id = message["id"] else { exit(22) }
                write(["id": id, "result": ["type": "chatgpt", "loginId": "fixture-login", "authUrl": "https://auth.openai.com/fixture-login"]])
            case (2, "account/read"):
                guard let id = message["id"] else { exit(22) }
                write(["id": id, "result": ["account": ["type": "chatgpt", "email": "fixture@example.invalid", "planType": "plus"]]])
            case (2, "account/usage/read"):
                guard let id = message["id"], let params = message["params"] as? [String: Any], params.isEmpty else { exit(22) }
                if scenario == "usage-unsupported" {
                    write(["id": id, "error": ["code": -32601, "message": "Method not found"]])
                } else if scenario == "usage-invalid" {
                    write(["id": id, "result": ["summary": NSNull()]])
                } else if scenario == "stop-during-usage", let home {
                    try mark("usage-read-started", home: home)
                } else {
                    write(["id": id, "result": [
                        "summary": ["lifetimeTokens": 123_456],
                        "dailyUsageBuckets": [["startDate": "2026-10-20", "tokens": 42]]
                    ]])
                }
            case (2, "getAuthStatus"):
                guard let id = message["id"], let params = message["params"] as? [String: Bool],
                      params == ["includeToken": true, "refreshToken": false] else { exit(22) }
                if scenario == "web-auth-unsupported" {
                    write(["id": id, "error": ["code": -32601, "message": "Method not found"]])
                } else if scenario == "web-stopped-auth", let home {
                    try mark("usage-auth-started", home: home)
                } else {
                    let claims = try JSONSerialization.data(withJSONObject: ["https://api.openai.com/auth": ["chatgpt_account_id": scenario]])
                        .base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                    write(["id": id, "result": ["authMethod": "chatgpt", "authToken": "fixture.\(claims).signature"]])
                }
            case (2, "account/rateLimits/read"):
                guard let id = message["id"] else { exit(22) }
                if scenario == "exit-with-pending-read", let home, !hasMarker("first-read-started", home: home) {
                    try mark("first-read-started", home: home)
                    try waitForMarkerBlocking("exit-now", home: home)
                    let holder = Process()
                    holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                    holder.arguments = ["hold-stdout", home.path]
                    holder.standardInput = FileHandle.nullDevice
                    holder.standardOutput = FileHandle.standardOutput
                    holder.standardError = FileHandle.nullDevice
                    try holder.run()
                    try Data(String(holder.processIdentifier).utf8).write(to: home.appendingPathComponent("holder-pid"))
                    try waitForMarkerBlocking("holding-stdout", home: home)
                    exit(48)
                }
                write([
                    "id": id,
                    "result": [
                        "rateLimitsByLimitId": [
                            "codex": [
                                "limitId": "codex",
                                "planType": "prolite",
                                "secondary": [
                                    "usedPercent": 44,
                                    "windowDurationMins": 10_080,
                                    "resetsAt": scenario == "expired-quota" ? 1 : 2_000_000_000
                                ]
                            ]
                        ]
                    ]
                ])
                // Remain ready for the next poll; a repeated handshake still fails.
                step = 2
            default:
                // A rejected initialize reply must never be followed by a
                // ready notification or a quota request.
                exit(23)
            }
        }
    }

    private enum FixtureError: Error {
        case timedOut(String)
        case oldReadSucceeded
        case unexpectedExecutable
    }

    private static func hasMarker(_ name: String, home: URL) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path)
    }

    private static func mark(_ name: String, home: URL) throws {
        try Data("fixture".utf8).write(to: home.appendingPathComponent(name))
    }

    private static func waitForMarker(_ name: String, home: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !hasMarker(name, home: home) {
            guard ContinuousClock.now < deadline else { throw FixtureError.timedOut(name) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func waitForMarkerBlocking(_ name: String, home: URL) throws {
        let deadline = Date().addingTimeInterval(5)
        while !hasMarker(name, home: home) {
            guard Date() < deadline else { throw FixtureError.timedOut(name) }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static func holdOldStdout(home: URL) throws {
        try mark("holding-stdout", home: home)
        // Even assertion failure in the parent cannot leave an unbounded helper.
        let deadline = Date().addingTimeInterval(10)
        while !hasMarker("release-stdout", home: home), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try mark("stdout-released", home: home)
    }

    private static func cleanupHeldStdout(home: URL) {
        guard !hasMarker("stdout-released", home: home),
              let text = try? String(contentsOf: home.appendingPathComponent("holder-pid"), encoding: .utf8),
              let pid = Int32(text), pid > 0 else { return }
        _ = kill(pid, SIGTERM)
        // A failure handler and the outer defer may both attempt cleanup.
        try? FileManager.default.removeItem(at: home.appendingPathComponent("holder-pid"))
    }

    private static func write(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

private final class HandshakeUsageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "ChatGPT-Account-Id")!
        precondition(request.url?.host == "chatgpt.com")
        precondition(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer fixture.") == true)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first(where: { $0.name == "end_date" })?.value == "2026-10-21")
        precondition(query.first(where: { $0.name == "workspace_user" })?.value == "true")
        let body: String
        switch scenario {
        case "web-invalid": body = #"{"data":[{"date":"2026-10-20","totals":{"text_total_tokens":-1}}]}"#
        case "web-missing-today": body = #"{"data":[{"date":"2026-10-19","totals":{"text_total_tokens":123}}]}"#
        default: body = "{\"data\":[{\"date\":\"2026-10-19\",\"totals\":{\"text_total_tokens\":123}},{\"date\":\"2026-10-20\",\"totals\":{\"text_total_tokens\":\(scenario == "web-zero" ? 0 : 321)}}]}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: scenario == "web-unauthorized" ? 401 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
