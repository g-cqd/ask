#if os(macOS)
    import Testing

    @testable import AskTUI

    /// A command-line process has no role of an app, and macOS then schedules every thread at the default priority whatever quality of
    /// service it asks for (note n18): ask's render and input threads asked for `userInteractive` and ran at 31 like a build's, so under
    /// heavy contention a trackpad's burst took hundreds of milliseconds to draw. As the screen opens, ask takes the role of the app in
    /// front, which an app in focus has: those threads run at 47, and what asked for nothing more (the conversation's work, a command's
    /// process) stays where it was.
    @Suite("The interactive screen is scheduled as the app in front")
    struct ProcessRoleTests {
        @Test func `once the screen opens, the process has the role of the app in focus`() {
            ProcessRole.becomeInteractive()
            #expect(ProcessRole.isInteractive)
        }
    }
#endif
