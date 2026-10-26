internal import AskAI
internal import Foundation
internal import FoundationModels
internal import Testing

@testable import AskApple

/// A tool's JSON Schema as the framework's generation schema: arguments are produced under constraint, and what a small model cannot use is left out.
@Suite("A tool's schema becomes a generation schema the model fills under constraint")
struct AppleToolSchemaTests {
    private func schema(_ json: String) -> GenerationSchema? {
        AppleToolSchema.schema(
            named: "read", description: "Read a file. Second sentence.", inputSchema: Array(json.utf8))
    }

    @Test func `scalars, arrays, enums, nested objects and optional properties are all expressible`() {
        let json = """
            {"type":"object","required":["path"],"properties":{
              "path":{"type":"string","description":"The file."},
              "offset":{"type":["integer","null"]},"ratio":{"type":"number"},"flag":{"type":"boolean"},
              "mode":{"enum":["a","b"]},"names":{"type":"array","items":{"type":"string"}},
              "box":{"type":"object","properties":{"x":{"type":"integer"}}}}}
            """
        #expect(schema(json) != nil)
    }

    @Test func `a schema that is not an object is not offered`() {
        #expect(schema("[1,2]") == nil && schema("not json") == nil)
    }

    @Test func `a tool with no properties is still a tool`() { #expect(schema(#"{"type":"object"}"#) != nil) }

    @Test
    func `the sandbox argument every tool takes is offered like any other, so this model has what the others have`()
        throws
    {
        let with =
            #"{"type":"object","properties":{"path":{"type":"string"},"sandbox":{"type":"object","properties":{"network":{"type":"string"}}}}}"#
        let without = #"{"type":"object","properties":{"path":{"type":"string"}}}"#
        let a = try #require(schema(with))
        let b = try #require(schema(without))
        #expect(String(describing: a) != String(describing: b))
    }

    @Test func `a brief description is its first sentence, shortened, and a full one keeps every sentence`() {
        #expect(
            AppleToolSchema.clipped("Read a file. Second sentence.", limit: AppleToolSchema.Detail.brief.limit)
                == "Read a file")
        #expect(
            AppleToolSchema.clipped("Read a file. Second sentence.", limit: AppleToolSchema.Detail.full.limit)
                == "Read a file. Second sentence.")
        #expect(AppleToolSchema.clipped(String(repeating: "w", count: 300))?.count == 120)
        #expect(AppleToolSchema.clipped("") == nil && AppleToolSchema.clipped(nil) == nil)
    }

    @Test func `a tool's cost counts its name, description and every argument, and a brief description costs less`()
        throws
    {
        let long = String(repeating: "A long sentence about the tool. ", count: 12)
        let definition = ToolDefinition(
            name: "read", description: long,
            inputSchema: try JSONObject(
                validating: Array(
                    #"{"type":"object","properties":{"path":{"type":"string","description":"The path."}}}"#.utf8)))
        #expect(
            AppleToolSchema.footprint(of: definition, detail: .full)
                > AppleToolSchema.footprint(of: definition, detail: .brief))
        #expect(AppleToolSchema.footprint(of: definition, detail: .brief) > "read".count)
    }
}
