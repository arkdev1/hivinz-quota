import SwiftUI

@main
struct QuotaApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = UsageStore.shared
    @State private var prefs = Preferences.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            let critical = store.mostCritical
            Image(systemName: symbol(for: critical?.window.clampedFraction))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }

    /// The menu bar icon reports, at a glance, whichever provider is worst off.
    private func symbol(for fraction: Double?) -> String {
        guard let fraction else { return "gauge.with.dots.needle.bottom.0percent" }
        switch fraction {
        case ..<0.25: return "gauge.with.dots.needle.bottom.0percent"
        case ..<0.60: return "gauge.with.dots.needle.bottom.50percent"
        default: return "gauge.with.dots.needle.bottom.100percent"
        }
    }
}

struct MenuBarContent: View {

    @State private var store = UsageStore.shared
    @State private var prefs = Preferences.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(prefs.enabledProviders) { provider in
            Text(line(for: provider))
        }

        Divider()

        Button("Refresh Now") {
            Task { await store.refresh() }
        }
        .keyboardShortcut("r")

        Toggle("Show Widget", isOn: Binding(
            get: { prefs.showNotchWidget },
            set: { prefs.showNotchWidget = $0 }
        ))

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit Quota") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func line(for provider: Provider) -> String {
        switch store.state(for: provider.id) {
        case .ready(let snapshot):
            guard let window = snapshot.headline else { return "\(provider.displayName): —" }
            return "\(provider.displayName): \(window.percentText) · \(window.resetText())"
        case .loading:
            return "\(provider.displayName): reading…"
        case .unavailable(let reason), .failed(let reason):
            return "\(provider.displayName): \(reason)"
        }
    }
}
