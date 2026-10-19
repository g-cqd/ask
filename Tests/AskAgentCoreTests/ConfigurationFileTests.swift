import Testing

@testable import AskAgentCore

/// A configuration file is JSON or JSON5, validated whole: a refused file names its path and, for syntax, the
/// line and column.
@Suite("Configuration files are JSON or JSON5, and refused whole when wrong")
struct ConfigurationFileTests {
    private func parse(_ text: String) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `plain JSON and JSON5 read the same`() throws {
        let json = try parse(#"{"model": "claude-sonnet-5-5", "maxTurns": 40, "compactAt": 100000}"#)
        let json5 = try parse(
            """
            // ask's settings
            {
              model: 'claude-sonnet-5-5',  /* the default */
              maxTurns: 40,
              compactAt: 100000,
            }
            """)
        #expect(json == ConfigurationFile(model: "claude-sonnet-5-5", maxTurns: 40, compactAt: 100_000))
        #expect(json5 == json)
        #expect(try parse("{}") == ConfigurationFile())
    }

    @Test func `a syntax error names the line and column`() {
        #expect(throws: ConfigurationError.self) { try parse("{\n  model: 'x',\n  maxTurns: ]\n}") }
        do {
            _ = try parse("{\n  model: 'x',\n  maxTurns: ]\n}")
        } catch {
            guard case .invalid(_, let line, let column, _) = error else {
                Issue.record("not a syntax error: \(error)")
                return
            }
            #expect(line == 3 && column == 13)
            #expect("\(error)" == "c.json:3:13: unexpected ']'")
        }
    }

    @Test func `a typo, a repeated key, a wrong type or a bad value refuses the file`() {
        #expect(throws: ConfigurationError.unknownKey(path: "c.json", key: "modle", known: ConfigurationFile.keys)) {
            try parse("{modle: 'x'}")
        }
        #expect(throws: ConfigurationError.self) { try parse("{maxTurns: 5, maxTurns: 6}") }
        #expect(throws: ConfigurationError.self) { try parse("{maxTurns: 'five'}") }
        #expect(throws: ConfigurationError.outOfRange(path: "c.json", key: "maxTurns", reason: "must be at least 1")) {
            try parse("{maxTurns: 0}")
        }
        #expect(throws: ConfigurationError.self) { try parse("{compactAt: -1}") }
    }
}
