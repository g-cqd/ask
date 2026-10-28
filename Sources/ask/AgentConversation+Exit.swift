internal import AskAgentCore
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// A command tied to this workspace and exact session path, with shell-safe argument boundaries.
    func printResumeCommand() {
        guard let path = session.withLock({ $0?.path }) else { return }
        let home = NSHomeDirectory()
        let displayPath = PathDisplay.tilde(path, home: home)
        let linked = PathDisplay.link(to: path, display: displayPath)
        let workspace = PathDisplay.shellArgument(source.workspace, home: home)
        let sessionArg = PathDisplay.shellArgument(path, home: home)
        let flags = source.flags.arguments.map { PathDisplay.shellArgument($0, home: home) }
        let command = (["ask", "--resume", sessionArg] + flags).joined(separator: " ")
        print("Session saved to \(linked)")
        print("To resume: cd \(workspace); \(command)")
    }
}
