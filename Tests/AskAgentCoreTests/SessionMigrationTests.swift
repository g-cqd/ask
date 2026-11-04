import Testing

@testable import AskAgentCore

/// Session migrations (ADR-0144): older files open through ordered steps, every one of which is marked for removal before 1.0.
@Suite("Every session migration ends before 1.0, and older files still open through them")
struct SessionMigrationTests {
    @Test func `every step is marked for removal before the first release candidate`() {
        #expect(!SessionMigration.all.isEmpty)
        for step in SessionMigration.all {
            #expect(step.removeBefore == "1.0.0-rc.1", "\(step.name)")
            #expect(step.from < SessionLog.formatVersion, "\(step.name) converts from an older format")
        }
    }

    @Test func `a format 1 file opens through its step, and a format no step knows is refused`() throws {
        let entry = #"{"id":"a","payload":{"kind":"user","text":"x"},"type":"entry"}"#
        let one = try SessionLog.recover(Array((#"{"type":"session","version":1}"# + "\n" + entry + "\n").utf8))
        #expect(one.formatVersion == 1 && one.issues.isEmpty && one.tree.entries.count == 1)
        #expect(throws: SessionLogError.unsupportedVersion(9)) {
            try SessionLog.recover(Array((#"{"type":"session","version":9}"# + "\n" + entry + "\n").utf8))
        }
    }
}
