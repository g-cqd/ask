internal import AskTUI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAgentCore
@testable import AskSession

/// What an organisation requires (ADR-0168) holds while ask runs: `/model` and `/thinking` refuse to change it for the run, and the
/// `/config` editor shows a required row as not editable and refuses to save it.
@Suite("Required settings hold while ask runs")
struct ManagedCommandsTests {
    private static let document = "/Library/Application Support/ask/requirements.json"

    private func requiring(_ keys: [String], in fixture: ConversationFixture) {
        fixture.conversation.current.withLock { state in
            for key in keys { state.settings.configuration.requiredKeys[key] = Self.document }
        }
    }

    private func errors(_ fixture: ConversationFixture) -> [String] {
        fixture.updates.compactMap { update in if case .notice(let text, isError: true) = update { text } else { nil } }
    }

    @Test func `model and thinking are not changed for the run when required`() async throws {
        let fixture = try await ConversationFixture()
        requiring(["model", "thinking"], in: fixture)
        let before = fixture.conversation.current.withLock { $0.settings.model }
        await fixture.conversation.model(arguments: "anthropic claude-other-2", update: fixture.update)
        await fixture.conversation.thinking(arguments: "high", update: fixture.update)
        #expect(fixture.conversation.current.withLock { $0.settings.model } == before)
        #expect(
            errors(fixture) == [
                "Model not changed: your organisation requires it (\(Self.document)).",
                "Thinking not changed: your organisation requires it (\(Self.document))."
            ]
        )
    }

    @Test func `a required row is not editable, is named, and is not saved`() async throws {
        let fixture = try await ConversationFixture()
        requiring(["ui.tint"], in: fixture)
        let user = fixture.conversation.configEditorPath(.user).path
        let editor = try ConfigEditor(path: user, isProject: false)
        let snapshot = AgentConversation.configSnapshot(editor, trustPath: "/nowhere") {
            fixture.conversation.requirement(of: $0)
        }
        let tint = try #require(snapshot.rows.first { $0.path == ["ui", "tint"] })
        #expect(!tint.editable)
        #expect(snapshot.rows.contains { $0.path != ["ui", "tint"] && $0.editable }, "other rows stay editable")
        #expect(snapshot.warnings.contains { $0.contains("ui.tint (\(Self.document))") })
        await fixture.conversation.commitConfig(
            scope: "user",
            path: ["ui", "tint"],
            value: "false",
            update: fixture.update
        )
        #expect(errors(fixture) == ["Not saved: your organisation requires ui.tint (\(Self.document))."])
        #expect(!FileManager.default.fileExists(atPath: user))
    }
}
