import Testing

@testable import AskAgentCore

/// `ui.statusPath` and `ui.statusPathSide` (notes n6 and n63): the folder on the status line, its form and its end.
@Suite("ui.statusPath and ui.statusPathSide say how the status line shows the folder")
struct StatusPathConfigurationTests {
    private func ui(_ json: String) throws -> UISection? {
        try ConfigurationFile.parse(Array(#"{"ui": \#(json)}"#.utf8), path: "c.json").ui
    }

    @Test func `both are read, layered, listed and shown`() throws {
        let section = try #require(try ui(#"{"statusPath": "home", "statusPathSide": "trailing"}"#))
        #expect(section.statusPath == .home && section.statusPathSide == .trailing)
        #expect(section.description == "statusPath home, statusPathSide trailing")
        var lower = UISection()
        lower.statusPath = .full
        var upper = UISection()
        upper.statusPath = .off
        #expect(lower.layered(with: upper).statusPath == .off && lower.layered(with: UISection()).statusPath == .full)
        #expect(UISection.keys.contains("statusPath") && UISection.keys.contains("statusPathSide"))
        #expect(StatusPathPreference.allCases.map(\.rawValue) == ["folder", "home", "full", "off"])
        #expect(StatusPathSidePreference.allCases.map(\.rawValue) == ["leading", "trailing"])
    }

    @Test func `what is not one of them is refused`() {
        for json in [#"{"statusPath": "short"}"#, #"{"statusPath": false}"#, #"{"statusPathSide": "left"}"#] {
            #expect(throws: (any Error).self, "\(json)") { try ui(json) }
        }
    }

    @Test func `both are in the catalog: the last folder, right after the mark`() throws {
        let form = try #require(SettingCatalog.all.first { $0.path == ["ui", "statusPath"] })
        let side = try #require(SettingCatalog.all.first { $0.path == ["ui", "statusPathSide"] })
        #expect(form.defaultValue == "folder" && side.defaultValue == "leading")
    }
}
