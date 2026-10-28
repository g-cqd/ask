internal import Synchronization

/// Keeps the Mac awake while ask works (roadmap 0090): from the moment a turn starts or a background job runs, until the last of them ends.
/// One activity is held at most, begun with the first reason to hold it and ended with the last; with `off`, none ever is.
public final class KeepAwake: Sendable {
    private struct State {
        var mode: KeepAwakeMode
        var turns = 0
        var jobsRunning = false
        var activity: (any Sendable)?
    }

    /// What `pmset -g assertions` shows while ask holds one.
    public static let reason = "ask is working"

    private let state: Mutex<State>
    private let activities: any PowerActivities

    public init(mode: KeepAwakeMode, activities: any PowerActivities = SystemPowerActivities()) {
        state = Mutex(State(mode: mode))
        self.activities = activities
    }

    /// Whether an activity is held now.
    public var isHolding: Bool { state.withLock { $0.activity != nil } }

    /// A turn began. Pair it with ``turnEnded()``, however the turn ends.
    public func turnStarted() { change { $0.turns += 1 } }

    /// A turn ended.
    public func turnEnded() { change { $0.turns = Swift.max(0, $0.turns - 1) } }

    /// Whether any background job is running.
    public func jobsRunning(_ running: Bool) { change { $0.jobsRunning = running } }

    /// The mode the configuration names now. A held activity is ended, and begun again in the new mode if there is still work.
    public func use(_ mode: KeepAwakeMode) {
        let old: (any Sendable)? = state.withLock { state in
            guard state.mode != mode else { return nil }
            state.mode = mode
            let old = state.activity
            state.activity = nil
            if mode != .off, state.turns > 0 || state.jobsRunning {
                state.activity = activities.begin(mode, reason: Self.reason)
            }
            return old
        }
        if let old { activities.end(old) }
    }

    /// Applies `edit`, then begins or ends the activity when whether there is work changed.
    private func change(_ edit: (inout State) -> Void) {
        let ended: (any Sendable)? = state.withLock { state in
            edit(&state)
            let working = state.turns > 0 || state.jobsRunning
            if working, state.activity == nil, state.mode != .off {
                state.activity = activities.begin(state.mode, reason: Self.reason)
            } else if !working, let activity = state.activity {
                state.activity = nil
                return activity
            }
            return nil
        }
        if let ended { activities.end(ended) }
    }
}
