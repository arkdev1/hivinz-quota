import Foundation
import Security

/// Asks Anthropic for the real numbers instead of estimating them.
///
/// Claude Code signs in with OAuth and parks the result in the login keychain as
/// a generic password under `Claude Code-credentials`. With that access token the
/// same usage endpoint `/usage` reads is one HTTPS call away — no backend, no
/// scanning, and the percentages match what the CLI reports exactly.
///
/// Two things worth knowing. The first read pops a macOS keychain prompt, because
/// this is a different binary than the one that stored the item; allowing it once
/// is enough. And the endpoint is not part of Anthropic's published API, so it
/// can change without notice — which is why `ClaudeUsageSource` keeps a local
/// fallback behind a preference.
actor AnthropicOAuthSource {

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
    }

    enum Failure: LocalizedError {
        case noCredentials
        case expired
        case http(Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .noCredentials: return "Sign in with Claude Code first"
            case .expired: return "Claude Code session expired — run /login"
            case .http(429): return "Rate limited — will retry shortly"
            case .http(let code): return "Usage endpoint returned \(code)"
            case .malformed: return "Unexpected response from the usage endpoint"
            }
        }
    }

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // MARK: - Politeness
    //
    // The UI refresh timer can tick every 20 seconds, but this endpoint must not
    // be hit that often — it rate-limits, and a usage widget that earns 429s is
    // spending the very quota it is supposed to watch. So the source keeps its
    // own cadence: a successful reading is served from cache for a minute, a 429
    // honours Retry-After (with a floor when the header is missing), and while
    // rate-limited the last good reading keeps being served. The windows carry
    // absolute reset dates, so a cached reading still counts down correctly.

    private let minInterval: TimeInterval = 60
    private let defaultCooldown: TimeInterval = 5 * 60
    /// How long the last good reading may stand in for a failing fetch. The
    /// reset dates are absolute, so a stale reading still counts down — it just
    /// slowly under-reports usage, which beats nagging about logins.
    private let staleGrace: TimeInterval = 3 * 3600
    private lazy var lastGood: (windows: [UsageWindow], at: Date)? = Self.loadCache()
    private var retryAfter: Date = .distantPast
    /// Keychain reads are the expensive part — each one can pop a permission
    /// prompt, and Claude Code rewrites the item when it rotates the token,
    /// which resets any one-off approval. So credentials are read once and held
    /// until they expire or the server rejects them.
    private var cachedCredentials: Credentials?

    func fetchWindows(force: Bool = false) async throws -> [UsageWindow] {
        let now = Date()
        if let cached = lastGood,
           now < retryAfter || (!force && now.timeIntervalSince(cached.at) < minInterval) {
            return cached.windows
        }
        guard now >= retryAfter else { throw Failure.http(429) }

        do {
            return try await refresh(now: now)
        } catch {
            // A failing fetch — expired token, missing credentials, network —
            // does not blank a reading that was fine minutes ago. Serve the
            // cached one through the grace window and surface the error only
            // once there is truly nothing to show.
            if let cached = lastGood, now.timeIntervalSince(cached.at) < staleGrace {
                return cached.windows
            }
            throw error
        }
    }

    private func refresh(now: Date) async throws -> [UsageWindow] {
        let credentials = try currentCredentials()

        var (data, http) = try await call(token: credentials.accessToken)
        if http.statusCode == 401 {
            // Claude Code rotated the token under us: re-read the keychain
            // once and retry before declaring the session dead.
            cachedCredentials = nil
            let fresh = try currentCredentials()
            (data, http) = try await call(token: fresh.accessToken)
        }

        if http.statusCode == 429 {
            let hinted = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            retryAfter = Date().addingTimeInterval(max(hinted ?? defaultCooldown, 60))
            if let cached = lastGood { return cached.windows }
            throw Failure.http(429)
        }
        if http.statusCode == 401 { throw Failure.expired }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformed
        }

        let windows = Self.windows(from: json)
        guard !windows.isEmpty else { throw Failure.malformed }
        lastGood = (windows, Date())
        retryAfter = .distantPast
        Self.storeCache(windows)
        return windows
    }

    private func currentCredentials() throws -> Credentials {
        if let held = cachedCredentials, !held.isExpired { return held }
        cachedCredentials = nil
        guard let read = Self.keychainCredentials() else { throw Failure.noCredentials }
        guard !read.isExpired else { throw Failure.expired }
        cachedCredentials = read
        return read
    }

    private func call(token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformed }
        return (data, http)
    }

    // MARK: - Reading cache
    //
    // The last good reading is kept in UserDefaults so a relaunch during a
    // rate-limit cooldown still has a figure to show instead of a blank ring.
    // Reset dates are absolute, so a persisted reading keeps counting down;
    // anything older than an hour is discarded as no longer worth showing.

    private static let cacheKey = "anthropicUsageCache"

    private static func storeCache(_ windows: [UsageWindow]) {
        let payload: [String: Any] = [
            "at": Date().timeIntervalSince1970,
            "windows": windows.map { w -> [String: Any] in
                var dict: [String: Any] = ["id": w.id, "label": w.label, "used": w.usedFraction]
                if let resetsAt = w.resetsAt { dict["resets"] = resetsAt.timeIntervalSince1970 }
                return dict
            }
        ]
        UserDefaults.standard.set(payload, forKey: cacheKey)
    }

    private static func loadCache() -> (windows: [UsageWindow], at: Date)? {
        guard let payload = UserDefaults.standard.dictionary(forKey: cacheKey),
              let epoch = payload["at"] as? Double,
              let raw = payload["windows"] as? [[String: Any]]
        else { return nil }

        let at = Date(timeIntervalSince1970: epoch)
        guard Date().timeIntervalSince(at) < 3 * 3600 else { return nil }

        let windows = raw.compactMap { item -> UsageWindow? in
            guard let id = item["id"] as? String,
                  let label = item["label"] as? String,
                  let used = item["used"] as? Double else { return nil }
            let resets = (item["resets"] as? Double).map(Date.init(timeIntervalSince1970:))
            return UsageWindow(id: id, label: label, usedFraction: used,
                               resetsAt: resets, usedTokens: 0, limitTokens: 0)
        }
        return windows.isEmpty ? nil : (windows, at)
    }

    // MARK: - Response shape

    /// The payload names its windows by duration. Parsing is deliberately loose:
    /// an undocumented endpoint is allowed to rename a field, and losing one
    /// window should not take the whole reading down with it.
    static func windows(from json: [String: Any]) -> [UsageWindow] {
        let known: [(keys: [String], id: String, label: String)] = [
            (["five_hour", "fiveHour", "session"], "session", "Current session"),
            (["seven_day", "sevenDay", "week"], "weekly", "All models"),
            (["seven_day_opus", "sevenDayOpus", "opus"], "weekly_opus", "Opus")
        ]

        var out: [UsageWindow] = []
        for entry in known {
            guard let raw = entry.keys.compactMap({ json[$0] as? [String: Any] }).first,
                  let fraction = utilization(in: raw) else { continue }
            out.append(UsageWindow(id: entry.id,
                                   label: entry.label,
                                   usedFraction: fraction,
                                   resetsAt: resetDate(in: raw),
                                   usedTokens: 0,
                                   limitTokens: 0))
        }
        return out
    }

    /// Percentages arrive as 0–100, occasionally as 0–1. Anything above 1 is
    /// unambiguously a percentage, and below that either reading means "empty".
    private static func utilization(in raw: [String: Any]) -> Double? {
        for key in ["utilization", "used_percent", "usedPercent", "percent_used", "percent"] {
            if let value = raw[key] as? Double { return value > 1 ? value / 100 : value }
            if let value = raw[key] as? Int { return Double(value) / 100 }
        }
        return nil
    }

    private static func resetDate(in raw: [String: Any]) -> Date? {
        for key in ["resets_at", "resetsAt", "reset_at"] {
            if let stamp = raw[key] as? String, let date = ISO8601.date(from: stamp) { return date }
            if let epoch = raw[key] as? Double { return Date(timeIntervalSince1970: epoch) }
        }
        for key in ["resets_in_seconds", "resetsInSeconds"] {
            if let seconds = raw[key] as? Double { return Date().addingTimeInterval(seconds) }
        }
        return nil
    }

    // MARK: - Keychain

    static func keychainCredentials() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // The blob nests the tokens under a provider key; take whichever branch
        // actually carries an access token rather than hard-coding the name.
        let candidates: [[String: Any]] = [json] + json.values.compactMap { $0 as? [String: Any] }
        for candidate in candidates {
            guard let token = (candidate["accessToken"] ?? candidate["access_token"]) as? String,
                  !token.isEmpty else { continue }
            var expiry: Date?
            if let ms = (candidate["expiresAt"] ?? candidate["expires_at"]) as? Double {
                // Milliseconds since the epoch, as JavaScript writes them.
                expiry = Date(timeIntervalSince1970: ms > 4_000_000_000 ? ms / 1000 : ms)
            }
            return Credentials(accessToken: token, expiresAt: expiry)
        }
        return nil
    }
}
