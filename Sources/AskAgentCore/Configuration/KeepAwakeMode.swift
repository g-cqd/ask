/// `keepAwake` (roadmaps 0090, 0148 and 0154): when ask keeps the Mac from sleeping. Whether the display stays on too is
/// `keepDisplayAwake`, a separate switch, so every pair can be said.
public enum KeepAwakeMode: String, Sendable, CaseIterable {
    /// Never: the Mac sleeps as it would without ask.
    case off
    /// While ask works: a turn runs or a background job does.
    case working
    /// For as long as ask runs, working or not (roadmap 0148).
    case always

    /// The choices, as an error names them.
    static let choices = #""working", "always" or "off""#
}
