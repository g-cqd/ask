internal import Foundation
internal import Testing

@testable import AskCore

/// Every request ask makes goes through `URLSessionTransport` (security audit 2: an ephemeral session, the system's TLS evaluation,
/// redirects refused when asked). The system's shared session keeps a cache and cookies on disk and follows redirects by itself:
/// used for `#123` it left GitHub's answers in `~/Library/Caches/ask` (security audit 3, 2026-11-13). So no other file makes or uses
/// a session.
@Suite("Only the transport makes an HTTP session")
struct HTTPSessionStandardsTests {
    static let forbidden = ["URLSession.shared", "URLSessionConfiguration.default", "URLSession(configuration"]
    static let transport = "AskAI/Transport/URLSessionTransport.swift"

    static func offenders(in text: String, file: String) -> [String] {
        guard file != transport else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .compactMap { index, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), forbidden.contains(where: code.contains) else { return nil }
                return "\(file):\(index + 1)"
            }
    }

    @Test func `the rule finds a shared session, and lets the transport and comments be`() {
        #expect(
            Self.offenders(in: "let a = 1\nlet d = try await URLSession.shared.data(for: r)\n", file: "A.swift") == [
                "A.swift:2"
            ]
        )
        #expect(Self.offenders(in: "let s = URLSession(configuration: c)\n", file: Self.transport).isEmpty)
        #expect(Self.offenders(in: "/// not URLSession.shared\n", file: "A.swift").isEmpty)
    }

    @Test func `no source file makes or uses a session of its own`() throws {
        let root = SourceStandards.repositoryRoot.appending(path: "Sources")
        let files =
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let found = try files.filter { $0.pathExtension == "swift" }
            .flatMap { file in
                Self.offenders(
                    in: try String(contentsOf: file, encoding: .utf8),
                    file: file.path.replacingOccurrences(of: root.path + "/", with: "")
                )
            }
        #expect(found.isEmpty, "send it through URLSessionTransport: \(found.sorted())")
    }
}
