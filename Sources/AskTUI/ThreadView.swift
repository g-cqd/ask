/// A thread's view while its lane is not shown (roadmaps 0194, 0195): its conversation, and what it is asking the person. Its questions
/// are its own: shown in its lane, answered there, and never cleared by main's run ending.
struct ThreadView: Sendable, Equatable {
    var transcript: Transcript
    var approval: PendingApproval?
    var questions: PendingQuestions?
}
