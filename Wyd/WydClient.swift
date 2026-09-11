import Foundation

/// Schema version this client understands (mirrors `wyd barman` contract v1).
let wydRequiredSchemaVersion = 1

protocol WydClient: Sendable {
    func snapshot() async throws -> Snapshot
    func perform(target: String, action: ResourceAction) async throws -> ActionResult
    func cleanupPlan() async throws -> CleanupPlan
    func executeCleanup(planID: String, only: [String]?) async throws -> CleanupResult
    func apiVersion() async throws -> ApiVersion
}

/// `Process`-based client. No shell interpolation ever: executable URL +
/// argument vector only. Every invocation has a timeout; timeouts terminate
/// the child. JSON decoding happens off the main actor (callers await from
/// `@MainActor` state into these detached tasks).
struct ProcessWydClient: WydClient {
    private let locator = WydLocator()
    private let snapshotTimeout: TimeInterval = 8
    private let actionTimeout: TimeInterval = 30

    func snapshot() async throws -> Snapshot {
        let data = try await invoke(
            Self.args(["barman", "snapshot"], json: true),
            timeout: snapshotTimeout, what: "Snapshot")
        let probe: VersionProbe = try decode(data)
        guard probe.schemaVersion == wydRequiredSchemaVersion else {
            throw WydError.incompatible(wydVersion: probe.wydVersion)
        }
        return try decode(data)
    }

    func perform(target: String, action: ResourceAction) async throws -> ActionResult {
        let data = try await invoke(
            Self.args(
                ["barman", "action", "--target", target, "--action", action.engineName],
                json: true),
            timeout: actionTimeout,
            what: "Action",
            // Exit code 2 carries a structured stale-target body; decode it
            // instead of throwing a generic failure.
            decodeFailure: true
        )
        let result: ActionResult = try decode(data)
        guard result.ok else {
            if result.stale {
                throw WydError.staleTarget(target: target)
            }
            throw WydError.actionFailed(
                summary: "Action failed.",
                detail: result.error ?? result.detail)
        }
        return result
    }

    func cleanupPlan() async throws -> CleanupPlan {
        let data = try await invoke(
            Self.args(["barman", "cleanup-plan"], json: true),
            timeout: snapshotTimeout, what: "Cleanup plan")
        let probe: VersionProbe = try decode(data)
        guard probe.schemaVersion == wydRequiredSchemaVersion else {
            throw WydError.incompatible(wydVersion: probe.wydVersion)
        }
        return try decode(data)
    }

    func executeCleanup(planID: String, only: [String]?) async throws -> CleanupResult {
        var base = ["barman", "execute", "--plan", planID]
        if let only, !only.isEmpty {
            base += ["--only", only.joined(separator: ",")]
        }
        let data = try await invoke(
            Self.args(base, json: true), timeout: actionTimeout, what: "Cleanup")
        let result: CleanupResult = try decode(data)
        guard result.ok else {
            throw WydError.actionFailed(
                summary: "Cleanup had failures.",
                detail: result.failed.map(\.error).joined(separator: "\n"))
        }
        return result
    }

    /// Demo mode (UserDefaults): routes every call through the engine's
    /// deterministic synthetic dataset — nothing on the host is touched.
    static func args(_ base: [String], json: Bool) -> [String] {
        var args = base
        if UserDefaults.standard.bool(forKey: "demoMode") {
            args.append("--demo")
        }
        if json {
            args.append("--json")
        }
        return args
    }


    func apiVersion() async throws -> ApiVersion {
        let data = try await invoke(
            ["barman", "version", "--json"], timeout: snapshotTimeout, what: "Version check")
        let version: ApiVersion = try decode(data)
        guard version.schemaVersion == wydRequiredSchemaVersion else {
            throw WydError.incompatible(wydVersion: version.wydVersion)
        }
        return version
    }

    // MARK: - Plumbing

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            throw WydError.decodeFailed(detail: "\(error.localizedDescription): \(preview)")
        }
    }

    private func invoke(
        _ arguments: [String], timeout: TimeInterval, what: String, decodeFailure: Bool = false
    ) async throws -> Data {
        let binary = try locator.resolve()
        let output: ProcessOutput = try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw WydError.actionFailed(
                    summary: "\(what) could not start.", detail: error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                throw WydError.timeout(what: what)
            }
            return ProcessOutput(
                stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                stderr: String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
                exitCode: process.terminationStatus
            )
        }.value
        guard output.exitCode == 0 || (decodeFailure && !output.stdout.isEmpty) else {
            throw WydError.actionFailed(
                summary: "\(what) failed.",
                detail: Self.detail(exitCode: output.exitCode, stderr: output.stderr))
        }
        return output.stdout
    }

    private static func detail(exitCode: Int32, stderr: String?) -> String {
        let err = (stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty {
            return "wyd returned exit code \(exitCode)."
        }
        return "wyd returned exit code \(exitCode): \(err)"
    }
}

private struct ProcessOutput {
    let stdout: Data
    let stderr: String?
    let exitCode: Int32
}
