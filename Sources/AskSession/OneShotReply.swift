internal import AskAI
internal import AskAgentCore

/// One short request answered in text, with no tools and a time limit: a thread's name (roadmap 0195), a definition's model word
/// (roadmap 0063 phase 4). Nil when the model is slow, fails or says nothing.
enum OneShotReply {
    static func text(
        _ prompt: String,
        system: [String] = [],
        by provider: any ModelProvider,
        model: String,
        maxTokens: Int = 64,
        within limit: Duration
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let request = ModelRequest(
                    model: model,
                    maxTokens: maxTokens,
                    systemPrompt: system,
                    messages: [ModelMessage(role: .user, blocks: [.text(prompt)])],
                    tools: []
                )
                var text = ""
                do {
                    for try await event in provider.stream(request) {
                        if case .textDelta(_, let delta) = event { text += delta }
                    }
                } catch { return nil }
                return text.isEmpty ? nil : text
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
