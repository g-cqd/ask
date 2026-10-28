/// `ui.appearance` (roadmap 0108): where the screen's tints come from. `auto` reads the terminal's own colours and follows them when macOS
/// changes appearance; `light` and `dark` fix the tints for that kind of page and ask the terminal nothing.
public enum AppearancePreference: String, Sendable, CaseIterable {
    case auto
    case light
    case dark
}
