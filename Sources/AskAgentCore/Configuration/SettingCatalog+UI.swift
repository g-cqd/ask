internal import AskAI

// The ui settings, apart from SettingCatalog.swift to keep each file under the 250-line ceiling.
extension SettingCatalog {
    // @dl:disable near-clone -- the rows below are the catalog's data: a key, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape
    static let ui: [Setting] = [
        row("ui.mouse", .boolean, "true", "true", "ask handles clicks, selection and the wheel."),
        row("ui.copyOnSelect", .boolean, "true", "true", "A finished selection is copied at once."),
        row("ui.tint", .boolean, "true", "true", "Tinted backgrounds for the input, your messages and tool calls."),
        row("ui.separator", .boolean, "true", "true", "A rule between the conversation and the input."),
        row("ui.padding", .boolean, "true", "true", "A row of padding around each block."),
        row("ui.markdown", .boolean, "true", "true", "Markdown drawn everywhere it can be."),
        row("ui.highlight", .boolean, "true", "true", "Fenced code coloured by the language its fence names."),
        row("ui.leaveFinishedJob", .boolean, "true", "true", "When a job you watch ends, go back to the conversation."),
        row(
            "ui.sessionColor",
            words(SessionColorPreference.self),
            #""off""#,
            "off",
            "A colour of the session's own on the status line: always, or only while another ask runs."
        ),
        row("ui.listAllModels", .boolean, "false", "false", "Model lists also show models ask cannot use."),
        row("ui.fold.tools", .boolean, "true", "true", "Tool calls start folded."),
        row("ui.fold.thinking", .boolean, "true", "true", "The model's reasoning starts folded."),
        row("ui.fold.code", .boolean, "true", "true", "Long code blocks start folded."),
        row("ui.fold.codeLines", .integer, "20", "20", "How many lines make a code block long."),
        row(
            "ui.fold.outputLines",
            .integer,
            "200",
            "200",
            "A tool's output with more lines than this keeps its head and tail and folds its middle."
        ),
        row(
            "ui.fold.outputBytes",
            .integer,
            "32768",
            "32768",
            "A tool's output with more bytes than this keeps its head and tail and folds its middle."
        ),
        row("ui.scrollLines", .integer, "3", "3", "Lines per wheel step."),
        row("ui.inputRows", .integer, "6", "6", "How many rows the input grows to before it scrolls."),
        row(
            "ui.sidebar",
            .choice(["closed", "open"]),
            #""closed""#,
            "closed",
            "Whether the runner sidebar starts open."
        ),
        row("ui.inputPrefix", .text, #""> ""#, "none", "Text the input line starts with."),
        row("ui.appearance", words(AppearancePreference.self), #""auto""#, "auto", "Where the tints come from."),
        row(
            "ui.durations",
            .choice(["words", "clock"]),
            #""words""#,
            "words",
            "Elapsed times as 1 hr, 40 min or as 1:40:00."
        ),
        row("ui.spinner", words(SpinnerPreference.self), #""line""#, "line", "The spinner."),
        row(
            "ui.showTimeout",
            words(TimeoutPreference.self),
            #""auto""#,
            "auto",
            "When a command's timeout is written in its header."
        ),
        row(
            "ui.timeoutLabel",
            .text,
            #""timeout""#,
            "timeout",
            "The word in front of a command's timeout, 1 to 8 characters."
        ),
        row("ui.stopKeys", words(InterruptKeysPreference.self), #""both""#, "both", "Which keys stop a running turn."),
        row(
            "ui.stopTwice",
            .structured,
            #"["esc"]"#,
            #"["esc"]"#,
            "The keys that must be pressed twice to stop a turn."
        ),
        row(
            "ui.queuedOnStop",
            words(QueuedAfterInterruptPreference.self),
            #""all""#,
            "all",
            "What happens to queued messages on a stop."
        )
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
