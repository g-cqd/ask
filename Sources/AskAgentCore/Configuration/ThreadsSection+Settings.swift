// The threads settings (roadmap 0195), each declared once (roadmap 0209).
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension ThreadsSection: DeclaredSection {
    /// A section that sets nothing.
    init() { self.init(max: nil) }

    /// Retired (note n52): a thread merges only by /merge. Still read, so a file that sets it opens.
    static let retired: Set<String> = ["merge"]

    static let settings = SettingTable<ThreadsSection>(
        "threads",
        [
            .number(
                SettingCatalog.row(
                    "threads.max",
                    .integer,
                    "4",
                    "4",
                    "How many threads may work at once, from 1 to 16."
                ),
                \.max
            ),
            .number(
                SettingCatalog.row("threads.depth", .integer, "3", "3", "How deep threads may nest, from 1 to 8."),
                \.depth
            ),
            .choice(
                SettingCatalog.row(
                    "threads.names",
                    .choice(ThreadsSection.Names.allCases.map(\.rawValue)),
                    #""onDevice""#,
                    "onDevice",
                    "How threads and the conversation are named: by Apple's on-device model where it is available, by a model, or numbered."
                ),
                \.names
            ),
            .string(
                SettingCatalog.row(
                    "threads.namesModel",
                    .text,
                    #""""#,
                    "the conversation's model",
                    "The model names \"model\" asks, as /model takes it (\"provider/model\" or a model); empty for the conversation's own."
                ),
                \.namesModel
            ),
            .string(
                SettingCatalog.row(
                    "threads.model",
                    .text,
                    #""provider/model""#,
                    "the conversation's model",
                    "The model threads work and write their summaries with, as /model takes it; empty for the conversation's own."
                ),
                \.model
            ),
            .string(
                SettingCatalog.row(
                    "threads.summaryInstructions",
                    .text,
                    #""List every file you changed.""#,
                    "none",
                    "What a thread's summary should also hold, added after the standard merge instruction."
                ),
                \.summaryInstructions
            ),
            .string(
                SettingCatalog.row(
                    "threads.mergedShownFor",
                    .text,
                    #""1d""#,
                    "1d",
                    "How long a merged thread stays in the sidebar: \"30m\", \"2h\", \"1d\", or \"always\". /threads still lists it."
                ),
                \.mergedShownFor
            ),
            .word(
                SettingCatalog.row(
                    "threads.questions",
                    .choice(ThreadsSection.questionWords),
                    #""focus""#,
                    "focus",
                    "Where a thread's question appears while you are elsewhere: at once, after questionsAfter, or only in its lane."
                ),
                \.questions,
                ThreadsSection.questionWords
            ),
            .string(
                SettingCatalog.row(
                    "threads.questionsAfter",
                    .text,
                    #""30s""#,
                    "30s",
                    "How long \"after\" waits before showing a thread's question."
                ),
                \.questionsAfter
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
