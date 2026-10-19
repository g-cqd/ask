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
    static func contextWindow(describedIn message: String) -> Int? {
        let patterns = [
            /available context size \((\d+) tokens\)/, /maximum context length is (\d+) tokens/, /> (\d+) maximum/
        ]
        for pattern in patterns {
            if let match = message.firstMatch(of: pattern), let window = Int(match.output.1) { return window }
        }
        return nil
    }
}
