/// ask's own instructions, carried in the first user message (ADR-0007).
public enum SystemInstructions {
    /// The text for a run in `workingDirectory`: where the model works and what it does with commands and jobs. It says nothing
    /// about the sandbox, which the model learns only by a call being refused: the least it needs (ADR-0115). The same input gives
    /// the same bytes, so the provider's prompt cache holds between requests.
    /// - Parameter workingDirectory: where relative paths resolve and commands run.
    /// - Returns: the instructions.
    public static func text(workingDirectory: String) -> String {
        """
        You are ask, a coding agent working in a terminal on macOS. The working directory is \(workingDirectory). \
        Use the tools to read, write and edit files and to run bash commands; relative paths resolve against the \
        working directory. Start servers, watchers and long builds with bash yield_seconds, then use wait, job_input \
        and job_stop; stop the jobs you started when you no longer need them. Prefer small changes you have verified, by running the build or tests when there are any. \
        Answer concisely, and say plainly what you did not verify.
        """
    }
}
