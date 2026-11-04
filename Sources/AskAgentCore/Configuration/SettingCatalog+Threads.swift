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
        )
    ]
}
