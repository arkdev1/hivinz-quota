import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ProvidersPane()
                .tabItem { Label("Providers", systemImage: "circle.grid.2x2") }
            AppearancePane()
                .tabItem { Label("Appearance", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 540, height: 460)
    }
}

private struct ProvidersPane: View {

    @State private var prefs = Preferences.shared
    @State private var store = UsageStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(prefs.providers) { provider in
                    ProviderRow(provider: provider)
                }
            } footer: {
                Text("Limits apply to the local-log fallback only. Left empty, the "
                     + "ceiling calibrates itself against the heaviest session on record.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Refresh") {
                LabeledContent("Every") {
                    Stepper(value: Binding(
                        get: { prefs.refreshSeconds },
                        set: { prefs.refreshSeconds = $0; store.scheduleTimer() }
                    ), in: 5...300, step: 5) {
                        Text("\(Int(prefs.refreshSeconds)) s")
                    }
                }
                Button("Refresh Now") { Task { await store.refresh() } }
                Button("Force Refresh") { Task { await store.refresh(force: true) } }
            }

            Section {
                Toggle("Estimate from local logs when an API is unavailable", isOn: Binding(
                    get: { prefs.allowLocalEstimate },
                    set: { prefs.allowLocalEstimate = $0; Task { await store.refresh() } }))
            } footer: {
                Text("Off by default. Claude reports exact figures through the OAuth "
                     + "session Claude Code already holds, and Codex writes its own "
                     + "rate limits into the newest rollout \u{2014} neither needs a scan. "
                     + "The fallback reads transcripts under your home folder and only "
                     + "ever approximates.")
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
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
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
                        set: { var p = current; p.scriptCommand = $0.isEmpty ? nil : $0; prefs.update(p) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                Text("The command must print to stdout "
                     + #"{"windows":[{"label":"…","used":0.73,"resets_in_seconds":3060}]}"#)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Toggle(isOn: Binding(
                get: { current.isEnabled },
                set: { var p = current; p.isEnabled = $0; prefs.update(p) }
            )) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.black)
                        ProviderGlyph(kind: provider.glyph, size: 11)
                    }
                    .frame(width: 20, height: 20)
                    Text(provider.displayName)
                }
            }
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
            .frame(width: 140)
            .multilineTextAlignment(.trailing)
    }
}

private struct AppearancePane: View {

    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
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
            }

            Section("Theme") {
                Picker("Appearance", selection: Binding(
                    get: { prefs.theme }, set: { prefs.theme = $0 })) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }

            Section("Colour thresholds") {
                Slider(value: Binding(
                    get: { prefs.warningThreshold }, set: { prefs.warningThreshold = $0 }),
                       in: 0.1...0.9) {
                    Text("Yellow from \(Int(prefs.warningThreshold * 100))%")
                }
                Slider(value: Binding(
                    get: { prefs.criticalThreshold }, set: { prefs.criticalThreshold = $0 }),
                       in: 0.1...1.0) {
                    Text("Red from \(Int(prefs.criticalThreshold * 100))%")
                }
                HStack(spacing: 14) {
                    ForEach([0.2, 0.55, 0.85], id: \.self) { value in
                        RingGauge(fraction: value, glyph: .sparkle, size: 28)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
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

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                                   "Thursday", "Friday", "Saturday"]
}
