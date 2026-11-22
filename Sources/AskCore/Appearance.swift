/// `ui.appearance` (roadmap 0108): where the screen's tints come from. `auto` reads the terminal's own colours and follows them when macOS
/// changes appearance; `light` and `dark` fix the tints for that kind of page and ask the terminal nothing.
/// Declared once for the setting and the screen (ADR-0166).
public enum Appearance: String, Sendable, CaseIterable {
    /// From the terminal's own colours, read at start and again whenever macOS changes appearance.
    case auto
    /// Mixed for a light page, whatever the terminal says.
    case light
    /// Mixed for a dark page, whatever the terminal says.
    case dark
}
