/// The reference `run.stop` hook (roadmap 0192): when a run that changed things would end, it runs the configured check (`hooks.check`,
/// such as `swift test`) and sends a failure back, so the model fixes it; the run then goes on within `hooks.maxContinues`. A pass, a
/// check that did not finish, or a run that changed nothing since the last stop lets the run end.
public struct CheckHook: AgentHook {
    public let name = "check"
    /// The command, as the person wrote it.
    let command: String
    /// Runs it.
    let run: @Sendable () async -> CheckOutcome

    /// The most of a failure's output sent back: its end, where a failure is said.
    static let keptCharacters = 8_000

    public init(command: String, run: @escaping @Sendable () async -> CheckOutcome) {
        self.command = command
        self.run = run
    }

    public func runStop(_ stop: RunStop) async -> RunStopDecision {
        guard stop.changed else { return .stop }
        guard case .failed(let output) = await run() else { return .stop }
        let kept = output.count > Self.keptCharacters ? "…\n" + output.suffix(Self.keptCharacters) : output
        return .continue(
            "The check `\(command)` failed. Fix what it reports, then finish; it runs again when you do.\n\n\(kept)"
        )
    }
}
