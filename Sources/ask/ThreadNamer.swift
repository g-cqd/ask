internal import AskAI
internal import AskApple
internal import Foundation

/// A thread's name from Apple's on-device model (roadmap 0195, `threads.names` onDevice): two to four words from its task, asked for in
/// one short request and given two seconds. Nil where the model is not available, when it is slow or fails, or says nothing usable;
/// the thread is then called by its id.
enum ThreadNamer {
    static func name(for task: String) async -> String? {
        guard AppleModel.availability().isAvailable else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { await ask(task) }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func ask(_ task: String) async -> String? {
        let request = ModelRequest(
            model: "apple",
            maxTokens: 24,
            systemPrompt: [
                "Reply with a name of two to four lowercase words for the task you are given, and nothing else."
            ],
            messages: [ModelMessage(role: .user, blocks: [.text(String(task.prefix(600)))])],
            tools: []
        )
        var text = ""
        do {
            for try await event in AppleProvider().stream(request) {
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
