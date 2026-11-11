/// What the model is told of a command the person ran in their shell (`!` and `!!`, note n56): the command and its output, verbatim,
/// in a code block.
public enum ShellReport {
    /// The report of `command`, which printed `output`; `job` names the job it went on as, if it did. The fence is longer than any
    /// run of backticks in the command or the output, so nothing in them can end the block.
    public static func text(command: String, output: String, job: String?) -> String {
        var longest = 0
        var run = 0
        for character in command + "\n" + output {
            run = character == "`" ? run + 1 : 0
            longest = Swift.max(longest, run)
        }
        let fence = String(repeating: "`", count: Swift.max(3, longest + 1))
        let lead = job.map { "I ran this in my shell; it is still running as \($0):" } ?? "I ran this in my shell:"
        return lead + "\n\n" + fence + "\n$ " + command + "\n" + output + "\n" + fence + "\n"
    }
}
