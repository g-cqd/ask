/// Which keys interrupt a running turn (`ui.interruptKeys`, roadmap 0083).
public enum InterruptKeysPreference: String, Sendable, CaseIterable {
    case esc
    case ctrlC = "ctrl-c"
    case both
}
