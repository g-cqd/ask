import Testing

@testable import AskTUI

/// What the picker lists for what was typed: prefix matches first (the prototype once ranked `explorer` above `reviewer` for `re`),
/// then names that contain it, then summaries that mention it, each in the order the commands were given.
@Suite("The picker ranks a prefix of a name above a name above a summary")
struct PickerRankingTests {
    private let commands = commandTable(
        """
        help | List commands.
        quit | Leave ask.
        config | Show the settings.
        compact | Compact the conversation.
        reload | Reload the configuration and the binary.
        resume | Resume another session.
        """)

    private func names(_ query: String, in list: [SlashCommand]? = nil) -> [String] {
        PickerRanking.rank(list ?? commands, query: query).map(\.name)
    }

    @Test func `an empty query lists everything in the given order`() {
        #expect(names("") == ["help", "quit", "config", "compact", "reload", "resume"])
    }

    @Test func `prefix matches come first, then names that contain it, then summaries`() {
        #expect(names("co") == ["config", "compact", "help", "reload"])
        #expect(names("fig") == ["config", "reload"], "a name containing it, then a summary that does")
        #expect(names("re") == ["reload", "resume"])
    }

    @Test func `a prefix beats a substring even when the substring came first`() {
        let list = commandTable("explorer | x\nreviewer | y")
        #expect(names("re", in: list) == ["reviewer", "explorer"])
    }

    @Test func `matching ignores case, and nothing matches nothing`() {
        #expect(names("CO") == names("co"))
        #expect(names("zzz").isEmpty)
        #expect(names("co", in: []).isEmpty)
    }

    @Test func `a command appears once however many ways it matches`() {
        let list = commandTable("model | Choose a model for the model run.")
        #expect(names("model", in: list) == ["model"])
    }
}
