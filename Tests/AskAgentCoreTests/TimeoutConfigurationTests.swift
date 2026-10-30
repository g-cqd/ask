import Testing

@testable import AskAgentCore

/// `ui.timeout` and `ui.timeoutLabel` in a configuration file (roadmap 0126): a choice of three, and a label of 1 to 8 characters.
@Suite("ui.timeout and ui.timeoutLabel (roadmap 0126)")
struct TimeoutConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `both are read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"showTimeout": "never", "timeoutLabel": "⏱"}"#))
        #expect(section.timeout == .never && section.timeoutLabel == "⏱")
        #expect(section.description == "showTimeout never, timeoutLabel \"⏱\"")
        #expect(section.value(forKey: "showTimeout") == "never" && section.value(forKey: "timeoutLabel") == "\"⏱\"")
        let layered = UISection(timeout: .always, timeoutLabel: "t").layered(with: UISection(timeout: .auto))
        #expect(layered.timeout == .auto && layered.timeoutLabel == "t")
        #expect(UISection.keys.contains("showTimeout") && UISection.keys.contains("timeoutLabel"))
        #expect(!UISection(timeout: .auto).isEmpty && !UISection(timeoutLabel: "t").isEmpty)
    }

    @Test func `what is not a choice or a short label is refused`() {
        for json in [
            #"{"timeout": "sometimes"}"#, #"{"timeout": true}"#, #"{"timeoutLabel": ""}"#,
            #"{"timeoutLabel": "much too long"}"#, #"{"timeoutLabel": "a\nb"}"#, #"{"timeoutLabel": "\u001b[31m"}"#
        ] {
            #expect(throws: (any Error).self, "\(json)") { try ui(json) }
        }
        #expect((try? ui(#"{"timeoutLabel": "12345678"}"#)) != nil, "8 characters is allowed")
    }
}
