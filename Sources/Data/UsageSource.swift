import Foundation

struct SourceConfig: Sendable {
    /// 1 = Sunday … 5 = Thursday. The reference design shows "Resets Thu 12:00 AM".
    var weeklyAnchorWeekday: Int = 5
    var weeklyAnchorHour: Int = 0
    var sessionLimitOverride: Int?
    var weeklyLimitOverride: Int?
    var scriptCommand: String?
    /// Whether a provider may fall back to reading local logs when its API path
    /// is unavailable. Off by default: that fallback scans transcripts.
    var allowLocalEstimate: Bool = false
    /// A user-initiated refresh: skip freshness caches, but never a 429 cooldown
    /// — being rate limited is a fact about the server, not about our cache.
    var force: Bool = false
}

protocol UsageSource: Sendable {
    var providerID: Provider.ID { get }
    func fetch(config: SourceConfig) async -> ProviderState
}

/// How tokens are weighted, following their relative cost: output counts about
/// 5x input, a cache write 1.25x, a cache read 0.1x. Without these weights the
/// cache reads — which are nearly free — would swamp the total and the
/// percentage would stop meaning anything.
enum TokenWeight {
    static let input = 1.0
    static let cacheCreation = 1.25
    static let cacheRead = 0.1
    static let output = 5.0

    static func weighted(input: Int, cacheCreation: Int, cacheRead: Int, output: Int) -> Int {
        Int((Double(input) * Self.input
             + Double(cacheCreation) * Self.cacheCreation
             + Double(cacheRead) * Self.cacheRead
             + Double(output) * Self.output).rounded())
    }
}

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
