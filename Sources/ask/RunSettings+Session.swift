internal import AskAgentCore
internal import Foundation

/// The strict sandbox a session records and a resumed one keeps (roadmap 0042).
extension RunSettings {
    /// Records the strict settings in `session`, so resuming it keeps them. Nothing for an unsandboxed run, and
    /// nothing for a session that never ran strict and still does not.
    func record(in session: SessionRecorder) throws(SessionFileError) {
        let section = configuration.sandbox.value
        guard !sandbox.isUnrestricted else { return }
        guard session.sandbox != nil || !section.strict.isEmpty else { return }
        try session.recordSandbox(section)
    }
}
