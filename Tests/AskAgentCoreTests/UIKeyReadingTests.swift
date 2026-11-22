internal import Testing

@testable import AskAgentCore

/// Each `ui` key reads back its own setting and no other (roadmap 0209, step 1): a file that sets one key, with the catalog's example,
/// shows a value for that key in `ask config` and none for any other. The fixture that sets every key (`ConfigurationKeySourceTests`)
/// tells two fields apart only where its values for them differ; two reading arms survived the mutation run of 2026-11-08.
@Suite("Each ui key reads its own setting")
struct UIKeyReadingTests {
    /// `{"ui": …}` setting only `path` (under `ui`) to `example`.
    private static func file(_ path: ArraySlice<String>, _ example: String) -> String {
        var json = example
        for name in path.reversed() { json = "{\"\(name)\": \(json)}" }
        return "{\"ui\": \(json)}"
    }

    @Test func `a file that sets one key shows a value for it and for no other key`() throws {
        let rows = SettingCatalog.all.filter { $0.path.first == "ui" }
        #expect(rows.count == UISection.keys.count)
        for row in rows {
            let key = row.path.dropFirst().joined(separator: ".")
            let parsed = try ConfigurationFile.parse(
                Array(Self.file(row.path.dropFirst(), row.example).utf8),
                path: key
            )
            let ui = try #require(parsed.ui, "\(key)")
            #expect(ui.value(forKey: key) != nil, "\(key) reads nothing back")
            let others = UISection.keys.filter { $0 != key && ui.value(forKey: $0) != nil }
            #expect(others.isEmpty, "setting \(key) shows a value for \(others)")
        }
    }

    /// `ask config` lists the keys in the order the example file and the `/config` editor show them.
    @Test func `ask config lists the ui keys in the catalog's order`() {
        let catalog = SettingCatalog.all.filter { $0.path.first == "ui" }
            .map { $0.path.dropFirst().joined(separator: ".") }
        #expect(UISection.keys == catalog)
    }
}
