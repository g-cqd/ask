internal import Synchronization

/// A conversation's goal (roadmap 0227): the condition, its bounds, the turns judged and how it ended. Shared by the hook that
/// judges it and the command that sets it.
public final class GoalState: Sendable {
    /// How a goal ended.
    public enum Outcome: Sendable, Equatable {
        case met(String)
        case impossible(String)
        case stoppedAtBound
        case cleared
    }

    /// A goal as it stands.
    public struct Goal: Sendable, Equatable {
        public var condition: String
        public var started: ContinuousClock.Instant
        public var turns = 0
        public var maxTurns: Int
        public var maxDuration: Duration
        public var lastReason: String?
        public var outcome: Outcome?

        public var isActive: Bool { outcome == nil }
    }

    public static let defaultMaxTurns = 10
    public static let defaultMaxDuration: Duration = .seconds(3600)

    private let state = Mutex<Goal?>(nil)

    public init() {}

    /// The goal, active or the last one that ended.
    public var goal: Goal? { state.withLock { $0 } }

    /// Sets `condition` as the goal, replacing any.
    public func set(_ condition: String, maxTurns: Int = defaultMaxTurns, maxDuration: Duration = defaultMaxDuration) {
        state.withLock { $0 = Goal(condition: condition, started: .now, maxTurns: maxTurns, maxDuration: maxDuration) }
    }

    /// Ends the active goal with `outcome`; returns the goal it ended, nil when none was active.
    @discardableResult
    public func end(_ outcome: Outcome) -> Goal? {
        state.withLock { goal in
            guard goal?.isActive == true else { return nil }
            goal?.outcome = outcome
            return goal
        }
    }

    /// Counts a judged turn that was not enough, with the judge's reason.
    func judged(_ reason: String) {
        state.withLock { goal in
            goal?.turns += 1
            goal?.lastReason = reason
        }
    }

    /// Extends the active goal's bounds by as much again.
    func extend() {
        state.withLock { goal in
            guard let current = goal, current.isActive else { return }
            goal?.maxTurns = current.turns + Self.defaultMaxTurns
            goal?.maxDuration = (ContinuousClock.now - current.started) + Self.defaultMaxDuration
        }
    }

    /// Whether the active goal has reached a bound, and which.
    func bound(now: ContinuousClock.Instant = .now) -> String? {
        state.withLock { goal in
            guard let goal, goal.isActive else { return nil }
            if goal.turns >= goal.maxTurns { return "\(goal.maxTurns) turns" }
            if now - goal.started >= goal.maxDuration {
                return "\(Int(goal.maxDuration.components.seconds / 60)) minutes"
            }
            return nil
        }
    }
}
