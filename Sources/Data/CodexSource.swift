import Foundation

/// Reads Codex CLI usage from `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Unlike Claude Code, Codex writes the server-computed rate-limit percentages
/// straight into its `token_count` events (`rate_limits.primary` / `.secondary`).
/// When they are there we use them as-is — those are the real numbers, not an
/// estimate. When they are missing (API-key auth, older sessions) we fall back to
/// counting tokens the way we do for Claude.
actor CodexSource: UsageSource {

    nonisolated let providerID: Provider.ID = "codex"

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    /// Only the newest rollouts are read: the rate limits we want live in the
    /// most recent `token_count` event, so walking a month of history would be
    /// work with nothing to show for it.
    private let freshWindow: TimeInterval = 36 * 3600
    private let maxFiles = 4
    private let reader = JSONLTailReader()
    private var events: [TokenEvent] = []
    private var latestLimits: (date: Date, primary: RateLimit?, secondary: RateLimit?)?

    private let sessionFloor = 2_000_000
    private let weeklyFloor = 20_000_000

    struct RateLimit {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsInSeconds: Int?
    }

    func fetch(config: SourceConfig) async -> ProviderState {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return .unavailable("Codex CLI isn't installed")
        }

        ingestNewData()
        let now = Date()

        // Preferred path: the rate limits the server reported.
        if let limits = latestLimits, now.timeIntervalSince(limits.date) < 6 * 3600 {
            var windows: [UsageWindow] = []
            if let p = limits.primary {
                windows.append(window(id: "primary", label: "Current session",
                                      limit: p, observedAt: limits.date))
            }
            if let s = limits.secondary {
                windows.append(window(id: "secondary", label: "Weekly limit",
                                      limit: s, observedAt: limits.date))
            }
            if !windows.isEmpty {
                return .ready(UsageSnapshot(providerID: providerID, windows: windows, fetchedAt: now))
            }
        }

        // Fallback: estimate from tokens, as for Claude Code.
        guard config.allowLocalEstimate else {
            return .unavailable("No rate limits in the latest rollout")
        }
        guard !events.isEmpty else {
            return .unavailable("No recent sessions")
        }

        let completed = TokenLedger.completedBlockTotals(events: events, now: now)
        let block = TokenLedger.activeBlock(events: events, now: now)
        let sessionUsed = block.map { TokenLedger.sum(events, from: $0.start, to: $0.end) } ?? 0
        let sessionLimit = config.sessionLimitOverride
            ?? TokenLedger.calibratedLimit(from: completed, floor: sessionFloor)

        let week = TokenLedger.weeklyBounds(weekday: config.weeklyAnchorWeekday,
                                            hour: config.weeklyAnchorHour, now: now)
        let weeklyUsed = TokenLedger.sum(events, from: week.start, to: week.end)
        let weeklyLimit = config.weeklyLimitOverride ?? weeklyFloor

        return .ready(UsageSnapshot(providerID: providerID, windows: [
            UsageWindow(id: "session", label: "Current session",
                        usedFraction: Double(sessionUsed) / Double(sessionLimit),
                        resetsAt: block?.end,
                        usedTokens: sessionUsed, limitTokens: sessionLimit),
            UsageWindow(id: "weekly", label: "Weekly limit",
                        usedFraction: Double(weeklyUsed) / Double(weeklyLimit),
                        resetsAt: week.end,
                        usedTokens: weeklyUsed, limitTokens: weeklyLimit)
        ], fetchedAt: now))
    }

    private func window(id: String, label: String, limit: RateLimit, observedAt: Date) -> UsageWindow {
        // `resets_in_seconds` is relative to when the event was written, not to
        // now, so it has to be re-anchored or the countdown sits frozen.
        let resetsAt = limit.resetsInSeconds.map {
            observedAt.addingTimeInterval(TimeInterval($0))
        }
        return UsageWindow(id: id, label: label,
                           usedFraction: limit.usedPercent / 100.0,
                           resetsAt: resetsAt,
                           usedTokens: 0, limitTokens: 0)
    }

    // MARK: - Incremental reading

    private func ingestNewData() {
        let cutoff = Date().addingTimeInterval(-freshWindow)
        let recent = FileScan.jsonlFiles(under: root, modifiedAfter: cutoff).suffix(maxFiles)

        for file in recent {
            for line in reader.newLines(at: file) { ingest(line: line) }
        }

        let horizon = Date().addingTimeInterval(-freshWindow)
        events.removeAll { $0.date < horizon }
        events.sort { $0.date < $1.date }
    }

    private func ingest(line: Data) {
        guard line.contains(subsequence: Self.tokenMarker) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count"
        else { return }

        let date = (obj["timestamp"] as? String).flatMap(ISO8601.date(from:)) ?? Date()

        if let raw = payload["rate_limits"] as? [String: Any] {
            let primary = rateLimit(from: raw["primary"] as? [String: Any])
            let secondary = rateLimit(from: raw["secondary"] as? [String: Any])
            if primary != nil || secondary != nil,
               latestLimits.map({ date > $0.date }) ?? true {
                latestLimits = (date, primary, secondary)
            }
        }

        if let info = payload["info"] as? [String: Any],
           let last = info["last_token_usage"] as? [String: Any] {
            let cached = last["cached_input_tokens"] as? Int ?? 0
            let tokens = TokenWeight.weighted(
                input: max((last["input_tokens"] as? Int ?? 0) - cached, 0),
                cacheCreation: 0,
                cacheRead: cached,
                output: (last["output_tokens"] as? Int ?? 0)
                    + (last["reasoning_output_tokens"] as? Int ?? 0)
            )
            if tokens > 0 { events.append(TokenEvent(date: date, tokens: tokens)) }
        }
    }

    private func rateLimit(from dict: [String: Any]?) -> RateLimit? {
        guard let dict, let used = dict["used_percent"] as? Double else { return nil }
        return RateLimit(usedPercent: used,
                         windowMinutes: dict["window_minutes"] as? Int,
                         resetsInSeconds: dict["resets_in_seconds"] as? Int)
    }

    private static let tokenMarker = Array("token_count".utf8)
}
