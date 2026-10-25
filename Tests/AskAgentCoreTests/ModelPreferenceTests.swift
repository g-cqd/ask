import Testing

@testable import AskAgentCore

/// A file's models are an ordered list of words, whatever the file's form, with the parent's model as the fallback.
@Suite("A model preference is the words a file used, in order")
struct ModelPreferenceTests {
    private func preference(_ text: String, toml: Bool = false) -> ModelPreference {
        ModelPreference(DefinitionFile(parsing: text, isTOML: toml))
    }

    @Test func `one alias is one word`() {
        let model = preference("---\nmodel: opus\n---\n")
        #expect(model.tokens == ["opus"] && !model.inheritsParent)
    }

    @Test func `display names with spaces and digits stay whole in a list`() {
        let model = preference("---\nmodel: [\"Claude Opus 5.5\", \"GPT-6 Astra\", \"Claude Sonnet 5\"]\n---\n")
        #expect(model.tokens == ["Claude Opus 5.5", "GPT-6 Astra", "Claude Sonnet 5"])
    }

    @Test func `a comment that names fallbacks adds them after the model, without repeats`() {
        let model = preference(
            "---\nmodel: opus\n# fallback_models: claude-opus-5-5, claude-opus-4-8, sonnet, Opus\n---\n")
        #expect(model.tokens == ["opus", "claude-opus-5-5", "claude-opus-4-8", "sonnet"])
    }

    @Test func `tier lists, with a parenthesised note after them, give their tiers`() {
        let yaml = preference("---\nsubagent: true\n# tier_models: [flash_lite, flash, inherit] (effort: low)\n---\n")
        #expect(yaml.tokens == ["flash_lite", "flash"] && yaml.inheritsParent)
        let vibe = preference(
            "# tier_models = [\"devstral-small-latest\", \"devstral-latest\"] (effort = \"low\")\nname = \"x\"\n",
            toml: true)
        #expect(vibe.tokens == ["devstral-small-latest", "devstral-latest"])
    }

    @Test func `a TOML model with a TOML fallback comment reads the same way`() {
        let model = preference(
            "model = \"gpt-6-luna\"\n# fallback_models = [\"gpt-5.6-luna\", \"gpt-5.5\"]\n", toml: true)
        #expect(model.tokens == ["gpt-6-luna", "gpt-5.6-luna", "gpt-5.5"])
    }

    @Test func `inherit, default and no model at all mean the parent's model`() {
        for text in ["---\nmodel: inherit\n---\n", "---\nmodel: default\n---\n", "---\nname: x\n---\n", "no head"] {
            let model = preference(text)
            #expect(model.inheritsParent && model.tokens.isEmpty, "\(text.debugDescription)")
        }
    }

    @Test func `inherit among names is remembered as a last resort, in any position`() {
        let model = preference("---\nmodel: sonnet, inherit\n---\n")
        #expect(model.tokens == ["sonnet"] && model.inheritsParent)
    }

    @Test func `provider-qualified names are kept as written`() {
        let model = preference("---\nmodel: anthropic/claude-opus-5-5, openai:gpt-6\n---\n")
        #expect(model.tokens == ["anthropic/claude-opus-5-5", "openai:gpt-6"])
    }
}
