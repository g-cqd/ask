internal import Foundation
internal import Testing

@testable import AskAgentCore

/// `docs/configuration.md`'s tables are held to the catalog (roadmap 0118): every setting has its row, under its section, with the
/// catalog's default, and a setting only your own file may hold says so, in its row or for its whole section. The prose stays in the
/// Markdown, where it is read and written; the test fails when the two drift.
@Suite("The configuration docs' tables are the catalog's settings")
struct SettingDocsTests {
    private struct Row {
        let defaultValue: String
        let text: String
        let sectionIntro: String
    }

    /// The rows of "Every setting", by dotted key; the `mcp` table describes a server's members and is left out.
    private static let rows: [String: Row] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/configuration.md")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let settings = text.components(separatedBy: "## Every setting").last ?? ""
        var rows: [String: Row] = [:]
        var section = ""
        var intro = ""
        for line in settings.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("### ") {
                section = line.hasPrefix("### `") ? line.dropFirst(5).prefix { $0 != "`" }.description : ""
                intro = ""
                continue
            }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            guard cells.count >= 4, cells[1].hasPrefix("`"), section != "mcp" else {
                if !line.hasPrefix("|") { intro += line + "\n" }
                continue
            }
            let key = cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            rows[(section.isEmpty ? "" : section + ".") + key] = Row(
                defaultValue: cells[2], text: cells[3...].joined(separator: "|"), sectionIntro: intro)
        }
        return rows
    }()

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "\"", with: "")
    }

    @Test func `every setting has its row with the catalog's default, and every row is a setting or a section`() {
        #expect(Self.rows.count > 40, "the tables were found")
        for setting in SettingCatalog.all {
            let row = Self.rows[setting.key]
            #expect(row != nil, "no row for \(setting.key)")
            if let row {
                #expect(Self.plain(row.defaultValue) == Self.plain(setting.defaultValue), "\(setting.key)")
            }
        }
        let known = Set(SettingCatalog.all.map(\.key)).union(SettingCatalog.sections)
        #expect(Set(Self.rows.keys).subtracting(known).isEmpty, "rows the catalog lacks")
    }

    @Test func `a setting only your own file may hold says so`() {
        for setting in SettingCatalog.all {
            guard let row = Self.rows[setting.key] else { continue }
            let says = row.text.contains("Your own file only") || row.sectionIntro.contains("Your own file only")
            #expect(says == setting.userOnly, "\(setting.key)")
        }
    }
}
