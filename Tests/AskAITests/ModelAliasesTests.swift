internal import Foundation
internal import Testing

@testable import AskAI

/// A connection's aliases are the user's words for a server's models. They never replace a model the server lists, never point at
/// each other, and never silently change which model a request names.
struct ModelAliasesTests {
    private func aliases(_ pairs: [(String, String)] = [("fast", "gpt-6-luna")]) throws -> ModelAliases {
        var value = ModelAliases()
        for (name, model) in pairs { try value.set(name, to: model) }
        return value
    }

    @Test func `an alias resolves to its model, with the limits the user stated`() throws {
        var value = ModelAliases()
        try value.set("fast", to: "gpt-6-luna", contextWindow: 8000, maxOutputTokens: 1000)
        let choice = try value.choice(requested: "fast", catalog: [])
        #expect(choice == ModelChoice(model: "gpt-6-luna", alias: "fast", contextWindow: 8000, maxOutputTokens: 1000))
    }

    @Test func `names are lower-cased, so Fast and FAST are the alias fast`() throws {
        var value = ModelAliases()
        try value.set("Fast", to: "gpt-6-luna")
        let value5 = try value.choice(requested: "fast", catalog: [])?.model
        #expect(value5 == "gpt-6-luna")
        let value6 = try value.choice(requested: "FAST", catalog: [])?.model
        #expect(value6 == "gpt-6-luna")
        #expect(value.aliases.keys.sorted() == ["fast"])
    }

    @Test func `a server id passes through unchanged, even one nothing lists`() throws {
        let value = try aliases()
        let value7 = try value.choice(requested: "gpt-6-sol", catalog: [])
        #expect(value7 == ModelChoice(model: "gpt-6-sol"))
        #expect(
            try value.choice(requested: "Some-Other.Model_1", catalog: []) == ModelChoice(model: "Some-Other.Model_1"))
    }

    @Test func `the default is used when nothing is asked for, whether it is an alias or a server id`() throws {
        var value = try aliases()
        let value8 = try value.choice(requested: nil, catalog: [])
        #expect(value8 == nil, "no request and no default is nothing")
        try value.setDefault("fast")
        let value9 = try value.choice(requested: nil, catalog: [])?.alias
        #expect(value9 == "fast")
        let value10 = try value.choice(requested: nil, catalog: [])?.model
        #expect(value10 == "gpt-6-luna")
        try value.setDefault("gpt-6-sol")
        let value11 = try value.choice(requested: nil, catalog: [])
        #expect(value11 == ModelChoice(model: "gpt-6-sol"))
        try value.setDefault(nil)
        let value12 = try value.choice(requested: nil, catalog: [])
        #expect(value12 == nil)
    }

    @Test func `an explicit request beats the default`() throws {
        var value = try aliases([("fast", "gpt-6-luna"), ("deep", "gpt-6-sol")])
        try value.setDefault("fast")
        let value13 = try value.choice(requested: "deep", catalog: [])?.model
        #expect(value13 == "gpt-6-sol")
    }

    @Test func `an alias that is also a model on the account is ambiguous, but only once the catalog is known`() throws
    {
        var value = ModelAliases()
        try value.set("gpt-6-sol", to: "gpt-6-luna")
        let value14 = try value.choice(requested: "gpt-6-sol", catalog: [])?.model
        #expect(value14 == "gpt-6-luna")
        #expect(throws: ModelAliasError.ambiguous("gpt-6-sol")) {
            try value.choice(requested: "gpt-6-sol", catalog: [CatalogModel(id: "gpt-6-sol")])
        }
    }

    @Test func `an alias cannot be made for a model the account lists`() {
        var value = ModelAliases()
        #expect(throws: ModelAliasError.shadowsModel("gpt-6-sol")) {
            try value.set("gpt-6-sol", to: "gpt-6-luna", known: ["gpt-6-sol"])
        }
        #expect(value.aliases.isEmpty)
    }

    @Test func `an alias cannot name itself or another alias, and a hand-edited chain is refused when used`() throws {
        var value = try aliases()
        #expect(throws: ModelAliasError.selfReference("loop")) { try value.set("loop", to: "loop") }
        #expect(throws: ModelAliasError.chained("deep")) { try value.set("deep", to: "fast") }
        let chained = try JSONDecoder()
            .decode(
                ModelAliases.self,
                from: Data(#"{"version":1,"aliases":{"a":{"model":"b"},"b":{"model":"gpt-x"}}}"#.utf8))
        #expect(throws: ModelAliasError.chained("a")) { try chained.choice(requested: "a", catalog: []) }
    }

    @Test(arguments: ["", " ", "bad name", "../escape", "a/b", "-lead", ".lead", "é", String(repeating: "a", count: 65)]
    )
    func `a name that is not a plain word is refused`(_ name: String) {
        var value = ModelAliases()
        #expect(throws: ModelAliasError.invalidName) { try value.set(name, to: "gpt-6-luna") }
        #expect(value.aliases.isEmpty)
    }

    @Test(arguments: ["", "has space", "-lead", "a/b", "é", String(repeating: "m", count: 129)])
    func `a model id that is not a plain id is refused, as an alias target and as a default`(_ model: String) {
        var value = ModelAliases()
        #expect(throws: ModelAliasError.invalidModel) { try value.set("fast", to: model) }
        #expect(throws: ModelAliasError.invalidModel) { try value.setDefault(model) }
    }

    @Test(arguments: [0, -1])
    func `a stated limit must be positive`(_ limit: Int) {
        var value = ModelAliases()
        #expect(throws: ModelAliasError.invalidLimit) { try value.set("fast", to: "m", contextWindow: limit) }
        #expect(throws: ModelAliasError.invalidLimit) { try value.set("fast", to: "m", maxOutputTokens: limit) }
    }

    @Test func `a connection keeps at most 64 aliases, and replacing one at the limit is allowed`() throws {
        var value = ModelAliases()
        for index in 0 ..< ModelAliases.limit { try value.set("a\(index)", to: "model-\(index)") }
        #expect(throws: ModelAliasError.tooMany) { try value.set("one-too-many", to: "m") }
        try value.set("a0", to: "replaced")
        #expect(value.aliases["a0"]?.model == "replaced")
        #expect(value.aliases.count == ModelAliases.limit)
    }

    @Test func `removing an alias removes it, and refuses one that is the default or that does not exist`() throws {
        var value = try aliases([("fast", "gpt-6-luna"), ("deep", "gpt-6-sol")])
        try value.setDefault("fast")
        #expect(throws: ModelAliasError.isDefault("fast")) { try value.remove("fast") }
        #expect(throws: ModelAliasError.notFound("nope")) { try value.remove("nope") }
        try value.remove("deep")
        #expect(value.aliases.keys.sorted() == ["fast"])
    }

    @Test func `the file format is stable and carries its version`() throws {
        var value = ModelAliases()
        try value.set("fast", to: "gpt-6-luna")
        try value.setDefault("fast")
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(
            text.contains(#""version":1"#) && text.contains(#""default":"fast""#)
                && text.contains(#""model":"gpt-6-luna""#))
        #expect(try JSONDecoder().decode(ModelAliases.self, from: Data(text.utf8)) == value)
    }
}
