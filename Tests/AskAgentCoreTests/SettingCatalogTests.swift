internal import Foundation
internal import Testing

@testable import AskAgentCore

/// The settings catalog (roadmaps 0096 and 0118) is the keys the parser accepts, no more and no fewer; the example generated from it
/// loads; the checked-in example is the generated one; and the `/config` editor's rows come from it.
@Suite("One list of every setting")
struct SettingCatalogTests {
    private static let exampleURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/config.example.jsonc")

    /// The parser's keys under `section`, with `ui.fold`'s as `fold.*`.
    private func catalogKeys(under section: String) -> Set<String> {
        Set(
            SettingCatalog.all.filter { $0.path.count > 1 && $0.path[0] == section }
                .map { $0.path.dropFirst().joined(separator: ".") })
    }

    @Test func `the catalog holds exactly the keys the parser reads`() {
        let sections: [String: [String]] = [
            "ui": UISection.keys, "sandbox": SandboxSection.keys, "approvals": ApprovalsSection.keys,
            "skills": SkillsSection.keys, "environment": EnvironmentSection.keys
        ]
        for (section, keys) in sections {
            #expect(catalogKeys(under: section) == Set(keys), "\(section)")
        }
        let top = Set(SettingCatalog.all.filter { $0.path.count == 1 }.map { $0.path[0] })
        #expect(top == Set(ConfigurationFile.keys).subtracting(sections.keys).subtracting(["mcp"]))
    }

    @Test func `the example loads as your own file, and sets every setting`() throws {
        let file = try ConfigurationFile.parse(Array(SettingCatalog.example.utf8), path: "example")
        #expect(file.notices.isEmpty, "the example uses no old name: \(file.notices)")
        for setting in SettingCatalog.all where setting.path.count == 1 {
            #expect(file.sets(setting.path[0]), "\(setting.path[0])")
        }
        #expect(file.mcp != nil)
    }

    @Test func `the checked-in example is the generated one`() throws {
        if ProcessInfo.processInfo.environment["ASK_WRITE_EXAMPLE"] == "1" {
            try Data(SettingCatalog.example.utf8).write(to: Self.exampleURL)
        }
        let checkedIn = try String(contentsOf: Self.exampleURL, encoding: .utf8)
        #expect(checkedIn == SettingCatalog.example, "run ASK_WRITE_EXAMPLE=1 swift test --filter SettingCatalogTests")
    }

    @Test func `the editor's rows are the catalog's, switches and choices editable`() {
        let rows = ConfigEditor.descriptors
        #expect(
            Set(rows.map(\.path)) == Set(SettingCatalog.all.map(\.path) + [["mcp"]])
                && rows.count == SettingCatalog.all.count + 1)
        #expect(
            rows.prefix(3).map(\.path) == [["ui", "mouse"], ["ui", "copyOnSelect"], ["ui", "tint"]],
            "the ui switches lead")
        #expect(rows.first { $0.path == ["ui", "tint"] }?.kind == .boolean)
        #expect(rows.first { $0.path == ["keepAwake"] }?.kind == .choice(KeepAwakeMode.allCases.map(\.rawValue)))
        #expect(rows.first { $0.path == ["ui", "stopTwice"] }?.kind == .readOnly)
    }
}
