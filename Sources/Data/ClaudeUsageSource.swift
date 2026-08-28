import Foundation

/// Claude's reading, preferring the truth over an estimate.
///
/// The OAuth endpoint returns the same percentages the CLI shows, so it goes
/// first. Only if the user has explicitly allowed it do we fall back to adding up
/// tokens from the local transcripts — that path is an approximation and it costs
/// a scan of `~/.claude/projects`, so it stays off unless asked for.
actor ClaudeUsageSource: UsageSource {

    nonisolated let providerID: Provider.ID = "claude"

    private let remote = AnthropicOAuthSource()
    private let local = ClaudeCodeSource()

    func fetch(config: SourceConfig) async -> ProviderState {
        do {
            let windows = try await remote.fetchWindows()
            return .ready(UsageSnapshot(providerID: providerID,
                                        windows: windows,
                                        fetchedAt: Date()))
        } catch {
            guard config.allowLocalEstimate else {
                let reason = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                return .unavailable(reason)
            }
            return await local.fetch(config: config)
        }
    }
}
