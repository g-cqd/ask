internal import Foundation
internal import Synchronization

/// The host's pasteboard, through a command that reads the text on its standard input (`pbcopy` on macOS). A copy is finished when that
/// command has exited with status 0, not when it was started, and a command that hangs is stopped after `timeout`.
enum HostPasteboard {
    /// How long `pbcopy` may take before the copy is called failed. It is normally instant.
    static let timeout = Duration.seconds(5)

    /// `pbcopy`, the macOS pasteboard.
    static let pbcopy: @Sendable (String) async -> PasteboardResult = { text in
        await run(text, executable: "/usr/bin/pbcopy", arguments: [], timeout: timeout)
    }

    /// Runs `executable` with `text` on its standard input and reports how it ended. Nothing blocks a thread: the process's end and the
    /// deadline both resume one continuation, whichever comes first.
    static func run(_ text: String, executable: String, arguments: [String], timeout: Duration) async
        -> PasteboardResult
    {
        await withCheckedContinuation { (continuation: CheckedContinuation<PasteboardResult, Never>) in
            let once = Once(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                once.resume(
                    finished.terminationStatus == 0
                        ? .copied
                        : .failed(
                            "\((executable as NSString).lastPathComponent) exited with status \(finished.terminationStatus)"
                        ))
            }
            do {
                try process.run()
            } catch {
                once.resume(.failed("\((executable as NSString).lastPathComponent) could not start"))
                return
            }
            // A command that exits without reading must give the write an error, not a SIGPIPE that would end ask.
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            // A large text may fill the pipe before the command reads it, so the write has its own thread.
            Thread.detachNewThread {
                try? pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
                try? pipe.fileHandleForWriting.close()
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                if once.resume(.failed("\((executable as NSString).lastPathComponent) did not finish in time")) {
                    process.terminate()
                }
            }
        }
    }

    /// Resumes a continuation once, whichever of the exit and the deadline gets there first.
    private final class Once: Sendable {
        private let continuation: Mutex<CheckedContinuation<PasteboardResult, Never>?>

        init(_ continuation: CheckedContinuation<PasteboardResult, Never>) {
            self.continuation = Mutex(continuation)
        }

        /// - Returns: whether this call resumed it.
        @discardableResult
        func resume(_ result: PasteboardResult) -> Bool {
            guard
                let taken = continuation.withLock({ state -> CheckedContinuation<PasteboardResult, Never>? in
                    defer { state = nil }
                    return state
                })
            else { return false }
            taken.resume(returning: result)
            return true
        }
    }
}
