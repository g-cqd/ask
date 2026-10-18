internal import AemiJSON
internal import AskAI

/// Decoded arguments, or the error output that explains why they could not be decoded.
public enum ToolArguments<Value> {
    case success(Value)
    case failure(ToolOutput)
}
