import AskAI
import Testing

@testable import AskAgentCore
@testable import AskTools

/// ADR-0160: a file written for another harness names its tools, and the table says which of ask's each means. A row for a
/// tool nobody is offered answers with a name that restricts nothing and matches nothing.
@Suite("Another harness's tool name means a tool ask offers")
struct ToolAliasTargetsTests {
    /// Named in real harness files, and not built: a file written for them is understood the day they exist.
    private static let notBuilt: Set<String> = ["grep", "find", "ls"]

    @Test func `every tool the table names is one a model is offered, or one known not to be built`() {
        let offered = Set(ToolDescriptionsTests.declared.map(\.name))
        let unknown = ToolAliasTable.standard.tools.subtracting(offered).subtracting(Self.notBuilt).sorted()
        #expect(unknown.isEmpty, "the table names tools no model is offered: \(unknown)")
        let built = Self.notBuilt.intersection(offered).sorted()
        #expect(built.isEmpty, "built now, so no longer an exception: \(built)")
    }
}
