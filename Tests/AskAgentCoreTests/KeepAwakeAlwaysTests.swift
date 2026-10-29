internal import Testing

@testable import AskAgentCore

/// `keepAwake: "always"` (roadmap 0148): the Mac is kept awake from launch to exit, idle or not; the assertion dies with the process.
@Suite("Keeping the Mac awake for as long as ask runs")
struct KeepAwakeAlwaysTests {
    @Test func `always holds from the start, through turns and idle time alike`() {
        let system = KeepAwakeTests.Recorder()
        let awake = KeepAwake(mode: .always, activities: system)
        #expect(awake.isHolding && system.log == ["begin always #1"])
        awake.turnStarted()
        awake.turnEnded()
        awake.jobsRunning(true)
        awake.jobsRunning(false)
        #expect(awake.isHolding && system.log == ["begin always #1"], "work coming and going changes nothing")
    }

    @Test func `leaving always while idle lets go, and choosing it while idle holds`() {
        let system = KeepAwakeTests.Recorder()
        let awake = KeepAwake(mode: .always, activities: system)
        awake.use(.system)
        #expect(!awake.isHolding && system.log == ["begin always #1", "end #1"])
        awake.use(.always)
        #expect(awake.isHolding && system.log.last == "begin always #2")
    }

    @Test func `always is read from a file`() throws {
        let file = try ConfigurationFile.parse(Array(#"{"keepAwake": "always"}"#.utf8), path: "c.json")
        #expect(file.keepAwake == .always)
    }
}
