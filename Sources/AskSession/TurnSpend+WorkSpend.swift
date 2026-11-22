internal import AskAgentCore
internal import AskTUI

extension TurnSpend {
    /// `spend` as the screen says it, in whole seconds: a turn's on the status line, a done task's in its line (roadmap 0239).
    init(_ spend: WorkSpend) {
        let seconds = { (milliseconds: Int) in Int64(milliseconds / 1_000) }
        self.init(
            requests: spend.requests,
            toolCalls: spend.toolCalls,
            tokens: spend.compactTokens,
            seconds: spend.wallMilliseconds.map(seconds),
            toolSeconds: spend.toolMilliseconds.map(seconds)
        )
    }
}
