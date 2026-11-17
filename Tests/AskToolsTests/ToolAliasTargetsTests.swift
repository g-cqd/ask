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

    /// A permission pattern (`Bash(*)`) and a server's tool (`mcp__server__tool`) name no tool of ask's: they would otherwise be read
    /// as the bare word they contain, and restrict or match something they do not mean.
    @Test func `a pattern, or a server's tool, is no spelling of one of ask's`() {
        let table = ToolAliasTable.standard
        #expect(table.lookup("Bash") == "bash", "a spelling is read")
        for name in ["Bash(*)", "Read*", "mcp__docs__read", "mcp__bash"] {
            #expect(table.lookup(name) == nil, "\(name)")
        }
    }

    @Test func `every tool the table names is one a model is offered, or one known not to be built`() {
        let offered = Set(ToolDescriptionsTests.declared.map(\.name))
        let unknown = ToolAliasTable.standard.tools.subtracting(offered).subtracting(Self.notBuilt).sorted()
        #expect(unknown.isEmpty, "the table names tools no model is offered: \(unknown)")
        let built = Self.notBuilt.intersection(offered).sorted()
        #expect(built.isEmpty, "built now, so no longer an exception: \(built)")
    }
}
