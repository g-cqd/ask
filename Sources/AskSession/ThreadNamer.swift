internal import AskAI
internal import AskAgentCore
internal import AskApple
internal import Foundation

/// A thread's name from a model (roadmap 0195, `threads.names`): two to four words from its task, asked for in one short request.
/// Apple's on-device model (`onDevice`) is given two seconds; a provider's model (`model`, note n20) fifteen, since it goes over the
/// network. Nil where the model is not available, when it is slow or fails, or says nothing usable; the thread is then called by its id.
enum ThreadNamer {
    /// By Apple's on-device model, where it is available.
    static func name(for task: String) async -> String? {
        guard AppleModel.availability().isAvailable else { return nil }
        return await name(for: task, by: AppleProvider(), model: "apple", within: .seconds(2))
    }

    /// By `model` through `provider`, given `within` to answer.
    static func name(
        for task: String,
        by provider: any ModelProvider,
        model: String,
        within limit: Duration
    ) async -> String? {
        let reply = await OneShotReply.text(
            String(task.prefix(600)),
            system: ["Reply with a name of two to four lowercase words for the task you are given, and nothing else."],
            by: provider,
            model: model,
            within: limit
        )
        return reply.flatMap(cleaned)
    }

    /// The first line, without quotes or a final full stop, at most 40 characters; nil when nothing is left.
    static func cleaned(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`.").union(.whitespaces))
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        return trimmed
    }
}
