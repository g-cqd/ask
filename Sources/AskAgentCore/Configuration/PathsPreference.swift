/// `ui.paths` (roadmap 0215): paths in replies and reasoning shown relative to the project (`short`, the default) or `asWritten`; linked
/// either way.
public enum PathsPreference: String, Sendable, CaseIterable {
    case short, asWritten
}
