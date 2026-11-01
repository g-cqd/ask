/// Built-in spinner styles supported in the configuration file (`ui.spinner`). `dot` and `star` are still read, so a file that names one
/// loads, and are drawn as the default spinner: they are no longer offered (roadmap 0171).
public enum SpinnerPreference: String, Sendable, CaseIterable {
    case braille
    case braillefull
    case braillequarter
    case snake
    case line
    case dot
    case star
    case random

    /// The styles offered, in the `/config` editor and the catalog: every one but the two that are only still read.
    public static var allCases: [SpinnerPreference] {
        [.braille, .braillefull, .braillequarter, .snake, .line, .random]
    }
}
