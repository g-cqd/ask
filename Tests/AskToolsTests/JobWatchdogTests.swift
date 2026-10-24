import AskAgentCore
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// A job outlives ask when ask is killed with SIGKILL, which nothing in ask can observe. A small process outside ask watches a pipe
/// ask holds, and when the pipe closes it stops every group still registered (ADR-0079). These tests close the pipe as the kernel
/// does when ask dies, and look at real processes. Nothing here waits for a time to pass: each wait is for an event.
@Suite("A job does not outlive a killed ask", .timeLimit(.minutes(1)))
struct JobWatchdogTests {
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)
    private let jobs = JobTable()

    private func start(_ command: String, _ started: Started = Started()) -> Job {
        jobs.start(command, in: context, keepsInputOpen: false, keeping: 1_000) { started.received($0) }
    }

    /// The pid the watchdog's shell runs as, once it has started.
    private func shell(of watchdog: JobWatchdog) async -> pid_t? {
        await watchdog.waitForProtection { $0 != .starting && $0 != .idle }
        if case .running(let pid) = watchdog.protection { return pid }
        return nil
    }

    private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    // MARK: - What it does

    @Test func `a running job's group is stopped when ask dies, though nothing stopped it`() async throws {
        let started = Started()
        let job = start("sleep 300 & echo child $!; wait", started)
        let child = try await started.child()
        #expect(isAlive(child))
        jobs.watchdog.simulateDeath()
        let gone = try await ProcessExit.observed(child)
        job.stop()  // a failed expectation must not leave the job to run out its sleep
        await job.ended()
        #expect(gone, "the child of the job was stopped by the watchdog")
    }

    @Test func `a job that ignores SIGTERM is killed after the grace`() async throws {
        let started = Started()
        let job = start("trap '' TERM; sleep 300 & echo child $!; wait", started)
        let child = try await started.child()
        jobs.watchdog.simulateDeath()
        let gone = try await ProcessExit.observed(child)
        job.stop()
        await job.ended()
        #expect(gone)
    }

    @Test func `a job that needs a moment to shut down is given it before it is killed`() async throws {
        let ready = Printed("ready")
        let output = Mutex("")
        let job = jobs.start(
            "trap 'echo terminated; sleep 1; echo graceful; exit 0' TERM; echo ready; sleep 300 & wait", in: context,
            keepsInputOpen: false, keeping: 1_000
        ) { bytes in
            ready.received(bytes)
            output.withLock { $0 += String(decoding: bytes, as: UTF8.self) }
        }
        await ready.seen()
        let bash = try #require(job.state.withLock { $0.pid })
        jobs.watchdog.simulateDeath()
        let ended = try await ProcessExit.observed(bash)
        job.stop()  // whatever happened, the job does not run out its sleep
        await job.ended()
        let text = output.withLock { $0 }
        #expect(ended && text.contains("terminated"), "the group was asked to stop first: \(text)")
        #expect(text.contains("graceful"), "and was given the second it needed; a KILL at once would not have: \(text)")
    }

    @Test func `only the groups still registered are stopped, whatever order the others left in`() async throws {
        let (first, second, third) = (Started(), Started(), Started())
        let one = start("sleep 300 & echo child $!; wait", first)
        let two = start("sleep 300 & echo child $!; wait", second)
        let three = start("sleep 300 & echo child $!; wait", third)
        let (a, b, c) = (try await first.child(), try await second.child(), try await third.child())
        jobs.watchdog.release(try #require(two.state.withLock { $0.pid }))
        jobs.watchdog.simulateDeath()
        let firstGone = try await ProcessExit.observed(a)
        // The shell stops the groups in the order it holds them, so once the last is gone it has been through the list.
        let thirdGone = try await ProcessExit.observed(c)
        let secondAlive = isAlive(b)
        for job in [one, two, three] { job.stop() }
        #expect(firstGone && thirdGone)
        #expect(secondAlive, "a group that was released is not the watchdog's to stop")
        await one.ended()
        await two.ended()
        await three.ended()
    }

    @Test func `a job that ended is released, and one that runs is watched`() async throws {
        let started = Started()
        let running = start("sleep 300 & echo child $!; wait", started)
        _ = try await started.child()
        let pid = try #require(running.state.withLock { $0.pid })
        let listed = jobs.watchdog.watching
        running.stop()
        await running.ended()
        #expect(listed == [pid])
        #expect(jobs.watchdog.watching.isEmpty)
        let quick = start("true")
        await quick.ended()
        #expect(jobs.watchdog.watching.isEmpty)
    }

    @Test func `with nothing registered the watchdog ends at once when ask does`() async throws {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_001)
        watchdog.release(2_000_000_001)
        let process = try #require(await shell(of: watchdog))
        let begun = ContinuousClock.now
        watchdog.simulateDeath()
        #expect(try await ProcessExit.observed(process))
        #expect(ContinuousClock.now - begun < .seconds(1.5), "with no group to stop there is no grace to wait out")
        await watchdog.waitForProtection { $0 == .unavailable }  // set once the shell has been reaped
        #expect(!isAlive(process), "and the shell has been reaped, not left as a zombie")
    }

    // MARK: - What it must not do

    @Test func `a watchdog that is gone does not take ask down with a signal`() async throws {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_002)
        let process = try #require(await shell(of: watchdog))
        // A test process may already ignore SIGPIPE; ask's own might not have, and the default is a death.
        let before = signal(SIGPIPE, SIG_DFL)
        defer { signal(SIGPIPE, before) }
        kill(process, SIGKILL)
        #expect(try await ProcessExit.observed(process))
        await watchdog.waitForProtection { $0 == .unavailable }
        #expect(
            watchdog.protection == .unavailable, "a shell that ended while ask holds the pipe is noticed, not assumed")
        for number in 0 ..< 50 { watchdog.watch(pid_t(2_000_000_100 + number)) }
        watchdog.release(2_000_000_002)
        #expect(watchdog.watching.count == 50, "ask still runs, and still knows what it started")
    }

    @Test func `the write end never blocks ask, and a watchdog that stops reading is reported`() async throws {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_008)
        let process = try #require(await shell(of: watchdog))
        let descriptor = try #require(watchdog.openDescriptorForTesting())
        let blocks = fcntl(descriptor, F_GETFL) & O_NONBLOCK == 0
        #expect(!blocks && fcntl(descriptor, F_GETNOSIGPIPE) == 1, "the write end never blocks and never signals")
        guard !blocks else { return }  // a blocking write below would not return
        kill(process, SIGSTOP)
        defer { kill(process, SIGKILL) }  // a stopped shell does not end when the pipe closes
        // More lines than a pipe holds (64 KiB at most), with nobody reading.
        for number in 0 ..< 20_000 { watchdog.watch(pid_t(2_100_000 + number)) }
        #expect(watchdog.protection == .unavailable)
    }

    @Test func `the watchdog is in a session of its own, so the terminal's signals do not reach it`() async throws {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_004)
        let process = try #require(await shell(of: watchdog))
        #expect(getsid(process) == process && getsid(process) != getsid(0))
        watchdog.simulateDeath()
    }

    @Test func `a descriptor ask left inheritable does not reach the watchdog's shell`() async throws {
        let marker = open("/dev/null", O_RDONLY)  // inheritable, as a descriptor ask forgot to close would be
        defer { close(marker) }
        _ = fcntl(marker, F_SETFD, 0)
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_009)
        watchdog.release(2_000_000_009)
        let process = try #require(await shell(of: watchdog))
        let size = proc_pidinfo(process, PROC_PIDLISTFDS, 0, nil, 0)
        var infos = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let listed = proc_pidinfo(process, PROC_PIDLISTFDS, 0, &infos, size)
        // Not "exactly 0, 1 and 2": for a moment the shell has the few files its own start-up has open.
        let open = infos.prefix(Int(listed) / MemoryLayout<proc_fdinfo>.size).map(\.proc_fd)
        #expect(open.contains(0) && !open.contains(marker), "the shell's descriptors: \(open), the marker is \(marker)")
        watchdog.simulateDeath()
    }

    @Test func `the pipe's write end is not inherited by a job`() async throws {
        await start("true").ended()  // the first job opens the pipe
        let descriptor = try #require(jobs.watchdog.openDescriptorForTesting())
        let output = Mutex("")
        let job = jobs.start(
            "[ -e /dev/fd/\(descriptor) ] && echo open || echo closed", in: context, keepsInputOpen: false,
            keeping: 1_000
        ) { bytes in output.withLock { $0 += String(decoding: bytes, as: UTF8.self) } }
        await job.ended()
        #expect(
            output.withLock { $0 }.contains("closed"), "an inherited write end would keep the pipe open after ask dies")
    }

    @Test func `once the pipe is closed nothing opens another`() {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_005)
        watchdog.simulateDeath()
        watchdog.watch(2_000_000_006)
        #expect(watchdog.openDescriptorForTesting() == nil)
    }

    /// The shell of a watchdog that goes out of scope when this returns.
    private func shellOfWatchdogThatIsLetGo() async -> pid_t? {
        let watchdog = JobWatchdog()
        watchdog.watch(2_000_000_007)
        watchdog.release(2_000_000_007)
        return await shell(of: watchdog)
    }

    @Test func `when the watchdog is let go its shell ends`() async throws {
        let process = try #require(await shellOfWatchdogThatIsLetGo())
        #expect(try await ProcessExit.observed(process))
    }

    @Test func `a shell that cannot start leaves ask running, and says it is unprotected`() async {
        let watchdog = JobWatchdog(shell: "/nonexistent/sh")
        watchdog.watch(2_000_000_003)
        await watchdog.waitForProtection { $0 != .starting }
        #expect(watchdog.protection == .unavailable)
        watchdog.release(2_000_000_003)
    }

    @Test func `before the first job there is no process and no pipe`() {
        let watchdog = JobWatchdog()
        #expect(watchdog.protection == .idle && watchdog.openDescriptorForTesting() == nil)
    }
}
