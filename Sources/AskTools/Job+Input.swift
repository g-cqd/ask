internal import AskAgentCore

extension Job {
    /// Shared input/EOF contract for the consolidated and legacy library tools.
    func sendInput(_ text: String?, closing: Bool) throws(ToolFailure) {
        if let text, !write(Array(text.utf8)) {
            throw ToolFailure("\(id) does not take input: \(status == .running ? "input is closed" : "it ended").")
        }
        if closing { closeInput() }
    }
}
