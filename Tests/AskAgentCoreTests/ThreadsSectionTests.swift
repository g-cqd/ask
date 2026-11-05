import Testing

@testable import AskAgentCore

/// The `threads` section (roadmap 0195): its limits, and how long a merged thread stays in the sidebar.
@Suite("The threads section reads its limits and how long merged threads stay listed")
struct ThreadsSectionTests {
    private func threads(_ json: String) throws -> ThreadsSection? {
        try ConfigurationFile.parse(Array(#"{"threads": \#(json)}"#.utf8), path: "test").threads
    }

    @Test func `mergedShownFor takes minutes, hours, days, or always`() throws {
        #expect(try threads(#"{"mergedShownFor": "30m"}"#)?.mergedListing == .seconds(1_800))
        #expect(try threads(#"{"mergedShownFor": "2h"}"#)?.mergedListing == .seconds(7_200))
        #expect(try threads(#"{"mergedShownFor": "1d"}"#)?.mergedListing == .seconds(86_400))
        #expect(try threads(#"{"mergedShownFor": "always"}"#)?.mergedListing == nil, "always: never left out")
        #expect(ThreadsSection().mergedListing == .seconds(86_400), "a day when nothing says")
    }

    @Test func `anything else is refused with what it takes`() {
        for value in ["soon", "0m", "5", "-1h", "1w"] {
            #expect(throws: ConfigurationError.self, "\(value)") { try threads(#"{"mergedShownFor": "\#(value)"}"#) }
        }
    }

    @Test func `questions takes focus, after or lane, and after waits questionsAfter`() throws {
        #expect(ThreadsSection().whereQuestions == .focus, "focus when nothing says")
        #expect(try threads(#"{"questions": "lane"}"#)?.whereQuestions == .lane)
        #expect(
            try threads(#"{"questions": "after"}"#)?.whereQuestions == .after(.seconds(30)),
            "after 30 s when nothing says"
        )
        #expect(
            try threads(#"{"questions": "after", "questionsAfter": "2m"}"#)?.whereQuestions == .after(.seconds(120))
        )
        #expect(try threads(#"{"questionsAfter": "45s"}"#)?.questionsAfter == "45s")
        #expect(throws: ConfigurationError.self) { try threads(#"{"questions": "soon"}"#) }
        #expect(throws: ConfigurationError.self) { try threads(#"{"questionsAfter": "always"}"#) }
    }

    @Test func `names may be a model, the one namesModel says or the conversation's own`() throws {
        #expect(try threads(#"{"names": "model"}"#)?.naming == .model)
        #expect(
            try threads(#"{"names": "model"}"#)?.namingModel == nil,
            "the conversation's own model when nothing says"
        )
        #expect(
            try threads(#"{"names": "model", "namesModel": "anthropic/claude-haiku-4-5"}"#)?.namingModel
                == "anthropic/claude-haiku-4-5"
        )
        #expect(try threads(#"{"namesModel": "  "}"#)?.namingModel == nil, "blank is the conversation's own")
        let layered = ThreadsSection().layered(with: try #require(try threads(#"{"namesModel": "haiku"}"#)))
        #expect(layered.namingModel == "haiku", "a later file's namesModel layers over an earlier one")
    }

    @Test func `summaryInstructions follow the merge instruction, and blank adds nothing`() throws {
        let section = try #require(try threads(#"{"summaryInstructions": "List every file you touched."}"#))
        #expect(section.summaryAddition == "List every file you touched.")
        #expect(ThreadsSection().summaryAddition == nil)
        #expect(try threads(#"{"summaryInstructions": "  "}"#)?.summaryAddition == nil)
        let instruction = AgentLoop.mergeInstruction(adding: section.summaryAddition)
        #expect(
            instruction.hasPrefix(AgentLoop.mergeInstruction) && instruction.hasSuffix("List every file you touched.")
        )
        #expect(AgentLoop.mergeInstruction(adding: nil) == AgentLoop.mergeInstruction)
        let layered = ThreadsSection().layered(with: section)
        #expect(layered.summaryAddition == "List every file you touched.")
    }

    @Test func `model is the threads' own, as /model reads it, and blank is the conversation's`() throws {
        #expect(ThreadsSection().threadModel == nil)
        #expect(try threads(#"{"model": "anthropic/claude-haiku-4-5"}"#)?.threadModel == "anthropic/claude-haiku-4-5")
        #expect(try threads(#"{"model": " "}"#)?.threadModel == nil)
        let layered = ThreadsSection().layered(with: try #require(try threads(#"{"model": "haiku"}"#)))
        #expect(layered.threadModel == "haiku")
    }
}
