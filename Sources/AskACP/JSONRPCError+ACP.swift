internal import AemiJSONRPC

/// The errors ACP v1 names (Errors), with the words ask says them in.
extension JSONRPCError {
    /// A request other than `initialize` arrived before it: -32600.
    static func notInitialized(_ method: String) -> JSONRPCError {
        JSONRPCError(code: invalidRequest, message: "Invalid request: \(method) before initialize")
    }

    /// A method ask does not implement, or one behind a capability it did not advertise: -32601.
    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: methodNotFound, message: "Method not found: \(method)")
    }

    /// Parameters that are malformed or hold a value ask does not support: -32602.
    static func invalidParams(_ reason: String) -> JSONRPCError {
        JSONRPCError(code: invalidParams, message: "Invalid params: \(reason)")
    }
}
