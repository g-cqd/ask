/// Where a tool result's pictures go on the Antigravity wire, and which of its models take them (roadmap 0084).
enum AgyImagePlacement {
    /// Whether this model takes pictures inside the function response (`functionResponse.parts`), as Gemini CLI does for Gemini 3 and
    /// as `gemini-3-flash` and `gemini-3.8-flash-medium` accepted live; the rest get `inlineData` parts after the responses, which
    /// `gemini-3.5-flash-lite` and Claude accepted live (diary 2026-10-28-08).
    static func nests(model: String) -> Bool { model.hasPrefix("gemini-3") }

    /// Whether the model takes images, from its name: Gemini and Claude do, GPT-OSS does not, anything else is unknown.
    static func accepts(model: String) -> Bool? {
        if model.hasPrefix("gemini-") || model.hasPrefix("claude-") { return true }
        if model.hasPrefix("gpt-oss") { return false }
        return nil
    }
}
