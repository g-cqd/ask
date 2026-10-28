internal import Synchronization
internal import Testing

@testable import AskAgentCore

/// The Mac is kept awake from the first sign of work to the end of the last, in the configured mode, and never with `off` (roadmap 0090).
@Suite("Keeping the Mac awake while ask works")
struct KeepAwakeTests {
    /// The system, played: every begin and end, in order.
    final class Recorder: PowerActivities {
        let calls = Mutex<[String]>([])
        private let next = Mutex(0)

        func begin(_ mode: KeepAwakeMode, reason: String) -> any Sendable {
            let id = next.withLock { value -> Int in
                value += 1
                return value
            }
            calls.withLock { $0.append("begin \(mode.rawValue) #\(id)") }
            return id
        }

        func end(_ activity: any Sendable) { calls.withLock { $0.append("end #\(activity as? Int ?? -1)") } }

        var log: [String] { calls.withLock { $0 } }
    }

    @Test func `a turn holds the Mac awake from its start to its end, and overlapping turns hold it once`() {
        let system = Recorder()
        let awake = KeepAwake(mode: .system, activities: system)
        awake.turnStarted()
        awake.turnStarted()
        #expect(awake.isHolding)
        awake.turnEnded()
        #expect(system.log == ["begin system #1"], "still working: one turn is left")
        awake.turnEnded()
        #expect(system.log == ["begin system #1", "end #1"] && !awake.isHolding)
    }

    @Test func `a job still running after the turn keeps it held until the job ends`() {
        let system = Recorder()
        let awake = KeepAwake(mode: .display, activities: system)
        awake.turnStarted()
        awake.jobsRunning(true)
        awake.turnEnded()
        #expect(awake.isHolding)
        awake.jobsRunning(false)
        #expect(system.log == ["begin display #1", "end #1"])
    }

    @Test func `off never holds anything, whatever runs`() {
        let system = Recorder()
        let awake = KeepAwake(mode: .off, activities: system)
        awake.turnStarted()
        awake.jobsRunning(true)
        awake.turnEnded()
        #expect(system.log.isEmpty && !awake.isHolding)
    }

    @Test func `a new mode from a reload applies at once while working, and off lets go`() {
        let system = Recorder()
        let awake = KeepAwake(mode: .system, activities: system)
        awake.turnStarted()
        awake.use(.display)
        awake.use(.off)
        #expect(!awake.isHolding)
        awake.use(.system)
        awake.turnEnded()
        awake.use(.display)
        #expect(
            system.log == ["begin system #1", "begin display #2", "end #1", "end #2", "begin system #3", "end #3"],
            "and an idle change of mode begins nothing")
    }

    @Test func `an unmatched end never drops below zero or ends what was never begun`() {
        let system = Recorder()
        let awake = KeepAwake(mode: .system, activities: system)
        awake.turnEnded()
        awake.turnStarted()
        #expect(awake.isHolding)
        awake.turnEnded()
        #expect(system.log == ["begin system #1", "end #1"])
    }

    @Test func `the system's activity can be taken and given back`() {
        let awake = KeepAwake(mode: .system)
        awake.turnStarted()
        #expect(awake.isHolding)
        awake.turnEnded()
        #expect(!awake.isHolding)
    }

    @Test func `keepAwake is read from a file, defaults to system, and refuses what it does not know`() throws {
        #expect(Configuration.defaults.keepAwake.value == .system)
        let file = try ConfigurationFile.parse(Array(#"{"keepAwake": "off"}"#.utf8), path: "c.json")
        #expect(file.keepAwake == .off)
        let configured = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(configured.changes(from: .defaults) == ["keepAwake: system → off (/u/config.json)"])
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(#"{"keepAwake": "caffeinate -dims"}"#.utf8), path: "c.json")
        }
    }
}
