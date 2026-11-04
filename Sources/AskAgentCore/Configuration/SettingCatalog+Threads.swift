// The threads settings (roadmap 0195), apart from SettingCatalog.swift to keep its body under the length limit.
extension SettingCatalog {
    static let threads: [Setting] = [
        // @dl:accept -- catalog rows are data, one setting each, as in every other part of the catalog
        row("threads.max", .integer, "4", "4", "How many threads may work at once, from 1 to 16."),
        row("threads.depth", .integer, "3", "3", "How deep threads may nest, from 1 to 8."),
        row(
            "threads.names",
            .choice(ThreadsSection.Names.allCases.map(\.rawValue)),
            #""onDevice""#,
            "onDevice",
            "How a thread is named: by Apple's on-device model from its task where it is available, or numbered."
        ),
        row(
            "threads.mergedShownFor",
            .text,
            #""1d""#,
            "1d",
            "How long a merged thread stays in the sidebar: \"30m\", \"2h\", \"1d\", or \"always\". /threads still lists it."
        ),
        row(
            "threads.questions",
            .choice(ThreadsSection.questionWords),
            #""focus""#,
            "focus",
            "Where a thread's question appears while you are elsewhere: at once, after questionsAfter, or only in its lane."
        ),
        row(
            "threads.questionsAfter",
            .text,
            #""30s""#,
            "30s",
            "How long \"after\" waits before showing a thread's question."
        )
    ]
}
