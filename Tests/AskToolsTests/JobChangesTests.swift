import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The screen's count of running jobs comes from the table, not from polling it.
@Suite("The job table reports who is running whenever that changes", .timeLimit(.minutes(1)))
struct JobChangesTests {
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)
    private let jobs = JobTable()

    private func start(_ command: String) -> Job {
        jobs.start(command, in: context, keepsInputOpen: false, keeping: 1_000) { _ in }
    }

    /// Reads until a list satisfies `done`: a slow reader may be shown only the newest.
    private func next(
        _ iterator: inout AsyncStream<[JobSummary]>.AsyncIterator, until done: ([JobSummary]) -> Bool
    ) async -> [JobSummary] {
        while let list = await iterator.next() {
            if done(list) { return list }
        }
        return []
    }

    @Test func `a new reader is told who is running now, then each start and each end`() async {
        var iterator = jobs.changes().makeAsyncIterator()
        #expect(await iterator.next() == [])
        let first = start("sleep 60")
        let second = start("sleep 61")
        let both = await next(&iterator) { $0.count == 2 }
        #expect(both == [JobSummary(id: "job-1", command: "sleep 60"), JobSummary(id: "job-2", command: "sleep 61")])
        first.stop()
        await first.ended()
        let one = await next(&iterator) { $0.count == 1 }
        #expect(one == [JobSummary(id: "job-2", command: "sleep 61")])
        second.stop()
        await second.ended()
        #expect(await next(&iterator) { $0.isEmpty } == [])
        #expect(jobs.summaries.isEmpty)
    }

    @Test func `a job that ends by itself leaves the list without anyone stopping it`() async {
        var iterator = jobs.changes().makeAsyncIterator()
        _ = await iterator.next()
        let job = start("true")
        await job.ended()
        #expect(await next(&iterator) { $0.isEmpty } == [])
    }

    @Test func `jobs are listed in the order they started, not by name`() {
        let started = (0 ..< 11).map { _ in start("sleep 60") }
        #expect(jobs.summaries.map(\.id) == (1 ... 11).map { "job-\($0)" })
        for job in started { job.stop() }
    }

    @Test func `two readers each get their own list`() async {
        var one = jobs.changes().makeAsyncIterator()
        var two = jobs.changes().makeAsyncIterator()
        _ = await one.next()
        _ = await two.next()
        let job = start("sleep 60")
        #expect(await next(&one) { $0.count == 1 }.count == 1)
        #expect(await next(&two) { $0.count == 1 }.count == 1)
        job.stop()
        await job.ended()
    }
}
