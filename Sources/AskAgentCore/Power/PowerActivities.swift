/// Where an activity that keeps the Mac awake is begun and ended: the system, or a test's record of the calls.
public protocol PowerActivities: Sendable {
    /// Begins keeping the system (and with `display`, the display) awake, for `reason`, which `pmset -g assertions` shows. Never called
    /// with `off`.
    func begin(_ mode: KeepAwakeMode, reason: String) -> any Sendable
    /// Ends what `begin` returned.
    func end(_ activity: any Sendable)
}
