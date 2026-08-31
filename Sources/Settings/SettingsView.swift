import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersPane()
                .tabItem { Label("Providers", systemImage: "circle.grid.2x2") }
            AppearancePane()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 560, height: 500)
    }
}

// MARK: - General

private struct GeneralPane: View {

    @State private var prefs = Preferences.shared
    @State private var store = UsageStore.shared

    var body: some View {
        Form {
            Section("Refresh") {
                LabeledContent("Check every") {
                    Stepper(value: Binding(
                        get: { prefs.refreshSeconds },
                        set: { prefs.refreshSeconds = $0; store.scheduleTimer() }
                    ), in: 5...300, step: 5) {
                        Text("\(Int(prefs.refreshSeconds)) s")
                            .monospacedDigit()
                    }
                }
                LabeledContent("Last refresh") {
                    Text(lastRefreshText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Refresh Now") { Task { await store.refresh() } }
                    Button("Force Refresh") { Task { await store.refresh(force: true) } }
                        .help("Skips the one-minute cache. A server rate-limit "
                              + "cooldown is still honoured.")
                }
            }

            Section {
                Toggle("Estimate from local logs when an API is unavailable", isOn: Binding(
                    get: { prefs.allowLocalEstimate },
                    set: { prefs.allowLocalEstimate = $0; Task { await store.refresh() } }))
            } footer: {
                Text("Off by default. Claude reports exact figures through the OAuth "
                     + "session Claude Code already holds, and Codex writes its own "
                     + "rate limits into the newest rollout — neither needs a scan. "
                     + "The fallback reads transcripts under your home folder and only "
                     + "ever approximates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Weekly reset") {
                Picker("Day", selection: Binding(
                    get: { prefs.weeklyAnchorWeekday }, set: { prefs.weeklyAnchorWeekday = $0 })) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Self.weekdays[day - 1]).tag(day)
                    }
                }
                Picker("Hour", selection: Binding(
                    get: { prefs.weeklyAnchorHour }, set: { prefs.weeklyAnchorHour = $0 })) {
                    ForEach(0...23, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var lastRefreshText: String {
        guard let date = store.lastRefresh else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                   "Thursday", "Friday", "Saturday"]
}

// MARK: - Providers

private struct ProvidersPane: View {

    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                // List-in-form so rows can be reordered by dragging; the order
                // here is the order of the rings on the rail.
                List {
                    ForEach(prefs.providers) { provider in
                        ProviderRow(provider: provider)
                    }
                    .onMove { source, destination in
                        var ordered = prefs.providers
                        ordered.move(fromOffsets: source, toOffset: destination)
                        for (index, var provider) in ordered.enumerated() {
                            provider.sortIndex = index
                            prefs.update(provider)
                        }
                    }
                }
                .frame(minHeight: 52 * CGFloat(prefs.providers.count) + 8)
                .listStyle(.plain)
                .scrollDisabled(true)
            } header: {
                Text("Drag to reorder — the rail follows this order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Session and weekly limits apply to the local-log fallback "
                     + "only. Left empty, the ceiling calibrates itself against the "
                     + "heaviest session on record.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderRow: View {

    let provider: Provider
    @State private var prefs = Preferences.shared
    @State private var store = UsageStore.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.surface)
                    Circle().strokeBorder(Theme.track, lineWidth: 1)
                    ProviderGlyph(kind: provider.glyph, size: 13)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { current.isEnabled },
                    set: { var p = current; p.isEnabled = $0; prefs.update(p) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Session limit") {
                        TokenField(value: binding(\.sessionLimitOverride))
                    }
                    LabeledContent("Weekly limit") {
                        TokenField(value: binding(\.weeklyLimitOverride))
                    }
                    LabeledContent("Custom command") {
                        TextField("e.g. my-usage --json", text: Binding(
                            get: { current.scriptCommand ?? "" },
                            set: { var p = current
                                   p.scriptCommand = $0.isEmpty ? nil : $0
                                   prefs.update(p) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    }
                    Text("The command must print to stdout "
                         + #"{"windows":[{"label":"…","used":0.73,"resets_in_seconds":3060}]}"#)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 36)
                .padding(.bottom, 8)
            }
        }
    }

    /// The live reading, so Settings doubles as a status page.
    private var statusLine: String {
        guard current.isEnabled else { return "Disabled" }
        switch store.state(for: provider.id) {
        case .ready(let snapshot):
            guard let window = snapshot.primary else { return "No data" }
            return "\(window.percentText) used · \(window.resetText())"
        case .loading: return "Reading…"
        case .unavailable(let reason), .failed(let reason): return reason
        }
    }

    private var current: Provider {
        prefs.providers.first { $0.id == provider.id } ?? provider
    }

    private func binding(_ key: WritableKeyPath<Provider, Int?>) -> Binding<Int?> {
        Binding(
            get: { current[keyPath: key] },
            set: { var p = current; p[keyPath: key] = $0; prefs.update(p) }
        )
    }
}

/// A numeric field that also accepts empty, meaning "calibrate it yourself".
private struct TokenField: View {
    @Binding var value: Int?

    var body: some View {
        TextField("automatic", value: $value, format: .number.grouping(.automatic))
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Appearance

private struct AppearancePane: View {

    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: Binding(
                    get: { prefs.theme }, set: { prefs.theme = $0 })) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }

            Section("Widget") {
                Toggle("Show the usage rail", isOn: Binding(
                    get: { prefs.showNotchWidget }, set: { prefs.showNotchWidget = $0 }))
                Picker("Side", selection: Binding(
                    get: { prefs.anchorOnRight }, set: { prefs.anchorOnRight = $0 })) {
                    Text("Right edge").tag(true)
                    Text("Left edge").tag(false)
                }
                Toggle("Attach to the notch instead of the screen edge", isOn: Binding(
                    get: { prefs.useNotchAnchor }, set: { prefs.useNotchAnchor = $0 }))
                Picker("Display", selection: Binding(
                    get: { prefs.preferredScreenName ?? "" },
                    set: { prefs.preferredScreenName = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                LabeledContent("Position") {
                    Text("Drag the rail up and down; drag it across the screen "
                         + "to switch sides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Colour thresholds") {
                thresholdSlider("Yellow from", value: Binding(
                    get: { prefs.warningThreshold }, set: { prefs.warningThreshold = $0 }),
                    range: 0.1...0.9)
                thresholdSlider("Red from", value: Binding(
                    get: { prefs.criticalThreshold }, set: { prefs.criticalThreshold = $0 }),
                    range: 0.1...1.0)
                HStack(spacing: 18) {
                    preview(0.2)
                    preview(prefs.warningThreshold + 0.02)
                    preview(min(prefs.criticalThreshold + 0.1, 1))
                    Spacer()
                    Text("Live preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .formStyle(.grouped)
    }

    private func thresholdSlider(_ label: String, value: Binding<Double>,
                                 range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range)
            Text("\(label) \(Int(value.wrappedValue * 100))%")
                .monospacedDigit()
                .frame(width: 130, alignment: .trailing)
                .font(.callout)
        }
    }

    private func preview(_ fraction: Double) -> some View {
        VStack(spacing: 3) {
            RingGauge(fraction: fraction, glyph: .sparkle, size: 26, lineWidth: 3)
            Text("\(Int(fraction * 100))%")
                .font(Theme.rounded(10))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
