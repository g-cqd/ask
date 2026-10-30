import AskMCP
import Testing

/// The rule itself, as the MCP spec (2025-06-18) defines the hints: `readOnlyHint` defaults to false, `destructiveHint` to true, and
/// `destructiveHint` means something only for a tool that is not read-only.
@Suite("Which annotations need the person's approval")
struct MCPAnnotationApprovalTests {
    @Test func `only a read-only tool, or one that says it is not destructive, goes unasked`() {
        #expect(MCPToolAnnotations().needsApproval)
        #expect(MCPToolAnnotations(destructive: true).needsApproval)
        #expect(MCPToolAnnotations(readOnly: false).needsApproval)
        #expect(!MCPToolAnnotations(readOnly: true).needsApproval)
        #expect(
            !MCPToolAnnotations(readOnly: true, destructive: true).needsApproval,
            "a read-only tool's destructive hint means nothing")
        #expect(!MCPToolAnnotations(destructive: false).needsApproval)
    }
}
