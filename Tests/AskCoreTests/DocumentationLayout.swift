internal import Foundation

enum DocumentationLayout {
    static let maximumWhitePaperLines = 200

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func whitePaperURL() -> URL {
        repositoryRoot.appending(path: "AGENTS.md")
    }

    static func whitePaperLineCount() throws -> Int {
        let text = try String(contentsOf: whitePaperURL(), encoding: .utf8)
        guard !text.isEmpty else { return 0 }
        let newlines = text.utf8.count { $0 == 0x0A }
        return text.utf8.last == 0x0A ? newlines : newlines + 1
    }

    static func adrFiles() throws -> [URL] {
        let dir = repositoryRoot.appending(path: "docs/adr")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
            .sorted()
        return names.map { dir.appending(path: $0) }
    }
}
