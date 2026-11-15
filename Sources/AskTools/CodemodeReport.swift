internal import AskAgentCore
internal import AskCodemode
internal import Foundation

/// What the model reads of a script (ADR-0156): how it ended and how long it took, then what it said. The shape is pi's on
/// purpose: `Script completed` or `Script failed` first, several texts each headed `==> text N/M <==`, the console's lines last
/// in a block of their own.
enum CodemodeReport {
    static func text(_ result: CodemodeResult, took: Duration) -> String {
        let seconds = String(
            format: "%.2f",
            Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
        )
        var lines = [
            result.failure.map { "Script failed after \(seconds) s: \($0)" } ?? "Script completed in \(seconds) s."
        ]
        let said = result.items.filter { !$0.console }.map(\.text)
        for (index, text) in said.enumerated() {
            if said.count > 1 { lines.append("==> text \(index + 1)/\(said.count) <==") }
            lines.append(text)
        }
        let console = result.items.filter(\.console).map(\.text)
        if !console.isEmpty { lines += ["<console_output>"] + console + ["</console_output>"] }
        if result.items.isEmpty, result.failure == nil { lines.append("(no output)") }
        if result.unsettled == 1 {
            lines.append("[1 tool call was still running when the script ended, and was cancelled.]")
        } else if result.unsettled > 1 {
            lines.append(
                "[\(result.unsettled) tool calls were still running when the script ended, and were cancelled.]"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// `report` within `tokens` (about four bytes each): whole when it fits, else its start and its end around what was left
    /// out, and where the whole is when it was written to `whole`.
    static func fitted(_ report: String, tokens: Int, whole: String?) -> String {
        // Lines are not what is bounded here: more of them than any result has.
        let fitted = OutputCap(maximumLines: 1 << 40, maximumBytes: tokens * 4).apply(report)
        guard fitted != report, let whole else { return fitted }
        return fitted + "\n[The whole output is in \(whole).]"
    }
}
