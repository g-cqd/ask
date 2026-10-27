internal import AskAgentCore
internal import Foundation
internal import Synchronization

extension AgentConversation {
    /// A command tied to this workspace and exact session path, with shell-safe argument boundaries.
    func printResumeCommand() {
        guard let path = session.withLock({ $0?.path }) else { return }
        let arguments = ["ask", "--resume", path] + source.flags.arguments
        func quote(_ argument: String) -> String {
            "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        print("Session saved to \(path)")
        print("To resume: cd \(quote(source.workspace)); \(arguments.map(quote).joined(separator: " "))")
    }
}
