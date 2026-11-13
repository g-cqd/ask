internal import AskAgentCore
internal import AskTUI
internal import Synchronization

/// What the conversation keeps beside its messages (roadmap 0230): a write of it that fails is said to the person, never dropped,
/// since what was not saved is missing after a resume and nothing else would tell them.
extension AgentConversation {
    /// Tells the person something outside a command's own answer, on the screen's channel when there is one.
    func tell(_ text: String, isError: Bool = true) {
        approvals.withLock { $0.ask }?(.notice(text, isError: isError))
    }

    /// Records `record` in `recorder`; says what was not saved when it cannot be.
    func saveThreadRecord(_ record: ThreadRecord, in recorder: SessionRecorder?, as what: String) {
        guard let recorder else { return }
        do { try recorder.recordThread(record) } catch {
            tell("Could not save \(what) in the session (\(error)): it will be missing after a resume.")
        }
    }
}
