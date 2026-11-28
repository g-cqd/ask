internal import Testing

@testable import AskCore

/// `SemanticVersion` (roadmap 0130): SemVer 2.0 parsing and precedence, including pre-release ordering, leading `v`, and build metadata.
@Suite("SemanticVersion parses and orders SemVer 2.0 versions accurately")
struct SemanticVersionTests {
    @Test func `core versions, pre-releases and build metadata order according to SemVer 2.0`() throws {
        let ordered = [
            "0.1.0-alpha.1",
            "0.1.0-alpha.2",
            "0.1.0-alpha.10",
            "0.1.0-alpha.beta",
            "0.1.0-beta.1",
            "0.1.0",
            "0.1.1",
            "0.2.0",
            "1.0.0"
        ]
        let parsed = try ordered.map { try #require(SemanticVersion($0)) }
        for index in 0 ..< (parsed.count - 1) {
            #expect(parsed[index] < parsed[index + 1], "\(ordered[index]) < \(ordered[index + 1])")
        }
        #expect(SemanticVersion("v0.1.0-alpha.1+20261127") == SemanticVersion("0.1.0-alpha.1"))

        for invalid in ["", "1.0", "01.1.0", "1.0.0-", "1.0.0+bad!", "1.0.0-01"] {
            #expect(SemanticVersion(invalid) == nil, "\(invalid)")
        }
    }
}
