/// `keepAwake` (roadmap 0090): what ask keeps awake while it works, that is while a turn runs or a background job does.
public enum KeepAwakeMode: String, Sendable, CaseIterable {
    /// Nothing: the Mac sleeps as it would without ask.
    case off
    /// The Mac does not go to sleep when idle; the display may.
    case system
    /// Neither the Mac nor the display goes to sleep when idle.
    case display
    /// The Mac does not go to sleep when idle for as long as ask runs, working or not (roadmap 0148); the display may.
    case always

    /// The choices, as an error names them.
    static let choices = #""off", "system", "display" or "always""#
}
