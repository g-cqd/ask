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

    /// An output with this content.
    public init(_ content: String, isError: Bool = false, backgroundJob: String? = nil) {
        self.content = content
        self.isError = isError
        self.backgroundJob = backgroundJob
    }

    /// A failed outcome, explained for the model.
    public static func error(_ content: String) -> ToolOutput { ToolOutput(content, isError: true) }
}
