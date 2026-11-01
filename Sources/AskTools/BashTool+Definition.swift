internal import AskAI
internal import AskAgentCore
internal import Foundation

extension BashTool {
    static func makeDefinition(shell: String) -> ToolDefinition {
        ToolDefinition(
            name: "bash",
            description:
                "Run commands using \(shell) (\((shell as NSString).lastPathComponent) syntax\(note(shell))); "
                + "the command to run goes in command, and shell names another shell's absolute path. "
                + "timeout_seconds: default 120, max 600. yield_seconds backgrounds; wait_for_output/port/file waits for readiness."
        ) {
            ToolProperty.string("command")
            ToolProperty.integer("timeout_seconds", minimum: 1, maximum: 600).optional
            // @dl:accept -- both tools intentionally expose the same readiness wire constraints
            ToolProperty.integer("yield_seconds", minimum: 1, maximum: 600).optional
            ToolProperty.string("wait_for_output", minLength: 1).optional
            ToolProperty.integer("wait_for_port", minimum: 1, maximum: 65_535).optional
            ToolProperty.string("wait_for_file", minLength: 1).optional
            ToolProperty.string("shell").optional
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
