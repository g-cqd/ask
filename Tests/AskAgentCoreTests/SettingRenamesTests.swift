internal import AemiJSON
internal import Testing

@testable import AskAgentCore

/// The names roadmap 0154 settled: a file written with the old ones still loads, the old names read as the new ones, and the person is
/// told the new name once per old one.
@Suite("Old setting names read as the new ones")
struct SettingRenamesTests {
    private func renamed(_ text: String) throws -> (value: JSONValue, notices: [String]) {
        let document = try AemiJSON.parse(Array(text.utf8), options: JSONParseOptions(validation: .json5))
        return try SettingRenames.apply(to: JSONValue(document.root))
    }

    private func json(_ text: String) throws -> JSONValue {
        JSONValue(try AemiJSON.parse(Array(text.utf8), options: JSONParseOptions(validation: .json5)).root)
    }

    @Test func `a plain rename keeps the value and says the new name`() throws {
        let result = try renamed(#"{"ui": {"promptRows": 4, "prompt": "> "}}"#)
        #expect(result.value == (try json(#"{"ui": {"inputRows": 4, "inputPrefix": "> "}}"#)))
        #expect(result.notices.count == 2)
        #expect(result.notices.contains { $0.contains("ui.promptRows") && $0.contains("ui.inputRows") })
    }

    @Test func `the fold switches move under ui.fold as booleans`() throws {
        let result = try renamed(#"{"ui": {"tools": "open", "thinking": "folded", "codeFoldLines": 30}}"#)
        #expect(result.value == (try json(#"{"ui": {"fold": {"tools": false, "thinking": true, "codeLines": 30}}}"#)))
    }

    @Test func `values that change words are translated`() throws {
        #expect(
            try renamed(#"{"ui": {"localizedDurations": "off"}}"#).value
                == (try json(#"{"ui": {"durations": "clock"}}"#)))
        #expect(
            try renamed(#"{"ui": {"localizedDurations": true}}"#).value
                == (try json(#"{"ui": {"durations": "words"}}"#)))
        #expect(
            try renamed(#"{"ui": {"onlyUsefulModels": "off"}}"#).value
                == (try json(#"{"ui": {"listAllModels": true}}"#)))
        #expect(try renamed(#"{"ui": {"timeout": "never"}}"#).value == (try json(#"{"ui": {"showTimeout": "never"}}"#)))
        #expect(
            try renamed(#"{"approvals": {"scope": "narrowing-only"}}"#).value
                == (try json(#"{"approvals": {"remember": "narrowing"}}"#)))
    }

    @Test func `the two confirmation switches become the keys pressed twice`() throws {
        #expect(
            try renamed(
                #"{"ui": {"escapeInterruptRequiresConfirmation": "off", "abortTurnRequiresConfirmation": "on"}}"#
            )
            .value
                == (try json(#"{"ui": {"stopTwice": ["ctrl-c"]}}"#)))
        #expect(
            try renamed(#"{"ui": {"abortTurnRequiresConfirmation": true}}"#).value
                == (try json(#"{"ui": {"stopTwice": ["esc", "ctrl-c"]}}"#)), "esc keeps its default, on")
    }

    @Test func `keepAwake's display becomes its own switch`() throws {
        #expect(
            try renamed(#"{"keepAwake": "display"}"#).value
                == (try json(#"{"keepAwake": "working", "keepDisplayAwake": true}"#)))
        #expect(try renamed(#"{"keepAwake": "system"}"#).value == (try json(#"{"keepAwake": "working"}"#)))
        #expect(
            try renamed(#"{"keepAwake": "always"}"#).notices.isEmpty, "a value that did not change is not an old name")
    }

    @Test func `the sandbox's exceptions and the skills' count are renamed`() throws {
        let result = try renamed(
            #"{"sandbox": {"denyRead": ["~/a"], "allowRead": ["~/b"], "allowWrite": ["~/c"]}, "skills": {"maxAdvertised": 8}}"#
        )
        #expect(
            result.value
                == (try json(
                    #"{"sandbox": {"hide": ["~/a"], "readable": ["~/b"], "writable": ["~/c"]}, "skills": {"maxListed": 8}}"#
                )))
    }

    @Test func `a new name wins over its old one, and the old one is reported as ignored`() throws {
        let result = try renamed(#"{"ui": {"promptRows": 4, "inputRows": 9}}"#)
        #expect(result.value == (try json(#"{"ui": {"inputRows": 9}}"#)))
        #expect(result.notices.count == 1 && result.notices[0].contains("ignored"))
    }

    @Test func `a file without old names is left as it is`() throws {
        let text = #"{"model": "m", "ui": {"inputRows": 3, "fold": {"code": false}}, "keepAwake": "working"}"#
        let result = try renamed(text)
        #expect(result.value == (try json(text)) && result.notices.isEmpty)
    }
}
