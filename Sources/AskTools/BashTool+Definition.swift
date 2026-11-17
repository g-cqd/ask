internal import AskAI
internal import AskAgentCore
internal import Foundation

extension BashTool {
    static func makeDefinition(shell: String) -> ToolDefinition {
        ToolDefinition(
            name: "bash",
            description: """
                Run a command in \(shell) (\((shell as NSString).lastPathComponent) syntax\(note(shell))) and return what it \
                printed, then [exit N].
                Each call starts in the working directory: a cd lasts for that command only. A command that does not parse is \
                refused; one shellcheck faults (ls | grep, cd without || exit, an unquoted $(…)) is refused once: fix it, or \
                send it again unchanged to run it as written. A server, a watcher or a long build goes on as a job when \
                yield_seconds or a wait_for is given: the job tool then waits for its end, writes to it and stops it. A \
                wait_for that has not happened by timeout_seconds stops the command.
                """
        ) {
            ToolProperty.string("command").described("What to run.")
            ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600)
                .described("Stop the command after this long: 120 unless given.").optional
            ToolProperty.integer("yield_seconds", minimum: 1, maximum: 600)
                .described("Return after this long; the command goes on as a job.").optional
            ToolProperty.string("wait_for_output", minLength: 1)
                .described("Return once it prints this text; it goes on as a job.").optional
            ToolProperty.integer("wait_for_port", minimum: 1, maximum: 65_535)
                .described("Return once this local port accepts connections; it goes on as a job.")
                .optional
            ToolProperty.string("wait_for_file", minLength: 1)
                .described("Return once this file exists; it goes on as a job.").optional
            ToolProperty.string("shell").described("Another shell for this command, by absolute path.").optional
            SandboxRequest.property
        }
    }

    /// What differs from the bash a model writes for enough to break a command: zsh stops the whole command at a glob that matches
    /// nothing; macOS's own bash is 3.2, without associative arrays, `mapfile`, `${var,,}` or `|&`.
    private static func note(_ shell: String) -> String {
        if (shell as NSString).lastPathComponent == "zsh" {
            return "; a glob that matches nothing aborts the command, so quote it"
        }
        if shell == "/bin/bash" { return " 3.2: no associative arrays, mapfile, ${var,,} or |&" }
        return ""
    }
}
