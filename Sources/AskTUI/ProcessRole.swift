#if canImport(Darwin)
    internal import Darwin
#endif

/// How macOS schedules ask's process while the screen is open (note n18).
///
/// A command-line process has no role of an app, and macOS then runs every thread at the default priority (31) whatever quality of
/// service it asks for. ask's render and input threads, and the screen's own thread, ask for `userInteractive`, but ran at 31 like any
/// build beside them; under heavy contention a trackpad's burst took hundreds of milliseconds, up to more than a second, to draw. With
/// the role of the app in focus, which an app in front has, the threads that asked for `userInteractive` run at 47 and `userInitiated`
/// at 37; the default and lower stay as they were, and a process ask starts (a command, a build) is not raised (measured 2026-11-05:
/// a child ran at 29).
enum ProcessRole {
    /// `PRIO_DARWIN_ROLE` and `PRIO_DARWIN_ROLE_UI_FOCAL` from `<sys/resource.h>`, which Swift does not import.
    private static let roleWhich: Int32 = 6
    private static let focal: Int32 = 1

    /// Takes the role of the app in focus. Nothing happens where there are no roles, or when the system refuses, as it does for a
    /// process outside a person's login session (a CI runner's).
    /// - Returns: whether the process has the role now.
    @discardableResult
    static func becomeInteractive() -> Bool {
        #if os(macOS)
            return setpriority(roleWhich, 0, focal) == 0 && isInteractive
        #else
            return false
        #endif
    }

    /// Whether the process has that role now.
    static var isInteractive: Bool {
        #if os(macOS)
            errno = 0
            return getpriority(roleWhich, 0) == focal && errno == 0
        #else
            return false
        #endif
    }
}
