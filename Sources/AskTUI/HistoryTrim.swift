/// How much of the conversation the screen keeps (`ui.historyLimit`, note n29; the owner, 2026-11-06 and 2026-11-11): all of it by
/// default; past `limit` blocks the oldest leave the screen and its memory, each left as an empty ``Transcript/Item/trimmed`` so no
/// block's place changes, and the newest of them says how many are gone. A block still going stays. The session file keeps everything,
/// so the model and a resume lose nothing.
struct HistoryTrim: Sendable, Equatable {
    /// The most blocks kept; nil for all of them.
    var limit: Int?
    /// How many blocks have left.
    var trimmed = 0
    /// The newest block that left, which draws the line saying how many did.
    var boundary: Int?
    /// Where the next look for a block to let go starts.
    var next = 0

    /// The line the newest block that left draws.
    static func notice(_ count: Int) -> String {
        "\(count) earlier \(count == 1 ? "block is" : "blocks are") not shown (ui.historyLimit)"
    }
}
