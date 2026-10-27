internal import AskAI
internal import AskTUI
internal import Foundation

/// What `/login ` offers: every way ask can sign in, each as the words that choose it.
enum LoginChoices {
    static let usage =
        "Forms: claude, claude api-key, codex, codex device, codex api-key, agy, copilot-vscode, spettro, mistral-vibe, PROVIDER (an API key), custom NAME URL."

    static func rows() -> [ChoiceRow] {
        var rows = [
            // @dl:accept -- a table of choices: its rows repeat their shape by being rows
            ChoiceRow(label: "claude", detail: "Claude account, in a browser", arguments: "claude"),
            ChoiceRow(label: "claude api-key", detail: "Anthropic API key", arguments: "claude api-key"),
            ChoiceRow(label: "codex", detail: "ChatGPT account (Codex), in a browser", arguments: "codex"),
            ChoiceRow(
                label: "codex device", detail: "ChatGPT account, with a code, no browser here",
                arguments: "codex device"),
            ChoiceRow(label: "codex api-key", detail: "OpenAI API key (stored as openai)", arguments: "codex api-key"),
            ChoiceRow(label: "agy", detail: "Google account for Antigravity", arguments: "agy"),
            ChoiceRow(
                label: CopilotProtocol.name, detail: "GitHub Copilot — VS Code-style (experimental)",
                arguments: CopilotProtocol.name),
            ChoiceRow(label: "spettro", detail: "Spettro, in a browser", arguments: "spettro"),
            ChoiceRow(label: "mistral-vibe", detail: "Mistral Vibe, in a browser", arguments: "mistral-vibe"),
            ChoiceRow(
                label: "custom NAME URL", detail: "any OpenAI-compatible API, with a key", arguments: "custom",
                completes: true)
        ]
        let taken = Set(rows.map(\.arguments)).union(["spettro", "mistral-vibe"])
        for name in ProviderPreset.names where !taken.contains(name) && name != "openai" {
            rows.append(ChoiceRow(label: name, detail: "API key", arguments: name))
        }
        return rows
    }
}
