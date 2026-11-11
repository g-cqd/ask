/// How the screen tells you a turn ended or that it waits for your answer while you look elsewhere (`ui.notify`, note n62).
public enum NotifyStyle: String, Sendable, CaseIterable {
    case off, bell, notification
}
