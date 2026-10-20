import Testing

@testable import AskAgentCore

/// A model chosen with /model is a layer above every file, variable and flag, and says so.
@Suite("A command-selected model replaces both provider and model and names its own source")
struct ConfigurationSelectionTests {
    private let layered = Configuration.defaults.applying(
        model: "flag-model", provider: "flag-provider", maxTurns: 9, compactAt: nil)

    @Test func `the selection pins provider and model and leaves other settings alone`() {
        let selected = layered.applying(selectedProvider: "pinned", model: "vendor/model:tag", command: "/model")
        #expect(selected.provider.value == "pinned")
        #expect(selected.model.value == "vendor/model:tag")
        #expect(selected.maxTurns == layered.maxTurns)
        #expect(selected.compactAt == layered.compactAt)
    }

    @Test func `both settings name the command as their source, and it reads as this run's`() {
        let selected = layered.applying(selectedProvider: "pinned", model: "m", command: "/model")
        #expect(selected.provider.source == .command("/model"))
        #expect(selected.model.source == .command("/model"))
        #expect(selected.model.source.description == "/model (this run)")
    }

    @Test func `a reload announces the change with the command as its source`() {
        let selected = layered.applying(selectedProvider: "pinned", model: "m", command: "/model")
        let lines = selected.changes(from: layered)
        #expect(lines.contains(#"model: "flag-model" → "m" (/model (this run))"#))
        #expect(lines.contains(#"provider: "flag-provider" → "pinned" (/model (this run))"#))
    }
}
