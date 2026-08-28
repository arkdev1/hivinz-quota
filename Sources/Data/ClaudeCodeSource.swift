import Foundation

/// Reads real Claude Code usage from the transcripts under `~/.claude/projects`.
/// Every `assistant` line carries a `message.usage`; from it we take the weighted
/// token count and the timestamp, then fold both into the 5-hour and weekly windows.
actor ClaudeCodeSource: UsageSource {

    nonisolated let providerID: Provider.ID = "claude"

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    /// Beyond this horizon the data only feeds calibration, not the live windows.
    private let retention: TimeInterval = 30 * 86400

    private let reader = JSONLTailReader()
    private var events: [TokenEvent] = []
    private var seen: Set<String> = []
    private var didFullScan = false

    private let sessionFloor = 2_000_000
    private let weeklyFloor = 20_000_000

    func fetch(config: SourceConfig) async -> ProviderState {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return .unavailable("Claude Code isn't installed")
        }

        ingestNewData()

        guard !events.isEmpty else {
            return .unavailable("No activity in the last 30 days")
        }

        let now = Date()
        let completed = TokenLedger.completedBlockTotals(events: events, now: now)

        // Session: the active 5-hour block.
        let block = TokenLedger.activeBlock(events: events, now: now)
        let sessionUsed = block.map { TokenLedger.sum(events, from: $0.start, to: $0.end) } ?? 0
        let sessionLimit = config.sessionLimitOverride
            ?? TokenLedger.calibratedLimit(from: completed, floor: sessionFloor)

        // Week: from the current anchor to the next.
        let week = TokenLedger.weeklyBounds(weekday: config.weeklyAnchorWeekday,
                                            hour: config.weeklyAnchorHour, now: now)
        let weeklyUsed = TokenLedger.sum(events, from: week.start, to: week.end)
        let weeklyLimit = config.weeklyLimitOverride
            ?? TokenLedger.calibratedLimit(from: [weeklyPeak(now: now)], floor: weeklyFloor)

        let windows = [
            UsageWindow(id: "session", label: "Current session",
                        usedFraction: Double(sessionUsed) / Double(sessionLimit),
                        resetsAt: block?.end,
                        usedTokens: sessionUsed, limitTokens: sessionLimit),
            UsageWindow(id: "weekly", label: "All models",
                        usedFraction: Double(weeklyUsed) / Double(weeklyLimit),
                        resetsAt: week.end,
                        usedTokens: weeklyUsed, limitTokens: weeklyLimit)
        ]

        return .ready(UsageSnapshot(providerID: providerID, windows: windows, fetchedAt: now))
    }

    // MARK: - Incremental reading

    private func ingestNewData() {
        let cutoff = didFullScan ? Date().addingTimeInterval(-2 * 3600)
                                 : Date().addingTimeInterval(-retention)
        didFullScan = true

        for file in FileScan.jsonlFiles(under: root, modifiedAfter: cutoff) {
            for line in reader.newLines(at: file) {
                if let event = parse(line: line) { events.append(event) }
            }
        }

        let horizon = Date().addingTimeInterval(-retention)
        events.removeAll { $0.date < horizon }
        events.sort { $0.date < $1.date }
    }

    /// Pre-filtering on raw bytes avoids decoding JSON for the `user` and
    /// `attachment` lines, which are the bulk of every transcript.
    private func parse(line: Data) -> TokenEvent? {
        guard line.count > 40, line.contains(subsequence: Self.usageMarker) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let date = ISO8601.date(from: stamp)
        else { return nil }

        // Claude Code rewrites the same message into several transcripts when a
        // session is resumed or forked; without dedup the tokens count twice.
        let key = (message["id"] as? String) ?? (obj["requestId"] as? String) ?? UUID().uuidString
        guard seen.insert(key).inserted else { return nil }

        let tokens = TokenWeight.weighted(
            input: usage["input_tokens"] as? Int ?? 0,
            cacheCreation: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0
        )
        guard tokens > 0 else { return nil }
        return TokenEvent(date: date, tokens: tokens)
    }

    /// Historical weekly peak, used to calibrate the long window's ceiling.
    private func weeklyPeak(now: Date) -> Int {
        guard let first = events.first?.date else { return 0 }
        var peak = 0
        var cursor = first
        while cursor < now {
            let next = cursor.addingTimeInterval(7 * 86400)
            peak = max(peak, TokenLedger.sum(events, from: cursor, to: next))
            cursor = next
        }
        return peak
    }

    private static let usageMarker = Array("\"usage\"".utf8)
}

extension Data {
    /// Substring search over raw bytes, without building a String.
    func contains(subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        return withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            let limit = count - needle.count
            var i = 0
            while i <= limit {
                if base[i] == needle[0] {
                    var j = 1
                    while j < needle.count, base[i + j] == needle[j] { j += 1 }
                    if j == needle.count { return true }
                }
                i += 1
            }
            return false
        }
    }
}
