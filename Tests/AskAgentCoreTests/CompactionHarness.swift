import AemiIO
import Foundation
import System

@testable import AskAgentCore

/// A loop over a scripted provider and a fresh session file, for the compaction and window suites.
struct CompactionHarness {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ask-compact-\(UUID().uuidString)")

    func newFile() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
    }

    func loop(_ provider: ScriptedProvider, compactAt: Int?, keepRecentBytes: Int = 1) -> AgentLoop {
        AgentLoop(
            provider: provider, tools: try! ToolRegistry([]),
            settings: AgentSettings(
                model: "claude-x", maximumTokens: 1_024, systemPrompt: ["Be brief."], maximumTurns: 8,
                compactAtTokens: compactAt, keepRecentBytes: keepRecentBytes),
            context: ToolContext(workingDirectory: directory.path))
    }

    /// Each entry's kind, in order.
    func kinds(_ file: SessionRecorder) -> [String] {
        file.tree.entries.map {
            switch $0.payload {
                case .user: "user"
                case .assistant: "assistant"
                case .response: "response"
                case .toolResult: "result"
                case .compaction: "compaction"
            }
        }
    }
}
