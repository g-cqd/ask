/// The goal's judge at `run.stop` (roadmap 0227): with a goal active, a run that would end is judged against it; not yet met, the run
/// goes on with what is missing; met or impossible, it ends and the goal with it. At a bound the person is asked to go on. The goal has
/// its own bound, so it is asked even past `hooks.maxContinues`.
public struct GoalHook: AgentHook {
    public let name = "goal"
    public var hasOwnBound: Bool { true }

    let state: GoalState
    /// Asks the judge `question`; nil when no answer came.
    let judge: @Sendable (_ question: String) async -> String?
    /// The run's recent entries as text, for the judge.
    let recent: @Sendable () -> String
    /// Asks the person whether to go on past `bound`; false when they say no or are not there.
    let atBound: @Sendable (_ bound: String) async -> Bool
    /// Tells the person how a goal ended.
    let notice: @Sendable (_ text: String) -> Void

    public init(
        state: GoalState,
        judge: @escaping @Sendable (String) async -> String?,
        recent: @escaping @Sendable () -> String,
        atBound: @escaping @Sendable (String) async -> Bool,
        notice: @escaping @Sendable (String) -> Void
    ) {
        self.state = state
        self.judge = judge
        self.recent = recent
        self.atBound = atBound
        self.notice = notice
    }

    public func runStop(_ stop: RunStop) async -> RunStopDecision {
        guard let goal = state.goal, goal.isActive else { return .stop }
        if let bound = state.bound() {
            guard await atBound(bound) else {
                state.end(.stoppedAtBound)
                notice("Goal stopped at its bound (\(bound)): \(goal.condition)")
                return .stop
            }
            state.extend()
        }
        guard let reply = await judge(GoalVerdict.question(condition: goal.condition, recent: recent())) else {
            notice("The goal's judge did not answer; the goal stays set, and is judged again when the next run ends.")
            return .stop
        }
        switch GoalVerdict.parse(reply) {
            case .met(let evidence):
                state.end(.met(evidence))
                notice("Goal met: \(goal.condition)" + (evidence.isEmpty ? "" : "\n\(evidence)"))
                return .stop
            case .impossible(let why):
                state.end(.impossible(why))
                notice("Goal judged impossible: \(why)")
                return .stop
            case .notYet(let missing):
                state.judged(missing)
                let turns = (state.goal?.turns ?? 0)
                return .continue(
                    // The reason is the judge's, a model that read the run's text: said as such, never as the person's words.
                    "Goal not met yet (\(turns) of \(goal.maxTurns)). Its judge, a separate model that read this run, says what is "
                        + "missing: \(missing)\n\nKeep working toward the goal: \(goal.condition)"
                )
        }
    }
}
