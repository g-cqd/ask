import AskAgentCore
import Testing

@testable import AskTools

@Suite("Job display identities never collide or replace native tool references")
struct JobDisplayIDsTests {
    @Test func `four hex digits are padded and collisions wrap without reuse`() {
        var ids = JobDisplayIDs()
        #expect(ids.next(candidate: 0xffff) == "ffff")
        #expect(ids.next(candidate: 0xffff) == "0000")
        #expect(ids.next(candidate: 0xffff) == "0001")
        #expect(ids.next(candidate: 0xabcd) == "abcd")
    }

    @Test func `exhausting four digit identities falls back to UUID rather than recycling`() {
        var ids = JobDisplayIDs()
        var seen: Set<String> = []
        for candidate in UInt16.min ... UInt16.max {
            #expect(seen.insert(ids.next(candidate: candidate)).inserted)
        }
        let fallback = ids.next(candidate: 0)
        #expect(fallback.count == 36 && !seen.contains(fallback))
    }

    @Test func `the short identity with or without hash addresses the same native job`() async {
        let table = JobTable()
        let job = table.start(
            "read hold", in: ToolContext(workingDirectory: "/tmp"),
            keepsInputOpen: true, keeping: 1000, observe: { _ in })
        #expect(job.displayID.count == 4)
        #expect(table.job(job.id) === job)
        #expect(table.job(job.displayID) === job)
        #expect(table.job("#" + job.displayID) === job)
        #expect(table.snapshot(of: job.displayID)?.displayID == job.displayID)
        await table.stopAll()
    }
}
