/// Why the screen closed, so the caller can act after the terminal is restored.
public enum ScreenExit: Sendable, Equatable {
    /// The user left.
    case quit
    /// A command asked for ask to be replaced by a newer build of itself (`/reload`).
    case reload
}
