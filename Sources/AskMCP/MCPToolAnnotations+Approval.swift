extension MCPToolAnnotations {
    /// Whether a call needs the person's approval (security audit 2026-10-29, finding 4): unless the server says the tool is read-only,
    /// or that it is not destructive. The MCP spec (2025-06-18) defaults `readOnlyHint` to false and `destructiveHint` to true, so a tool
    /// with no annotations may destroy or overwrite, and is asked about.
    public var needsApproval: Bool { readOnly != true && destructive != false }
}
