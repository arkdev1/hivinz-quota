import Foundation

/// Token spend attributed to a moment in time — the common unit across every
/// provider that reads local logs.
struct TokenEvent {
    let date: Date
    let tokens: Int
}

/// Folds events into the two windows we care about and estimates the ceilings.
enum TokenLedger {

    static let sessionWindow: TimeInterval = 5 * 3600

    // MARK: - Session window (5-hour block)

    /// Both Anthropic and Codex start the window at the *first* message, floored
    /// to the hour, and it runs for 5 hours; a gap longer than that closes the
    /// block. Returns the active block, or nil when there is no recent activity.
    static func activeBlock(events: [TokenEvent], now: Date = Date()) -> (start: Date, end: Date)? {
        guard !events.isEmpty else { return nil }
        var blockStart: Date?
        var lastEvent: Date?

        for e in events { // already sorted oldest first
            if let start = blockStart, let last = lastEvent,
               e.date.timeIntervalSince(start) < sessionWindow,
               e.date.timeIntervalSince(last) < sessionWindow {
                lastEvent = e.date
            } else {
                blockStart = floorToHour(e.date)
                lastEvent = e.date
            }
        }

        guard let start = blockStart else { return nil }
        let end = start.addingTimeInterval(sessionWindow)
        return end > now ? (start, end) : nil
    }

    /// Every closed block in history with its token total: this is how the real
    /// ceiling of the plan is inferred without asking the user for it.
    static func completedBlockTotals(events: [TokenEvent], now: Date = Date()) -> [Int] {
        guard !events.isEmpty else { return [] }
        var totals: [Int] = []
        var blockStart: Date?
        var lastEvent: Date?
        var running = 0

        for e in events {
            if let start = blockStart, let last = lastEvent,
               e.date.timeIntervalSince(start) < sessionWindow,
               e.date.timeIntervalSince(last) < sessionWindow {
                running += e.tokens
                lastEvent = e.date
            } else {
                if let start = blockStart, start.addingTimeInterval(sessionWindow) <= now {
                    totals.append(running)
                }
                blockStart = floorToHour(e.date)
                lastEvent = e.date
                running = e.tokens
            }
        }
        if let start = blockStart, start.addingTimeInterval(sessionWindow) <= now {
            totals.append(running)
        }
        return totals
    }

    // MARK: - Weekly window

    /// The weekly reset is anchored to a fixed weekday and hour (Thursday 00:00
    /// by default, as in the reference design). Returns this anchor and the next.
    static func weeklyBounds(weekday: Int, hour: Int, now: Date = Date()) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = 0
        comps.second = 0

        let start = cal.nextDate(after: now, matching: comps,
                                 matchingPolicy: .nextTime, direction: .backward)
            ?? now.addingTimeInterval(-7 * 86400)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? now.addingTimeInterval(86400)
        return (start, end)
    }

    // MARK: - Ceilings

    /// The estimated ceiling: the heaviest closed block ever observed, with a
    /// floor so the first days of use do not produce absurd percentages.
    static func calibratedLimit(from totals: [Int], floor: Int) -> Int {
        max(totals.max() ?? 0, floor)
    }

    static func sum(_ events: [TokenEvent], from: Date, to: Date) -> Int {
        events.reduce(0) { acc, e in
            (e.date >= from && e.date < to) ? acc + e.tokens : acc
        }
    }

    private static func floorToHour(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}
