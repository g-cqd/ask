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
        let arguments = [source.workspace, path] + source.flags.arguments
        guard !arguments.contains(where: PathDisplay.hasControl) else {
            print("Session saved to \(linked)")
            print(
                "No resume command is printed: a path or flag holds a control character. Use ask --resume with the session file."
            )
            return
        }
        let workspace = PathDisplay.shellArgument(source.workspace, home: home)
        let sessionArg = PathDisplay.shellArgument(path, home: home)
        let flags = source.flags.arguments.map { PathDisplay.shellArgument($0, home: home) }
        let command = (["ask", "--resume", sessionArg] + flags).joined(separator: " ")
        print("Session saved to \(linked)")
        print("To resume: cd \(workspace); \(command)")
    }
}
