/// `ui.sessionTint`: where the session's colour shows, once `ui.sessionColor` gives it one: the status line's background and the input
/// box's border (`both`, the default), only one of them, or `none`.
public enum SessionTintPreference: String, Sendable, CaseIterable {
    case both, status, input, none
}
