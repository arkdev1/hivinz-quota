import Foundation

/// One rate-limit window: "Current session" (5 hours), "All models" (weekly), …
struct UsageWindow: Identifiable, Hashable {
    let id: String
    /// Label shown above the bar, e.g. "Current session".
    let label: String
    /// 0...1 — can exceed 1 when the estimated ceiling is blown through; the UI clamps it.
    let usedFraction: Double
    /// When the window resets to zero. `nil` when it cannot be worked out.
    let resetsAt: Date?
    /// Token detail, surfaced in Settings.
    let usedTokens: Int
    let limitTokens: Int

    var clampedFraction: Double { min(max(usedFraction, 0), 1) }

    var percentText: String { "\(Int((clampedFraction * 100).rounded()))%" }

    /// "Resets in 51 min" / "Resets Thu 12:00 AM", as in the reference design.
    func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "—" }
        let delta = resetsAt.timeIntervalSince(now)
        guard delta > 0 else { return "Resets now" }
        if delta < 3600 {
            return "Resets in \(Int((delta / 60).rounded(.up))) min"
        }
        if delta < 12 * 3600 {
            let h = Int(delta / 3600)
            let m = Int((delta - Double(h) * 3600) / 60)
            return m == 0 ? "Resets in \(h)h" : "Resets in \(h)h \(m)m"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = Calendar.current.isDateInToday(resetsAt) ? "h:mm a" : "EEE h:mm a"
        return "Resets \(f.string(from: resetsAt))"
    }
}

/// A provider's state at a point in time.
enum ProviderState: Equatable {
    case loading
    /// Configured, but there is nothing to read: no logs, or the CLI isn't installed.
    case unavailable(String)
    case failed(String)
    case ready(UsageSnapshot)

    var snapshot: UsageSnapshot? {
        if case .ready(let s) = self { return s }
        return nil
    }
}

struct UsageSnapshot: Equatable {
    let providerID: Provider.ID
    let windows: [UsageWindow]
    let fetchedAt: Date

    /// The window that drives the ring and the menu bar figure. Always the
    /// session window when there is one: a ring that silently switches to
    /// whichever window is worst reads as the number jumping around.
    var primary: UsageWindow? {
        windows.first(where: { $0.id == "session" }) ?? windows.first
    }

    /// The window closest to its limit — what the collapsed stub's colour and
    /// severity decisions care about.
    var headline: UsageWindow? {
        windows.max(by: { $0.clampedFraction < $1.clampedFraction })
    }
}
