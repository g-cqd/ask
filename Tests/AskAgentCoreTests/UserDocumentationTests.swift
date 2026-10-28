internal import AskAgentCore
internal import Foundation
internal import Testing

/// The user guide in `docs/` follows the code it describes (roadmap 0102, ADR-0128): every key a configuration file may set is documented,
/// its links lead somewhere, and only its index points at the development records.
@Suite("The user guide documents every setting and stands on its own")
struct UserDocumentationTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private static func guidePages() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "docs").path)
            .filter { $0.hasSuffix(".md") }.sorted()
    }

    @Test func `every key a configuration file may set is in the configuration page`() throws {
        let page = try Self.text("docs/configuration.md")
        let sections: [(String, [String])] = [
            ("top level", ConfigurationFile.keys), ("ui", UISection.keys), ("skills", SkillsSection.keys),
            ("sandbox", SandboxSection.keys), ("environment", EnvironmentSection.keys), ("mcp", MCPServerSetting.keys)
        ]
        for (section, keys) in sections {
            let missing = keys.filter { !page.contains("`\($0)`") }
            #expect(missing.isEmpty, "docs/configuration.md does not document \(section) keys \(missing)")
        }
    }

    @Test func `only the guide's index points at the development records`() throws {
        for page in try Self.guidePages() where page != "README.md" {
            #expect(
                !(try Self.text("docs/" + page)).contains("development/"), "docs/\(page) sends a user into development/"
            )
        }
    }

    /// The targets of a page's Markdown links that name a file here: not a web address, not an anchor alone.
    private static func relativeTargets(_ text: String) -> [String] {
        text.components(separatedBy: "](").dropFirst()
            .compactMap { rest in
                guard let close = rest.firstIndex(of: ")") else { return nil }
                let target = String(rest[..<close].prefix { $0 != "#" })
                return target.isEmpty || target.contains(":") || target.contains(" ") ? nil : target
            }
    }

    @Test func `every relative link in the guide and the README leads to a file`() throws {
        let pages = try Self.guidePages().map { "docs/" + $0 } + ["README.md"]
        for page in pages {
            let directory = Self.root.appending(path: page).deletingLastPathComponent()
            for target in Self.relativeTargets(try Self.text(page)) {
                let path = directory.appending(path: target).standardizedFileURL.path
                #expect(FileManager.default.fileExists(atPath: path), "\(page) links to \(target), which is not there")
            }
        }
    }
}
