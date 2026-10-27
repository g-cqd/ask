internal import struct AskAgentCore.SandboxPolicy

extension Job {
    /// What starting a job needs.
    struct Launch: Sendable {
        /// The job's name, as the model sees it.
        var id: String
        var displayID: String? = nil
        var command: String
        var workingDirectory: String
        /// A new file for the whole output, or nil.
        var outputPath: String?
        /// Whether standard input stays open for ``write(_:)``; otherwise it is closed at once.
        var keepsInputOpen: Bool
        /// How many bytes of unread output to keep at each end.
        var keeping: Int
        /// What the command may touch.
        var sandbox: SandboxPolicy
        /// Stops the job's group if ask is killed (ADR-0079).
        var watchdog: JobWatchdog?
        /// The whole environment the command is given, and no other (ADR-0106).
        var environment: [String: String]
        var shell: String? = nil
    }
}
