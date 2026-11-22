/// Which keys interrupt a running turn (`ui.interruptKeys`, roadmap 0083).
/// Declared once for the setting and the screen (ADR-0166).
public enum InterruptKeys: String, Sendable, CaseIterable {
    case esc
    case ctrlC = "ctrl-c"
    case both
}
