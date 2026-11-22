/// `ui.sessionTint`: where the session's colour shows, once `ui.sessionColor` gives it one: the status line's background and the input
/// box's border (`both`, the default), only one of them, or `none`.
/// Declared once for the setting and the screen (ADR-0166).
public enum SessionTint: String, Sendable, CaseIterable {
    case both, status, input, none
}
