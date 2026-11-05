/// What the model gives a subagent it starts (roadmap 0063, ADR-0146): the subagent sees nothing of the conversation, so these three
/// are all it has.
public struct SubagentTask: Sendable, Equatable {
    /// Who starts a subagent for a task and waits for what it reports; nil where no one can.
    public typealias Starter = @Sendable (SubagentTask) async -> SubagentOutcome

    /// What to do.
    public let task: String
    /// What it needs to know: paths, findings, constraints, decisions already made.
    public let context: String
    /// What completion is, and what to return.
    public let done: String
    /// The agent definition it runs as, when the call named one (roadmap 0063 phase 3).
    public let definition: AgentDefinition?

    public init(task: String, context: String, done: String, definition: AgentDefinition? = nil) {
        self.task = task
        self.context = context
        self.done = done
        self.definition = definition
    }

    /// Its first message: the three, as its parent wrote them.
    public var prompt: String {
        // A definition's instructions come first: who it is, then what it is asked.
        (definition.map { $0.instructions + "\n\n" } ?? "")
            + """
            You are a subagent: another agent started you for one piece of work. You see nothing of its conversation; this is all \
            you have. When you have finished, end with your report, which is all it will see of your work.

            Task: \(task)

            What you need to know: \(context)

            Done when: \(done)
            """
    }
}
