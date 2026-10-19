/// The four budgets `ask` is held to, as numbers with units.
///
/// A baseline says where we are. Only a target makes a regression a *failure* rather than an
/// observation someone notices in a review six weeks later. These came from
/// `Scripts/measure-budgets.py` — median of 12 release runs on the development machine — and they
/// are deliberately set with headroom above what was measured, because a budget that the current
/// code cannot meet is a budget that gets raised on the first bad day rather than defended.
///
/// Re-measure before tightening, never after a regression.
///
/// SAFETY: `-Ounchecked` is deliberately NOT used. It would strip the bounds and overflow checks
/// that `StrictMemorySafety` relies on, trading correctness for a benchmark number. Performance in
/// `ask` comes from doing less work — diff rendering, pooled buffers — not from removing the checks
/// that catch the bugs.
public enum Budget {
    /// Process spawn to the first frame visible on the terminal, in milliseconds.
    ///
    /// Measured 11.06 ms median, 13.77 p95. Budget set at 25 ms: roughly 2x the median and above the
    /// p95 observed, so ordinary variance cannot fail the gate.
    public static let coldStartMilliseconds: Double = 25

    /// Resident memory once the prompt is up and the process is idle, in mebibytes.
    ///
    /// Measured 5,712 KiB median with a 32 KiB spread — remarkably tight, because an idle agent
    /// allocates nothing. Budget set at 8 MiB. This is the one budget that should never grow at all.
    public static let idleMemoryMebibytes: Int = 8

    /// One byte written to the terminal to its echo reaching the output stream, in milliseconds.
    ///
    /// Measured 0.12 ms median, 0.23 max. Budget set at 2 ms. It is two orders of magnitude inside
    /// what a person can perceive, which is the point: the budget exists to catch a regression that
    /// reintroduces a round trip through the allocator, not to describe what is already imperceptible.
    public static let inputDelayMilliseconds: Double = 2

    /// One action to its visible result, in milliseconds.
    ///
    /// Measured 0.05 ms — but read the caveat, because this number currently describes a trivial
    /// action. It measures Enter producing the next prompt in a program with no agent in it. When
    /// the agent loop lands, this budget has to be re-derived against a real action, and the stale
    /// number must not survive the change.
    public static let actionToActionMilliseconds: Double = 2

    /// Whether a measurement is inside budget.
    ///
    /// Nothing at run time calls this: `Scripts/measure-budgets.py` reads the limits from `ask --budgets` and
    /// compares them itself. It states the rule once in Swift, for the tests. (The comment here used to say the
    /// CI guard and `--budgets` call it; deadwood's `referenced-only-by-tests` found that was not true.)
    public static func isWithinBudget(
        coldStart: Double, idleMemoryMebibytes: Double, inputDelay: Double, action: Double
    ) -> Bool {
        coldStart <= Budget.coldStartMilliseconds
            && idleMemoryMebibytes <= Double(Budget.idleMemoryMebibytes)
            && inputDelay <= Budget.inputDelayMilliseconds
            && action <= Budget.actionToActionMilliseconds
    }
}
