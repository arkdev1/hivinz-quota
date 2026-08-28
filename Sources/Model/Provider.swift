import Foundation

/// The glyphs drawn inside each ring. These are our own vector `Path`s, not
/// imported logos — see `ProviderGlyph`.
enum GlyphKind: String, Codable, CaseIterable {
    case anthropic
    case openai
    case gemini
    case terminal
    case sparkle
}

struct Provider: Identifiable, Codable, Hashable {
    typealias ID = String

    let id: ID
    var displayName: String
    var glyph: GlyphKind
    var isEnabled: Bool
    var sortIndex: Int
    /// If the user knows their real ceiling they pin it here; otherwise the
    /// value is calibrated from history.
    var sessionLimitOverride: Int?
    var weeklyLimitOverride: Int?
    /// External command printing JSON to stdout (script-backed providers).
    var scriptCommand: String?

    static let claude = Provider(
        id: "claude", displayName: "Claude Usage", glyph: .anthropic,
        isEnabled: true, sortIndex: 0,
        sessionLimitOverride: nil, weeklyLimitOverride: nil, scriptCommand: nil
    )

    static let codex = Provider(
        id: "codex", displayName: "Codex Usage", glyph: .openai,
        isEnabled: true, sortIndex: 1,
        sessionLimitOverride: nil, weeklyLimitOverride: nil, scriptCommand: nil
    )

    static let gemini = Provider(
        id: "gemini", displayName: "Gemini Usage", glyph: .gemini,
        isEnabled: true, sortIndex: 2,
        sessionLimitOverride: nil, weeklyLimitOverride: nil, scriptCommand: nil
    )

    static let openai = Provider(
        id: "openai", displayName: "OpenAI Usage", glyph: .openai,
        isEnabled: false, sortIndex: 3,
        sessionLimitOverride: nil, weeklyLimitOverride: nil, scriptCommand: nil
    )

    static let builtIn: [Provider] = [.claude, .codex, .gemini, .openai]
}
