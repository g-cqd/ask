#if os(macOS)
    import Darwin
    import Foundation
    import Synchronization
    import Testing

    @testable import AskTUI

    /// A command-line process has no role of an app, and macOS then schedules every thread at the default priority whatever quality of
    /// service it asks for (note n18): ask's render and input threads asked for `userInteractive` and ran at 31 like a build's, so under
    /// heavy contention a trackpad's burst took hundreds of milliseconds to draw. As the screen opens, ask takes the role of the app in
    /// front, which an app in focus has: those threads run at 47, and what asked for nothing more (the conversation's work, a command's
    /// process) stays where it was.
    @Suite("The interactive screen is scheduled as the app in front")
    struct ProcessRoleTests {
        /// Granted in a person's login session; a CI runner's process is refused, and then nothing changes.
        @Test func `the process has the role of the app in focus exactly when the system grants it`() {
            let granted = ProcessRole.becomeInteractive()
            #expect(ProcessRole.isInteractive == granted)
        }

        /// What the role is for: a thread that asks for `userInteractive` is scheduled above the default (47, not 31) once it is held.
        @Test func `once granted, a thread asking for userInteractive is scheduled above the default`() async {
            guard ProcessRole.becomeInteractive() else { return }
            #expect(await Self.basePriority(of: .userInteractive) > Self.basePriority(of: .default))
        }

        /// The base priority the scheduler gives a new thread at `quality`.
        private static func basePriority(of quality: QualityOfService) async -> Int32 {
            await withCheckedContinuation { continuation in
                let thread = Thread {
                    var info = thread_extended_info_data_t()
                    var count = mach_msg_type_number_t(
                        MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size
                    )
                    let port = mach_thread_self()
                    let status = withUnsafeMutablePointer(to: &info) { pointer in
                        unsafe pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                            unsafe thread_info(port, thread_flavor_t(THREAD_EXTENDED_INFO), raw, &count)
                        }
                    }
                    mach_port_deallocate(mach_task_self_, port)
                    continuation.resume(returning: status == KERN_SUCCESS ? info.pth_priority : -1)
                }
                thread.qualityOfService = quality
                thread.start()
            }
        }
    }
#endif
