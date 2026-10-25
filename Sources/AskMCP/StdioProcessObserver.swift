/// Told when a stdio server's process starts and ends, so something outside this library can look after it (ADR-0102): ask lists the
/// group with the watchdog that stops it if ask is killed.
public protocol StdioProcessObserver: Sendable {
    /// The process has started. It leads a session of its own, so this is also its process group.
    func started(group: Int32)

    /// The process has ended and been reaped: the group id may be used again.
    func ended(group: Int32)
}
