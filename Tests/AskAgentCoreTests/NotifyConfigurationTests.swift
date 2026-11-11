import Testing

@testable import AskAgentCore

/// `ui.notify` (note n62; the owner's answers of 2026-11-11): off by default, a bell, or a notification through the terminal.
@Suite("ui.notify says how ask tells you it is done or waiting")
struct NotifyConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `it is read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"notify": "bell"}"#))
        #expect(section.notify == .bell)
        #expect(section.description == "notify bell")
        #expect(section.value(forKey: "notify") == "bell")
        var lower = UISection()
        lower.notify = .notification
        var upper = UISection()
        upper.notify = .off
        #expect(lower.layered(with: upper).notify == .off && lower.layered(with: UISection()).notify == .notification)
        #expect(UISection.keys.contains("notify") && !lower.isEmpty)
        #expect(NotifyPreference.allCases.map(\.rawValue) == ["off", "bell", "notification"])
    }

    @Test func `what is not one of the three is refused`() {
        for json in [#"{"notify": "loud"}"#, #"{"notify": true}"#] {
            #expect(throws: (any Error).self, "\(json)") { try ui(json) }
        }
    }

    @Test func `the setting is in the catalog, off by default`() throws {
        let row = try #require(SettingCatalog.all.first { $0.path == ["ui", "notify"] })
        #expect(row.defaultValue == "off")
    }
}
