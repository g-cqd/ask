internal import AemiRegex

extension ProviderFailure.Kind {
    /// Whether a refusal's wording says the request exceeded the context window.
    ///
    /// Servers say it in their own words, recorded in diary 14: llama.cpp and Ollama "exceeds the available context
    /// size", OpenAI and vLLM "maximum context length", Anthropic "prompt is too long". The phrases name no provider.
    static func describesContextOverflow(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("exceeds the available context size") || text.contains("maximum context length")
            || text.contains("prompt is too long") || text.contains("context_length_exceeded")
            || (text.contains("context") && text.contains("exceed"))
    }

    /// The window a refusal for length names in its wording: llama.cpp and Ollama "available context size (N
    /// tokens)", OpenAI and vLLM "maximum context length is N tokens", Anthropic "N tokens > M maximum".
    private static let windowPatterns: [Pattern] = [
        #"available context size \((\d+) tokens\)"#, #"maximum context length is (\d+) tokens"#, #"> (\d+) maximum"#
    ]
    .compactMap { try? Pattern($0) }

    static func contextWindow(describedIn message: String) -> Int? {
        // Linear-time patterns; a provider's message is untrusted input.
        for pattern in Self.windowPatterns {
            if let match = pattern.firstMatch(in: message), let range = match.range(ofGroup: 1, in: message),
                let window = Int(message[range])
            {
                return window
            }
        }
        return nil
    }
}
