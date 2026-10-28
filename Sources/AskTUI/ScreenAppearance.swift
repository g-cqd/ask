/// Where the screen's tints come from (`ui.appearance`, roadmap 0108).
public enum ScreenAppearance: String, Sendable, CaseIterable {
    /// From the terminal's own colours, read at start and again whenever macOS changes appearance.
    case auto
    /// Mixed for a light page, whatever the terminal says.
    case light
    /// Mixed for a dark page, whatever the terminal says.
    case dark
}
