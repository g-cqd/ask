internal import AemiJSON
public import AskAI

/// What a tool returns. A failure is an output too: the model reads it and decides what to do next.
public struct ToolOutput: Sendable, Equatable {
    public var content: String
    public var isError: Bool
    /// A live process yielded by this call. UI routing only; never inferred from output prose.
    public var backgroundJob: String?
    /// Images the tool returned (roadmap 0084), sent to a model that takes images.
    public var images: [ImagePart] = []
    /// Whether the tool cut ``content`` itself, to a limit its caller chose: the registry's cap then leaves it as it is.
    public var bounded = false
    /// What the tool did, typed, for the screen; the model reads ``content`` only.
    public var facts = ToolFacts()

    /// An output with this content.
    public init(_ content: String, isError: Bool = false, backgroundJob: String? = nil) {
        self.content = content
        self.isError = isError
        self.backgroundJob = backgroundJob
    }

    /// A failed outcome, explained for the model.
    public static func error(_ content: String) -> ToolOutput { ToolOutput(content, isError: true) }
}
