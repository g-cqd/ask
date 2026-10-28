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
    /// Measured 11.06 ms median, 13.77 p95 on an idle machine. Set at 25 ms, then raised to 50 ms by the owner
    /// (ADR-0122), who asked that every budget check run with the machine loaded: under load the median was 27 to
    /// 45 ms (roadmap 0054, 0079), so 25 ms measured idle-machine luck, not what a person feels.
    public static let coldStartMilliseconds: Double = 50

    /// Resident memory once the prompt is up and the process is idle, in mebibytes.
    ///
    /// Measured 5,712 KiB median with a 32 KiB spread when the budget was first set at 8 MiB, over a program with no
    /// agent in it. With the loop, providers, tools and the full-screen interface the median is about 9 MiB, so the
    /// 8 MiB limit was exceeded for a long time and reported nothing useful. The owner raised it to 24 MiB
    /// (ADR-0038). It is a ceiling that catches a regression, not a statement that 24 MiB is wanted: a change that
    /// adds memory still needs its before and after numbers.
    public static let idleMemoryMebibytes: Int = 24

    /// One byte written to the terminal to its echo reaching the output stream, in milliseconds.
    ///
    /// Measured 0.12 ms median, 0.23 max. Budget set at 2 ms. It is two orders of magnitude inside
    /// what a person can perceive, which is the point: the budget exists to catch a regression that
    /// reintroduces a round trip through the allocator, not to describe what is already imperceptible.
    public static let inputDelayMilliseconds: Double = 2

    /// One action to its visible result, in milliseconds: the model's tool call fully received to the frame showing
    /// that tool finished, for a tool that runs in process (`read` of a small file). It is ask's own work between
    /// the model asking and the user seeing: parsing the stream, recording the response and the result, running the
    /// tool, drawing (ADR-0053).
    ///
    /// Measured 2.5–2.9 ms median, 3.1 ms p95, the same fresh and after 500 turns. The next request leaves about
    /// 1.5 ms later (4.0–4.5 ms, growing slightly with history). A sandboxed `bash` command adds its spawn,
    /// about 16 ms in all. Budget set at 5 ms.
    public static let actionToActionMilliseconds: Double = 5

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
