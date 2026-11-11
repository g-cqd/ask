import Testing

@testable import AskAgentCore

/// `ui.historyLimit` (note n29; the owner, 2026-11-06): how many blocks the screen keeps; unlimited by default, `null` to say so over
/// a lower file's limit.
@Suite("ui.historyLimit is a number of blocks, or null for all of them")
struct HistoryLimitConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `a number, or null, read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"historyLimit": 2000}"#))
        #expect(section.historyLimit == 2000 && section.description == "historyLimit 2000")
        let unlimited = try #require(try ui(#"{"historyLimit": null}"#))
        #expect(unlimited.historyLimit == UISection.noHistoryLimit && unlimited.value(forKey: "historyLimit") == "null")
        #expect(
            section.layered(with: unlimited).historyLimit == UISection.noHistoryLimit,
            "null undoes a lower file's limit"
        )
        #expect(section.layered(with: UISection()).historyLimit == 2000)
        #expect(UISection.keys.contains("historyLimit"))
    }

    @Test func `what is not a whole number of 1 or more is refused`() {
        for json in [
            #"{"historyLimit": 0}"#, #"{"historyLimit": -5}"#, #"{"historyLimit": "lots"}"#, #"{"historyLimit": 1.5}"#
        ] {
            #expect(throws: (any Error).self, "\(json)") { try ui(json) }
        }
    }

    @Test func `it is in the catalog, unlimited by default`() throws {
        let row = try #require(SettingCatalog.all.first { $0.path == ["ui", "historyLimit"] })
        #expect(row.defaultValue == "null")
    }
}
