import Testing

@testable import AskAgentCore

/// What the person is told about the instruction files (roadmap 0028): one line each, what was loaded and what was skipped and why.
@Suite("Each instruction file is described in a line, loaded or skipped")
struct ProjectInstructionsDescriptionTests {
    @Test func `a loaded file says where it came from`() {
        let file = ProjectInstructions.File(path: "/work/AGENTS.md", text: "be brief", skippedBecause: nil)
        #expect(ProjectInstructions.describe([file]) == ["Instructions loaded from /work/AGENTS.md."])
    }

    @Test func `a skipped file says why`() {
        let file = ProjectInstructions.File(path: "/work/CLAUDE.md", text: "", skippedBecause: "it is a symlink")
        #expect(ProjectInstructions.describe([file]) == ["Skipped /work/CLAUDE.md: it is a symlink."])
    }

    @Test func `the lines keep the files' order`() {
        let files = [
            ProjectInstructions.File(path: "/a/AGENTS.md", text: "x", skippedBecause: nil),
            ProjectInstructions.File(path: "/a/b/AGENTS.md", text: "", skippedBecause: "unreadable")
        ]
        #expect(
            ProjectInstructions.describe(files) == [
                "Instructions loaded from /a/AGENTS.md.", "Skipped /a/b/AGENTS.md: unreadable."
            ])
    }

    @Test func `no files, no lines`() {
        #expect(ProjectInstructions.describe([]).isEmpty)
    }
}
