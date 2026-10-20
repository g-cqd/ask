internal import AskAgentCore
internal import Foundation

/// The strict sandbox a session records and a resumed one keeps (roadmap 0042).
extension RunSettings {
    /// These settings, or, for a session that recorded a strict sandbox, the settings read again with that record as
    /// a narrowing layer below the flags. A record the configuration cannot load with is reported and ignored.
    func resuming(_ session: SessionRecorder?, from source: ConfigurationSource) async -> RunSettings {
        guard session?.sandbox != nil else { return self }
        do { return try await source.resuming(session).load() } catch {
            FileHandle.standardError.write(Data("ask: the session's recorded sandbox was not applied: \(error)\n".utf8))
            return self
        }
    }

    /// Records the strict settings in `session`, so resuming it keeps them. Nothing for an unsandboxed run, and
    /// nothing for a session that never ran strict and still does not.
    func record(in session: SessionRecorder) throws(SessionFileError) {
        let section = configuration.sandbox.value
        guard !sandbox.isUnrestricted else { return }
        guard session.sandbox != nil || !section.write.isEmpty || section.network != nil else { return }
        try session.recordSandbox(section)
    }
}
