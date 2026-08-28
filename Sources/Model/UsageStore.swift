import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {

    static let shared = UsageStore()

    private(set) var states: [Provider.ID: ProviderState] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private let sources: [Provider.ID: any UsageSource] = [
        "claude": ClaudeUsageSource(),
        "codex": CodexSource(),
        "gemini": ScriptSource(providerID: "gemini",
                               hint: "Gemini CLI not found — set a command"),
        "openai": ScriptSource(providerID: "openai",
                               hint: "No local logs — set a command")
    ]

    private var timer: Timer?
    private let prefs = Preferences.shared

    private init() {}

    func start() {
        Task { await refresh() }
        scheduleTimer()
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: prefs.refreshSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func state(for id: Provider.ID) -> ProviderState {
        states[id] ?? .loading
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = prefs.enabledProviders

        // Providers are polled in parallel: a slow one must not hold up the rest.
        await withTaskGroup(of: (Provider.ID, ProviderState).self) { group in
            for provider in providers {
                guard let source = sources[provider.id] else { continue }
                let config = prefs.config(for: provider)
                group.addTask {
                    (provider.id, await source.fetch(config: config))
                }
            }
            for await (id, state) in group {
                states[id] = merged(old: states[id], new: state)
            }
        }

        for id in states.keys where !providers.contains(where: { $0.id == id }) {
            states.removeValue(forKey: id)
        }
        lastRefresh = Date()
    }

    /// A transient failure must not blank a ring that had a good reading moments
    /// ago: keep the last snapshot for up to an hour before surfacing the error.
    private func merged(old: ProviderState?, new: ProviderState) -> ProviderState {
        if case .ready = new { return new }
        if let old, case .ready(let snapshot) = old,
           Date().timeIntervalSince(snapshot.fetchedAt) < 3600 {
            return old
        }
        return new
    }

    /// The provider closest to its limit — the one that drives the menu bar icon.
    var mostCritical: (provider: Provider, window: UsageWindow)? {
        var best: (Provider, UsageWindow)?
        for provider in prefs.enabledProviders {
            guard let window = states[provider.id]?.snapshot?.headline else { continue }
            if best == nil || window.clampedFraction > best!.1.clampedFraction {
                best = (provider, window)
            }
        }
        return best
    }
}
