/// When a command's timeout is written in its block's header (`ui.timeout`, roadmap 0126).
public enum TimeoutDisplay: String, Sendable, CaseIterable {
    /// Only a timeout the call chose that differs from the tool's default; the yield whenever the call set one. The default.
    case auto
    /// Every limit the call set.
    case always
    /// None.
    case never
}
