import Foundation

/// Locates the `wyd` engine binary. The client never shells out for
/// discovery; this only resolves a path, in strict order.
struct WydLocator: Sendable {
    static let overrideKey = "wydBinaryPath"
    static let installURL = URL(string: "https://wyd.sh")!

    func resolve() throws -> URL {
        // 1. Explicit user override from Settings.
        if let custom = UserDefaults.standard.string(forKey: Self.overrideKey),
            !custom.trimmingCharacters(in: .whitespaces).isEmpty
        {
            let url = URL(fileURLWithPath: custom)
            if isExecutable(url) { return url }
            throw WydError.notFound
        }
        // 2. Well-known install locations.
        var candidates = [
            "/opt/homebrew/bin/wyd",
            "/usr/local/bin/wyd",
        ]
        if let home = homeDirectory {
            candidates.append(home.appendingPathComponent(".local/bin/wyd").path)
        }
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if isExecutable(url) { return url }
        }
        // 3. Login-shell PATH (GUI apps lack the interactive PATH).
        // Fixed command, no interpolation of user input.
        if let found = lookupViaLoginShell(), !found.isEmpty {
            let url = URL(fileURLWithPath: found)
            if isExecutable(url) { return url }
        }
        throw WydError.notFound
    }
    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private var homeDirectory: URL? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        return URL(fileURLWithPath: home)
    }

    private func lookupViaLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v wyd"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        // Wait for real exit so the pipe is closed — then the blocking read
        // cannot hang (readDataToEndOfFile waits for EOF).
        process.waitUntilExit()
        guard
            let raw = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }
        let out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }
}
