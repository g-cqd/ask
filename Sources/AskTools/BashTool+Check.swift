internal import AemiJSON
public import AskAI
public import AskAgentCore

/// The check hook's command as a `bash` call (roadmap 0192): so it runs in the session's sandbox, shell and environment, and is cut
/// and stopped as any command is.
extension BashTool {
    /// The call's input: the command, and its deadline in seconds.
    public static func checkInput(command: String, seconds: Int) -> JSONObject? {
        guard
            let bytes = try? AemiJSON.JSONEncoder().encodeToBytes(CheckCall(command: command, timeout_seconds: seconds))
        else {
            return nil
        }
        return try? JSONObject(validating: bytes)
    }

    /// How the check ended, from the call's output.
    public static func checkOutcome(of output: ToolOutput) -> CheckOutcome {
        guard output.isError else { return .passed }
        let text = output.content
        if text.hasPrefix(startFailure) || text.hasSuffix(abortedMark) || text.contains(timedOutMark) {
            return .unfinished
        }
        return .failed(text)
    }

    private struct CheckCall: Encodable {
        let command: String
        // swiftlint:disable:next identifier_name
        let timeout_seconds: Int
    }
}
