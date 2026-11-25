import AskCore
import Testing

@Suite("AskVersion")
struct AskVersionTests {
    @Test func `current version is a valid semantic version without a leading v`() {
        let v = AskVersion.current
        #expect(!v.isEmpty)
        #expect(!v.hasPrefix("v"))
        let parts = v.split(separator: "-", maxSplits: 1)
        let core = parts[0].split(separator: ".")
        #expect(core.count == 3)
        #expect(core.allSatisfy { Int($0) != nil })
    }
}
