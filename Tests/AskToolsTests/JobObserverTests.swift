import AskAgentCore
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The observer a test gives a job is told of a chunk of output only once the job holds it, so a test that acts on being told
/// finds the output where `wait` and `takeOutput` look for it. The other order made `JobToolsTests` fail about one run in twenty.
@Suite("A job holds a chunk of output before its observer hears of it", .timeLimit(.minutes(1)))
struct JobObserverTests {
    @Test func `the buffer already holds what the observer is told`() async {
        let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)
        let jobs = JobTable()
        let job = Mutex<Job?>(nil)
        let held = Mutex<[Bool]>([])
        let started = jobs.start("read go; echo one", in: context, keepsInputOpen: true, keeping: 1_000) { bytes in
            // The job is stored before it is written to, so by now it is there.
            let total = job.withLock { $0 }?.state.withLock { $0.totalBytes } ?? 0
            held.withLock { $0.append(total >= bytes.count) }
        }
        job.withLock { $0 = started }
        #expect(started.write(Array("go\n".utf8)))
        await started.ended()
        #expect(held.withLock { $0 } == [true], "the job had the chunk when the observer was told of it")
    }
}
