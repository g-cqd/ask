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

    /// What differs from bash enough to break a command written for it: zsh stops the whole command at a glob that matches nothing.
    private static func note(_ shell: String) -> String {
        (shell as NSString).lastPathComponent == "zsh"
            ? "; a glob that matches nothing aborts the command, so quote it" : ""
    }
}
