internal import Foundation
internal import Testing

@testable import AskAI

/// A tool declares its input as properties, and the schema the model reads is derived from them.
///
/// Each expected string is the JSON the builder must produce for its shape: required and optional properties,
/// bounds on either side, a minimum length, a name that needs escaping. The real tools' schemas, which used to
/// be written by hand, are pinned byte for byte in `ToolDefinitionTests`.
@Suite("A tool's input schema is built from its properties")
struct ToolSchemaTests {
    private func schema(_ definition: ToolDefinition) -> String {
        String(decoding: definition.inputSchema.bytes, as: UTF8.self)
    }

    @Test func `required string and optional bounded integers`() {
        let definition = ToolDefinition(name: "search", description: "Search.") {
            ToolProperty.integer("page", minimum: 1)
            ToolProperty.string("query").optional
            ToolProperty.integer("take", minimum: 1).optional
        }
        #expect(
            schema(definition)
                == #"""
                {"type":"object","properties":{"page":{"type":"integer","minimum":1},"query":{"type":"string"},\#
                "take":{"type":"integer","minimum":1}},"required":["page"]}
                """#
                .replacingOccurrences(of: "\n", with: "")
        )
    }

    @Test func `every property required keeps declaration order`() {
        let definition = ToolDefinition(name: "rename", description: "Rename.") {
            ToolProperty.string("from")
            ToolProperty.string("to")
        }
        #expect(
            schema(definition)
                == #"{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"}},"required":["from","to"]}"#
        )
    }

    @Test func `a string can have a minimum length and a boolean is optional`() {
        let definition = ToolDefinition(name: "tag", description: "Tag.") {
            ToolProperty.string("target")
            ToolProperty.string("label", minLength: 1)
            ToolProperty.boolean("force").optional
        }
        #expect(
            schema(definition)
                == #"""
                {"type":"object","properties":{"target":{"type":"string"},"label":{"type":"string","minLength":1},\#
                "force":{"type":"boolean"}},"required":["target","label"]}
                """#
                .replacingOccurrences(of: "\n", with: "")
        )
    }

    @Test func `an integer can be bounded on both sides`() {
        let definition = ToolDefinition(name: "wait", description: "Wait.") {
            ToolProperty.string("reason")
            ToolProperty.integer("seconds", minimum: 1, maximum: 60).optional
        }
        #expect(
            schema(definition)
                == #"""
                {"type":"object","properties":{"reason":{"type":"string"},\#
                "seconds":{"type":"integer","minimum":1,"maximum":60}},"required":["reason"]}
                """#
                .replacingOccurrences(of: "\n", with: "")
        )
    }

    @Test func `no required property omits the required list`() {
        let definition = ToolDefinition(name: "x", description: "x") { ToolProperty.boolean("flag").optional }
        #expect(schema(definition) == #"{"type":"object","properties":{"flag":{"type":"boolean"}}}"#)
    }

    @Test func `a name that needs escaping is escaped`() {
        let definition = ToolDefinition(name: "x", description: "x") { ToolProperty.string("a\"b") }
        #expect(schema(definition) == #"{"type":"object","properties":{"a\"b":{"type":"string"}},"required":["a\"b"]}"#)
        #expect((try? JSONObject(validating: definition.inputSchema.bytes)) != nil)
    }

    @Test func `a property says what it is last, required or not, and what it says is escaped`() {
        let definition = ToolDefinition(name: "x", description: "x") {
            ToolProperty.string("path", minLength: 1).described("The file.")
            ToolProperty.integer("limit", minimum: 1).described(#"How many "lines"."#).optional
            ToolProperty.boolean("all").optional.described("Every one.")
        }
        let expected = #"""
            {"type":"object","properties":{"path":{"type":"string","minLength":1,"description":"The file."},\#
            "limit":{"type":"integer","minimum":1,"description":"How many \"lines\"."},\#
            "all":{"type":"boolean","description":"Every one."}},"required":["path"]}
            """#
            .replacingOccurrences(of: "\n", with: "")
        #expect(schema(definition) == expected)
        #expect((try? JSONObject(validating: definition.inputSchema.bytes)) != nil)
    }

    @Test
    func `a schema written as given says what it is before its closing brace, and one that says nothing is as given`() {
        let raw = #"{"type":"array","items":{"type":"number"}}"#
        let definition = ToolDefinition(name: "x", description: "x") {
            ToolProperty.schema("at", raw).described("The seconds.").optional
            ToolProperty.schema("plain", raw).optional
        }
        let expected = #"""
            {"type":"object","properties":{\#
            "at":{"type":"array","items":{"type":"number"},"description":"The seconds."},\#
            "plain":{"type":"array","items":{"type":"number"}}}}
            """#
            .replacingOccurrences(of: "\n", with: "")
        #expect(schema(definition) == expected)
    }

    @Test func `a field says what it is last, at any depth, and one that says nothing adds nothing`() {
        let definition = ToolDefinition(
            name: "x",
            description: "x",
            fields: [
                .init(
                    "changes",
                    .array(.object([.init("op", .choice(["add"]), "What to do."), .init("id", .string())])),
                    "In order."
                ),
                .init("limit", .integer(minimum: 1), "At most this many.")
            ]
        )
        let expected = #"""
            {"type":"object","properties":{"changes":{"type":"array","items":{"type":"object","properties":{\#
            "op":{"enum":["add"],"description":"What to do."},"id":{"type":"string"}}},"description":"In order."},\#
            "limit":{"type":"integer","minimum":1,"description":"At most this many."}}}
            """#
            .replacingOccurrences(of: "\n", with: "")
        #expect(schema(definition) == expected)
    }
}
