/// When a command's timeout is written in its header (`ui.timeout`, roadmap 0126): `"auto"` (only one other than the tool's default),
/// `"always"` or `"never"`.
public enum TimeoutPreference: String, Sendable, CaseIterable {
    case auto, always, never
}
