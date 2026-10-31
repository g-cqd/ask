internal import AskAI

/// Every setting a configuration file may hold, once (roadmaps 0096 and 0118): its path, its type, an example value, its default in
/// words, whether only the person's own file may set it, and one line of help. The `/config` editor's rows and the generated
/// `docs/config.example.jsonc` come from here, and tests hold it to the keys the parser accepts.
enum SettingCatalog {
    /// What a value is.
    enum Kind: Sendable, Equatable {
        case boolean
        /// One of these words.
        case choice([String])
        case integer
        case text
        /// A list, or a more complex value (a scope, a number or a share); shown, not edited.
        case structured
    }

    struct Setting: Sendable, Equatable {
        let path: [String]
        let kind: Kind
        /// A valid value, as JSON, for the example file.
        let example: String
        /// What it is when unset, in words.
        let defaultValue: String
        /// Whether only the person's own file may set it, not a project's.
        let userOnly: Bool
        let help: String
    }

    private static func row(
        _ path: String, _ kind: Kind, _ example: String, _ defaultValue: String, user: Bool = false, _ help: String
    ) -> Setting {
        Setting(
            path: path.split(separator: ".").map(String.init), kind: kind, example: example, defaultValue: defaultValue,
            userOnly: user, help: help)
    }

    private static func words<Choice: RawRepresentable & CaseIterable>(_: Choice.Type) -> Kind
    where Choice.RawValue == String {
        .choice(Choice.allCases.map(\.rawValue))
    }

    static let all: [Setting] = top + ui + sandbox + approvals + skills + environment

    // @dl:disable near-clone -- the rows below are the catalog's data: a key, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape

