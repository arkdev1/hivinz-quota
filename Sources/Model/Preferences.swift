import Foundation
import Observation

@Observable
final class Preferences {

    static let shared = Preferences()

    var providers: [Provider] { didSet { save(providers, "providers") } }
    var refreshSeconds: Double { didSet { save(refreshSeconds, "refreshSeconds") } }
    /// Below this the ring is green.
    var warningThreshold: Double { didSet { save(warningThreshold, "warningThreshold") } }
    /// From here up the ring is red.
    var criticalThreshold: Double { didSet { save(criticalThreshold, "criticalThreshold") } }
    var weeklyAnchorWeekday: Int { didSet { save(weeklyAnchorWeekday, "weeklyAnchorWeekday") } }
    var weeklyAnchorHour: Int { didSet { save(weeklyAnchorHour, "weeklyAnchorHour") } }
    var showNotchWidget: Bool { didSet { save(showNotchWidget, "showNotchWidget") } }
    /// The rail hangs from the right edge of the screen (default) or the left.
    var anchorOnRight: Bool { didSet { save(anchorOnRight, "anchorOnRight") } }
    /// When true the rail latches onto the notch instead of the screen edge.
    var useNotchAnchor: Bool { didSet { save(useNotchAnchor, "useNotchAnchor") } }
    /// How far below the menu bar the rail has been dragged.
    var verticalOffset: Double { didSet { save(verticalOffset, "verticalOffset") } }
    /// Allow estimating usage by reading local CLI transcripts when a provider's
    /// API path is unavailable. Off by default: it costs a filesystem scan and
    /// only ever produces an approximation.
    var allowLocalEstimate: Bool { didSet { save(allowLocalEstimate, "allowLocalEstimate") } }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "providers"),
           let decoded = try? JSONDecoder().decode([Provider].self, from: data), !decoded.isEmpty {
            // A provider added in a later version has to show up without wiping
            // the choices the user already made.
            var merged = decoded
            for builtIn in Provider.builtIn where !merged.contains(where: { $0.id == builtIn.id }) {
                merged.append(builtIn)
            }
            providers = merged.sorted { $0.sortIndex < $1.sortIndex }
        } else {
            providers = Provider.builtIn
        }
        refreshSeconds = d.object(forKey: "refreshSeconds") as? Double ?? 20
        warningThreshold = d.object(forKey: "warningThreshold") as? Double ?? 0.50
        criticalThreshold = d.object(forKey: "criticalThreshold") as? Double ?? 0.70
        weeklyAnchorWeekday = d.object(forKey: "weeklyAnchorWeekday") as? Int ?? 5
        weeklyAnchorHour = d.object(forKey: "weeklyAnchorHour") as? Int ?? 0
        showNotchWidget = d.object(forKey: "showNotchWidget") as? Bool ?? true
        anchorOnRight = d.object(forKey: "anchorOnRight") as? Bool ?? true
        useNotchAnchor = d.object(forKey: "useNotchAnchor") as? Bool ?? false
        verticalOffset = d.object(forKey: "verticalOffset") as? Double ?? 0
        allowLocalEstimate = d.object(forKey: "allowLocalEstimate") as? Bool ?? false
    }

    var enabledProviders: [Provider] {
        providers.filter(\.isEnabled).sorted { $0.sortIndex < $1.sortIndex }
    }

    func config(for provider: Provider) -> SourceConfig {
        SourceConfig(
            weeklyAnchorWeekday: weeklyAnchorWeekday,
            weeklyAnchorHour: weeklyAnchorHour,
            sessionLimitOverride: provider.sessionLimitOverride,
            weeklyLimitOverride: provider.weeklyLimitOverride,
            scriptCommand: provider.scriptCommand,
            allowLocalEstimate: allowLocalEstimate
        )
    }

    func update(_ provider: Provider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let plain = value as? any (Encodable & PlistRepresentable) {
            defaults.set(plain, forKey: key)
        } else if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Marks the types UserDefaults can already store without a JSON round trip.
protocol PlistRepresentable {}
extension Bool: PlistRepresentable {}
extension Int: PlistRepresentable {}
extension Double: PlistRepresentable {}
extension String: PlistRepresentable {}
