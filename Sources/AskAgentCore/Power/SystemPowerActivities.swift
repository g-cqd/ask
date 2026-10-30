internal import Foundation

/// The system's activities (roadmap 0090): `ProcessInfo.beginActivity`, a Foundation API ask already links, which takes the same power
/// assertions `caffeinate` takes and needs no child process. The system drops the assertion when ask's process ends, even when it crashes or
/// is killed; checked with `pmset -g assertions` after `kill -9`.
public struct SystemPowerActivities: PowerActivities {
    public init() {}

    public func begin(_ mode: KeepAwakeMode, display: Bool, reason: String) -> any Sendable {
        let options: ProcessInfo.ActivityOptions =
            display ? [.idleSystemSleepDisabled, .idleDisplaySleepDisabled] : [.idleSystemSleepDisabled]
        return Token(ProcessInfo.processInfo.beginActivity(options: options, reason: reason))
    }

    public func end(_ activity: any Sendable) {
        guard let token = activity as? Token else { return }
        ProcessInfo.processInfo.endActivity(token.activity)
    }

    /// The activity Foundation returns, which it only ever hands back to `endActivity`.
    // SAFETY: the token is never read or changed; it is only handed back once to `endActivity`, which may be called from any thread.
    private struct Token: @unchecked Sendable {
        let activity: any NSObjectProtocol
        init(_ activity: any NSObjectProtocol) { self.activity = activity }
    }
}
