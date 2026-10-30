/// `ui.sessionColor` (roadmap 0164): whether the status line takes a colour of the session's own, so sessions can be told apart. `off`
/// (the default), `always`, or `others`: only while another ask runs on this Mac.
public enum SessionColorPreference: String, Sendable, CaseIterable {
    case off, always, others
}
