/// How ask tells you a turn is done, or that it waits for your answer, while you look elsewhere (`ui.notify`, note n62): `"off"`
/// (default), `"bell"`, or `"notification"`, the desktop's, through the terminal.
public enum NotifyPreference: String, Sendable, CaseIterable {
    case off, bell, notification
}
