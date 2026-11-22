/// When a command's timeout is written in its header (`ui.timeout`, roadmap 0126): `"auto"` (only one other than the tool's default),
/// `"always"` or `"never"`.
/// Declared once for the setting and the screen (ADR-0166).
public enum TimeoutDisplay: String, Sendable, CaseIterable {
    /// Only a timeout the call chose that differs from the tool's default; the yield whenever the call set one. The default.
    case auto
    /// Every limit the call set.
    case always
    /// None.
    case never
}
