import Foundation

/// A generic provider: runs a shell command and reads its stdout as JSON. This is
/// the hook that turns adding a provider into configuration rather than code.
///
/// Expected contract on stdout:
/// ```json
/// { "windows": [
///     { "label": "Current session", "used": 0.73, "resets_in_seconds": 3060 },
///     { "label": "All models", "used_percent": 7, "resets_at": "2026-08-29T00:00:00Z" }
/// ] }
/// ```
actor ScriptSource: UsageSource {

    nonisolated let providerID: Provider.ID
    private let hint: String

    init(providerID: Provider.ID, hint: String) {
        self.providerID = providerID
        self.hint = hint
    }

    func fetch(config: SourceConfig) async -> ProviderState {
        guard let command = config.scriptCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            return .unavailable(hint)
        }

        do {
            let output = try run(command)
            guard let obj = try JSONSerialization.jsonObject(with: output) as? [String: Any],
                  let raw = obj["windows"] as? [[String: Any]], !raw.isEmpty
            else { return .failed("Invalid output: missing \"windows\"") }

            let now = Date()
            let windows = raw.enumerated().compactMap { index, item -> UsageWindow? in
                let fraction: Double
                if let used = item["used"] as? Double { fraction = used }
                else if let pct = item["used_percent"] as? Double { fraction = pct / 100 }
                else { return nil }

                var resetsAt: Date?
                if let seconds = item["resets_in_seconds"] as? Double {
                    resetsAt = now.addingTimeInterval(seconds)
                } else if let stamp = item["resets_at"] as? String {
                    resetsAt = ISO8601.date(from: stamp)
                }

                return UsageWindow(
                    id: item["id"] as? String ?? "w\(index)",
                    label: item["label"] as? String ?? "Usage",
                    usedFraction: fraction,
                    resetsAt: resetsAt,
                    usedTokens: item["used_tokens"] as? Int ?? 0,
                    limitTokens: item["limit_tokens"] as? Int ?? 0
                )
            }

            guard !windows.isEmpty else { return .failed("No readable window") }
            return .ready(UsageSnapshot(providerID: providerID, windows: windows, fetchedAt: now))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func run(_ command: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        // A provider that hangs must not stall the refresh of the others.
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw NSError(domain: "Quota", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Command timed out (10s)"])
        }
        return (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
    }
}
