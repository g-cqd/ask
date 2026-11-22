internal import AskCore

// The ui settings, second half of the catalog's order: folds, the input, the sidebar, the status line and stopping a turn.
extension UISection {
    // @dl:disable near-clone -- the rows below are the ui settings' data: a key, its field, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape
    static let layout: [SettingDeclaration<UISection>] = [
        .flag(SettingCatalog.row("ui.fold.tools", .boolean, "true", "true", "Tool calls start folded."), \.foldTools),
        .flag(
            SettingCatalog.row("ui.fold.thinking", .boolean, "true", "true", "The model's reasoning starts folded."),
            \.foldThinking
        ),
        .flag(
            SettingCatalog.row("ui.fold.code", .boolean, "true", "true", "Long code blocks start folded."),
            \.foldCode
        ),
        .number(
            SettingCatalog.row("ui.fold.codeLines", .integer, "20", "20", "How many lines make a code block long."),
            \.codeFoldLines
        ),
        .number(
            SettingCatalog.row(
                "ui.fold.outputLines",
                .integer,
                "200",
                "200",
                "A tool's output with more lines than this keeps its head and tail and folds its middle."
            ),
            \.outputFoldLines
        ),
        .number(
            SettingCatalog.row(
                "ui.fold.outputBytes",
                .integer,
                "32768",
                "32768",
                "A tool's output with more bytes than this keeps its head and tail and folds its middle."
            ),
            \.outputFoldBytes
        ),
        .number(SettingCatalog.row("ui.scrollLines", .integer, "3", "3", "Lines per wheel step."), \.scrollLines),
        .number(
            SettingCatalog.row(
                "ui.inputRows",
                .integer,
                "6",
                "6",
                "How many rows the input grows to before it scrolls."
            ),
            \.promptRows
        ),
        .either(
            SettingCatalog.row(
                "ui.sidebar",
                .choice(["closed", "open"]),
                #""closed""#,
                "closed",
                "Whether the runner sidebar starts open."
            ),
            \.sidebarOpen,
            "open",
            "closed"
        ),
        .either(
            SettingCatalog.row(
                "ui.sidebarJobs",
                .choice(["tree", "section"]),
                #""tree""#,
                "tree",
                "Where the sidebar lists a thread's jobs: under the thread, or with every job in the Jobs section. /sidebar jobs switches."
            ),
            \.sidebarJobsInTree,
            "tree",
            "section"
        ),
        .word(
            SettingCatalog.row(
                "ui.sidebarLayout",
                .choice(UISection.sidebarLayouts),
                #""adaptive""#,
                "adaptive",
                "Where the open sidebar goes: beside the transcript, in the bottom band with the input, or the band where the other would leave the transcript under 100 columns."
            ),
            \.sidebarLayout,
            UISection.sidebarLayouts
        ),
        .text(
            SettingCatalog.row("ui.inputPrefix", .text, #""> ""#, "none", "Text the input line starts with."),
            \.prompt
        ) {
            container,
            key,
            _ in
            try container.decode(String.self, forKey: key)
        },
        .choice(
            SettingCatalog.row(
                "ui.appearance",
                SettingCatalog.words(Appearance.self),
                #""auto""#,
                "auto",
                "Where the tints come from."
            ),
            \.appearance
        ),
        .either(
            SettingCatalog.row(
                "ui.durations",
                .choice(["words", "clock"]),
                #""words""#,
                "words",
                "Elapsed times as 1 hr, 40 min or as 1:40:00."
            ),
            \.localizedDurations,
            "words",
            "clock"
        ),
        .choice(
            SettingCatalog.row(
                "ui.spinner",
                SettingCatalog.words(SpinnerStyle.self),
                #""line""#,
                "line",
                "The spinner."
            ),
            \.spinner
        ),
        .choice(
            SettingCatalog.row(
                "ui.statusPath",
                SettingCatalog.words(StatusPathForm.self),
                #""home""#,
                "folder",
                "The folder ask works in, on the status line: its last folder, from home, in full, or off."
            ),
            \.statusPath
        ),
        .choice(
            SettingCatalog.row(
                "ui.statusPathSide",
                SettingCatalog.words(StatusPathSide.self),
                #""trailing""#,
                "leading",
                "Where that folder sits: right after the mark, or last."
            ),
            \.statusPathSide
        ),
        .choice(
            SettingCatalog.row(
                "ui.showTimeout",
                SettingCatalog.words(TimeoutDisplay.self),
                #""auto""#,
                "auto",
                "When a command's timeout is written in its header."
            ),
            \.timeout
        ),
        .text(
            SettingCatalog.row(
                "ui.timeoutLabel",
                .text,
                #""timeout""#,
                "timeout",
                "The word in front of a command's timeout, 1 to 8 characters."
            ),
            \.timeoutLabel
        ) { try ConfigurationFile.decodeLabel($0, key: $1, named: $2) },
        .choice(
            SettingCatalog.row(
                "ui.stopKeys",
                SettingCatalog.words(InterruptKeys.self),
                #""both""#,
                "both",
                "Which keys stop a running turn."
            ),
            \.interruptKeys
        ),
        stopTwice,
        .choice(
            SettingCatalog.row(
                "ui.queuedOnStop",
                SettingCatalog.words(QueuedAfterInterrupt.self),
                #""all""#,
                "all",
                "What happens to queued messages on a stop."
            ),
            \.interruptSendsQueued
        )
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone

    /// `ui.stopTwice`: the keys that must be pressed twice to stop a turn, `"esc"` and `"ctrl-c"`, kept as two fields. Written back as
    /// the pair, the field a file did not set at its default (Esc twice, Ctrl+C once).
    private static let stopTwice = SettingDeclaration<UISection>(
        row: SettingCatalog.row(
            "ui.stopTwice",
            .structured,
            #"["esc"]"#,
            #"["esc"]"#,
            "The keys that must be pressed twice to stop a turn."
        ),
        merge: .replaces,
        read: { section, container, key, name in
            let keys = try container.decode([String].self, forKey: key)
            for key in keys where key != "esc" && key != "ctrl-c" {
                throw ConfigurationFile.BadValue(key: name, value: key)
            }
            section.escapeInterruptRequiresConfirmation = keys.contains("esc")
            section.abortTurnRequiresConfirmation = keys.contains("ctrl-c")
        },
        write: { section in
            guard section.escapeInterruptRequiresConfirmation != nil || section.abortTurnRequiresConfirmation != nil
            else {
                return nil
            }
            let keys = [
                ("esc", section.escapeInterruptRequiresConfirmation ?? true),
                ("ctrl-c", section.abortTurnRequiresConfirmation ?? false)
            ]
            let pressedTwice = keys.filter(\.1).map(\.0)
            return pressedTwice.isEmpty ? "none" : pressedTwice.joined(separator: ", ")
        },
        layer: { section, later in
            if let esc = later.escapeInterruptRequiresConfirmation { section.escapeInterruptRequiresConfirmation = esc }
            if let ctrlC = later.abortTurnRequiresConfirmation { section.abortTurnRequiresConfirmation = ctrlC }
        }
    )
}