    private static let top: [Setting] = [
        row(
            "model", .text, #""a-model-id""#, "the provider's default",
            "The model to use; /model changes it for the session."),
        row("provider", .text, #""a-connection""#, "the first account that can answer", "The connection to use."),
        row("thinking", words(ThinkingLevel.self), #""default""#, "default", "How much the model thinks."),
        row(
            "maxTurns", .structured, "100", "100 in the sandbox, no limit with --no-sandbox",
            "The most model requests one prompt may make, or null for no limit."),
        row(
            "compactAt", .structured, "0.75", "0.75",
            "When the conversation is summarised: a share of the window up to 1, or a number of tokens."),
        row("keepAwake", words(KeepAwakeMode.self), #""working""#, "working", "When ask keeps the Mac from sleeping."),
        row("keepDisplayAwake", .boolean, "false", "false", "Whether the display stays on too."),
        row(
            "credentials", words(CredentialStorage.self), #""auto""#, "auto", user: true,
            "Where keys and sign-in tokens are kept.")
    ]

    private static let ui: [Setting] = [
        row("ui.mouse", .boolean, "true", "true", "ask handles clicks, selection and the wheel."),
        row("ui.copyOnSelect", .boolean, "true", "true", "A finished selection is copied at once."),
        row("ui.tint", .boolean, "true", "true", "Tinted backgrounds for the input, your messages and tool calls."),
        row("ui.separator", .boolean, "true", "true", "A rule between the conversation and the input."),
        row("ui.padding", .boolean, "true", "true", "A row of padding around each block."),
        row("ui.markdown", .boolean, "true", "true", "Markdown drawn everywhere it can be."),
        row("ui.leaveFinishedJob", .boolean, "true", "true", "When a job you watch ends, go back to the conversation."),
        row(
            "ui.sessionColor", words(SessionColorPreference.self), #""off""#, "off",
            "A colour of the session's own on the status line: always, or only while another ask runs."),
        row("ui.listAllModels", .boolean, "false", "false", "Model lists also show models ask cannot use."),
        row("ui.fold.tools", .boolean, "true", "true", "Tool calls start folded."),
        row("ui.fold.thinking", .boolean, "true", "true", "The model's reasoning starts folded."),
        row("ui.fold.code", .boolean, "true", "true", "Long code blocks start folded."),
        row("ui.fold.codeLines", .integer, "20", "20", "How many lines make a code block long."),
        row("ui.scrollLines", .integer, "3", "3", "Lines per wheel step."),
        row("ui.inputRows", .integer, "6", "6", "How many rows the input grows to before it scrolls."),
        row(
            "ui.sidebar", .choice(["closed", "open"]), #""closed""#, "closed", "Whether the runner sidebar starts open."
        ),
        row("ui.inputPrefix", .text, #""> ""#, "none", "Text the input line starts with."),
        row("ui.appearance", words(AppearancePreference.self), #""auto""#, "auto", "Where the tints come from."),
        row(
            "ui.durations", .choice(["words", "clock"]), #""words""#, "words",
            "Elapsed times as 1 hr, 40 min or as 1:40:00."),
        row("ui.spinner", words(SpinnerPreference.self), #""line""#, "line", "The spinner."),
        row(
            "ui.showTimeout", words(TimeoutPreference.self), #""auto""#, "auto",
            "When a command's timeout is written in its header."),
        row(
            "ui.timeoutLabel", .text, #""timeout""#, "timeout",
            "The word in front of a command's timeout, 1 to 8 characters."),
        row("ui.stopKeys", words(InterruptKeysPreference.self), #""both""#, "both", "Which keys stop a running turn."),
        row(
            "ui.stopTwice", .structured, #"["esc"]"#, #"["esc"]"#, "The keys that must be pressed twice to stop a turn."
        ),
        row(
            "ui.queuedOnStop", words(QueuedAfterInterruptPreference.self), #""all""#, "all",
            "What happens to queued messages on a stop.")
    ]

    private static let sandbox: [Setting] = [
        row("sandbox.write", .structured, #""workspace""#, "workspace", "Where tools and commands may write."),
        row("sandbox.read", .structured, #""anywhere""#, "anywhere", "Where they may read."),
        row("sandbox.network", .choice(["none", "localhost", "any"]), #""any""#, "any", "How far commands reach."),
        row("sandbox.hide", .structured, #"["~/notes"]"#, "none", "More paths to hide."),
        row(
            "sandbox.readable", .structured, #"["~/.aws"]"#, "none", user: true,
            "Protected paths to make readable again."),
        row(
            "sandbox.writable", .structured, #"["~/.zshrc"]"#, "none", user: true,
            "Protected paths to make writable again.")
    ]

    private static let approvals: [Setting] = [
        row(
            "approvals.default", .choice(["ask", "allow"]), #""ask""#, "ask", user: true,
            "What a call no list names does."),
        row("approvals.allow", .structured, #"["mcp__docs__*"]"#, "none", user: true, "Tools that run without asking."),
        row("approvals.ask", .structured, #"["write"]"#, "none", user: true, "Tools that always ask."),
        row(
            "approvals.remember", words(ApprovalsSection.Scope.self), #""none""#, "none", user: true,
            "What an \"always\" answer could write back to this file.")
    ]

    private static let skills: [Setting] = [
        row(
            "skills.enabled", .boolean, "true", "true",
            "Whether skills are offered; a project's file may only turn them off."),
        row("skills.maxListed", .integer, "32", "32", user: true, "How many skills are listed to the model."),
        row(
            "skills.sources", .structured, #"["agents", "user"]"#, "every harness", user: true,
            "Where to look, by harness.")
    ]

    private static let environment: [Setting] = [
        row(
            "environment.withhold", .structured, #"["AWS_*"]"#, "ask's credential variables",
            "More variables kept from commands."),
        row(
            "environment.pass", .structured, #"["GH_TOKEN"]"#, "none", user: true,
            "Withheld variables commands get anyway."),
        row(
            "environment.shell", .text, #""zsh""#, "zsh, else bash, else your login shell", user: true,
            "The shell commands run in.")
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
