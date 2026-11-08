import Testing

@testable import AskAgentCore

/// `openers` (roadmap 0216, ADR-0148): read from the person's own file, refused in a project's, every rule an app or a command.
@Suite("openers are read from your own file only")
struct OpenersConfigurationTests {
    private func file(_ json: String, isProject: Bool = false) throws -> ConfigurationFile {
        try ConfigurationFile.parse(Array(#"{"openers": \#(json)}"#.utf8), path: "c.json", isProject: isProject)
    }

    @Test func `kinds and rules are read`() throws {
        let openers = try #require(
            try file(
                #"""
                {"file": "Xcode", "web": "Safari", "rules": [
                  {"match": {"extensions": ["md"], "kind": "file"}, "app": "Typora"},
                  {"match": {"pattern": "/work/.+\\.swift$"}, "command": ["code", "--goto", "{path}:{line}"]},
                  {"match": {"host": "github.com"}, "app": "Arc"}
                ]}
                """#
            )
            .openers
        )
        #expect(openers.file == "Xcode" && openers.web == "Safari" && openers.folder == nil)
        #expect(
            openers.rules == [
                OpenerRule(kind: .file, extensions: ["md"], app: "Typora"),
                OpenerRule(pattern: "/work/.+\\.swift$", command: ["code", "--goto", "{path}:{line}"]),
                OpenerRule(host: "github.com", app: "Arc")
            ]
        )
        #expect(
            OpenersSection(file: "A").layered(with: OpenersSection(web: "B")) == OpenersSection(file: "A", web: "B")
        )
    }

    @Test func `a project's file may not set openers`() {
        #expect(throws: ConfigurationError.self) { try file(#"{"file": "Xcode"}"#, isProject: true) }
    }

    @Test func `a rule needs exactly one of an app and a command, a command an argument, and a pattern must compile`() {
        for bad in [
            #"{"rules": [{"match": {"host": "a.com"}}]}"#,
            #"{"rules": [{"match": {"host": "a.com"}, "app": "X", "command": ["y"]}]}"#,
            #"{"rules": [{"match": {"host": "a.com"}, "command": []}]}"#,
            #"{"rules": [{"match": {"pattern": "(unclosed"}, "app": "X"}]}"#,
            #"{"rules": [{"match": {"kind": "socket"}, "app": "X"}]}"#,
            #"{"rules": [{"match": {"colour": "red"}, "app": "X"}]}"#
        ] {
            #expect(throws: ConfigurationError.self, "\(bad)") { try file(bad) }
        }
    }
}
