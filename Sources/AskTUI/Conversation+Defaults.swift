internal import TerminalKitCodecs
internal import TerminalKitInput

extension Conversation {
    /// Without pictures: a conversation that takes none starts the text alone.
    public func start(_ prompt: String, images: [ToolImage], update: @escaping @Sendable (ConversationUpdate) -> Void)
        -> Task<Void, Never>
    {
        start(prompt, update: update)
    }

    public func enqueue(_ text: String, images: [ToolImage], id: Int, followUp: Bool) {
        enqueue(text, id: id, followUp: followUp)
    }

    public func preparePicture(_ bytes: [UInt8]) async -> PicturePreparation {
        .refused("this conversation takes no pictures")
    }

    public func withdraw(_ id: Int) -> Bool { false }

    /// No in-flight input; the screen starts unacknowledged messages after the current run ends.
    public func enqueue(_ text: String, id: Int, followUp: Bool) {}

    /// Never asks, so never answered.
    public func answer(approval id: Int, with choice: ApprovalChoice) {}

    /// Never asks questions, so never answered.
    public func answer(questions id: Int, with answers: [QuestionAnswer]?) {}

    /// No commands of its own.
    public var commands: [SlashCommand] { [] }

    /// No files to offer.
    public func projectFiles() async -> ProjectFiles { ProjectFiles() }

    /// No lists.
    public func choices(for command: String) async -> [ChoiceRow] { [] }

    public func commitConfig(
        scope: String,
        path: [String],
        value: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async {
        update(.notice("Configuration editing is unavailable.", isError: true))
    }

    /// Never asks for input, so never answered.
    public func answer(input id: Int, with text: String?) {}

    /// Without the host's read policy, rendering performs no filesystem lookup.
    public func replyPathExists(_ path: String) -> Bool { false }

    /// No skills to offer.
    public func skillCommands() async -> [SlashCommand] { [] }

    /// No runners, so no output.
    public func runnerOutput(_ id: String) async -> String { "" }

    /// No shell to run it in.
    public func shell(
        _ command: String,
        sends: Bool,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        Task { update(.notice("There is no shell here to run \(command).", isError: true)) }
    }

    /// No openers: the system's choice.
    public func opening(for uri: String) -> LinkOpening { .system }

    /// No openers, so no command to run.
    // @dl:accept -- a protocol's defaults that do nothing differ only in what they are not asked to do
    public func runOpener(for uri: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {}

    /// No threads, so none to stop.
    public func stopThread(_ id: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {}

    /// No threads, so none to name.
    public func renameThread(_ id: String, to title: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {
    }

    /// No threads, so none to merge.
    public func mergeThread(_ id: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {}

    /// Nothing follows which lane is shown.
    public func laneShown(_ id: String?) {}

    /// No threads, so nothing to send to.
    public func sendToThread(_ id: String, text: String, update: @escaping @Sendable (ConversationUpdate) -> Void) {}

    /// No threads, so none to start from.
    public func startThread(
        _ text: String,
        from parent: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) async {}

    /// A conversation without live runners supplies its one snapshot.
    public func watchRunnerOutput(_ id: String, update: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        Task { update(await runnerOutput(id)) }
    }

    /// A conversation without process jobs has no snapshots to send.
    public func watchJob(_ id: String, update: @escaping @Sendable (JobUpdate) -> Void) -> Task<Void, Never> {
        Task {}
    }

    /// No command to send.
    public func sendCommandToBackground() -> Bool { false }

    /// Nothing to watch.
    public func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>? { nil }

    /// Beside a turn as alone, for a conversation that does not tell them apart: the end of run is not passed on.
    public func command(
        _ name: String,
        arguments: String,
        beside: Bool,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        guard beside else { return command(name, arguments: arguments, update: update) }
        return command(name, arguments: arguments) { item in
            if case .runEnded = item { return update(.besideEnded) }
            update(item)
        }
    }

    /// Ends at once, saying the command is unknown. A conversation with no commands is never asked to run one.
    public func command(
        _ name: String,
        arguments: String,
        update: @escaping @Sendable (ConversationUpdate) -> Void
    ) -> Task<Void, Never> {
        Task {
            update(.notice("There is no command /\(name).", isError: true))
            update(.runEnded)
        }
    }
}
