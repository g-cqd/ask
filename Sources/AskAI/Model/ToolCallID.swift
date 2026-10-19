/// Identifiers for tool calls a server sent without one.
enum ToolCallID {
    /// A call id unique enough that a session cannot match a result to the wrong call.
    static func generated() -> String {
        var random = SystemRandomNumberGenerator()
        return "call_" + String(random.next(), radix: 16)
    }
}
