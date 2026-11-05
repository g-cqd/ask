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
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await ask(task, provider, model) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func ask(_ task: String, _ provider: any ModelProvider, _ model: String) async -> String? {
        let request = ModelRequest(
            model: model,
            maxTokens: 64,
            systemPrompt: [
                "Reply with a name of two to four lowercase words for the task you are given, and nothing else."
            ],
            messages: [ModelMessage(role: .user, blocks: [.text(String(task.prefix(600)))])],
            tools: []
        )
        var text = ""
        do {
            for try await event in provider.stream(request) {
                if case .textDelta(_, let delta) = event { text += delta }
            }
        } catch { return nil }
        return cleaned(text)
    }

    /// The first line, without quotes or a final full stop, at most 40 characters; nil when nothing is left.
    static func cleaned(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`.").union(.whitespaces))
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        return trimmed
    }
}
