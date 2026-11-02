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

    static func row(
        _ path: String,
        _ kind: Kind,
        _ example: String,
        _ defaultValue: String,
        user: Bool = false,
        _ help: String
    ) -> Setting {
        Setting(
            path: path.split(separator: ".").map(String.init),
            kind: kind,
            example: example,
            defaultValue: defaultValue,
            userOnly: user,
            help: help
        )
    }

    static func words<Choice: RawRepresentable & CaseIterable>(_: Choice.Type) -> Kind
    where Choice.RawValue == String {
        .choice(Choice.allCases.map(\.rawValue))
    }

    static let all: [Setting] = top + ui + sandbox + approvals + hooks + skills + environment

    // @dl:disable near-clone -- the rows below are the catalog's data: a key, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape

    private static let top: [Setting] = [
        row(
            "model",
            .text,
            #""a-model-id""#,
            "the provider's default",
            "The model to use; /model changes it for the session."
        ),
        row("provider", .text, #""a-connection""#, "the first account that can answer", "The connection to use."),
        row("thinking", words(ThinkingLevel.self), #""default""#, "default", "How much the model thinks."),
        row(
            "maxTurns",
            .structured,
            "100",
            "100 in the sandbox, no limit with --no-sandbox",
            "The most model requests one prompt may make, or null for no limit."
        ),
        row(
            "compactAt",
            .structured,
            "0.75",
            "0.75",
            "When the conversation is summarised: a share of the window up to 1, or a number of tokens."
        ),
        row("keepAwake", words(KeepAwakeMode.self), #""working""#, "working", "When ask keeps the Mac from sleeping."),
        row("keepDisplayAwake", .boolean, "false", "false", "Whether the display stays on too."),
        row(
            "sessionEncryption",
            words(SessionEncryptionMode.self),
            #""on""#,
            "asked at first start",
            "Whether new sessions are encrypted: on, off, or asked when each begins."
        ),
        row("sessionCompression", .boolean, "false", "false", "Whether session files are compressed."),
        row(
            "taskScope",
            words(TaskScope.self),
            #""session""#,
            "session",
            "A task list for each session, or one for the workspace."
        ),
        row(
            "sessionPassword",
            words(SessionPasswordMode.self),
            #""remember""#,
            "asked at first start",
            "Whether the key the password opens is kept in the keychain, or the password asked at every start."
        ),
        row(
            "credentials",
            words(CredentialStorage.self),
            #""auto""#,
            "auto",
            user: true,
            "Where keys and sign-in tokens are kept."
        ),
        row(
            "modelScopes",
            .structured,
            #"[{"path": "~/work", "providers": ["work"]}]"#,
            "none",
            user: true,
            "Which providers serve a repository, by its path, remote or git identity; the first rule that matches decides."
        ),
        row(
            "presets",
            .structured,
            #"["swift"]"#,
            "none",
            "Sets of MCP servers ask knows: swift connects apple-docs and swift-search."
        )
    ]

    private static let sandbox: [Setting] = [
        row("sandbox.write", .structured, #""workspace""#, "workspace", "Where tools and commands may write."),
        row("sandbox.read", .structured, #""anywhere""#, "anywhere", "Where they may read."),
        row(
            "sandbox.network",
            .choice(["none", "localhost", "provider", "any"]),
            #""any""#,
            "any",
            "How far commands reach."
        ),
        row("sandbox.hide", .structured, #"["~/notes"]"#, "none", "More paths to hide."),
        row(
            "sandbox.readable",
            .structured,
            #"["~/.aws"]"#,
            "none",
            user: true,
            "Protected paths to make readable again."
        ),
        row(
            "sandbox.writable",
            .structured,
            #"["~/.zshrc"]"#,
            "none",
            user: true,
            "Protected paths to make writable again."
        )
    ]

    private static let approvals: [Setting] = [
        row(
            "approvals.default",
            .choice(["ask", "allow"]),
            #""ask""#,
            "ask",
            user: true,
            "What a call no list names does."
        ),
        row("approvals.allow", .structured, #"["mcp__docs__*"]"#, "none", user: true, "Tools that run without asking."),
        row("approvals.ask", .structured, #"["write"]"#, "none", user: true, "Tools that always ask."),
        row(
            "approvals.remember",
            words(ApprovalsSection.Scope.self),
            #""none""#,
            "none",
            user: true,
            "What an \"always\" answer could write back to this file."
        )
    ]

    private static let skills: [Setting] = [
        row(
            "skills.enabled",
            .boolean,
            "true",
            "true",
            "Whether skills are offered; a project's file may only turn them off."
        ),
        row("skills.maxListed", .integer, "32", "32", user: true, "How many skills are listed to the model."),
        row(
            "skills.sources",
            .structured,
            #"["agents", "user"]"#,
            "every harness",
            user: true,
            "Where to look, by harness."
        )
    ]

    private static let environment: [Setting] = [
        row(
            "environment.withhold",
            .structured,
            #"["AWS_*"]"#,
            "ask's and well-known credential variables",
            "More variables kept from commands."
        ),
        row(
            "environment.pass",
            .structured,
            #"["GH_TOKEN"]"#,
            "none",
            user: true,
            "Withheld variables commands get anyway."
        ),
        row(
            "environment.shell",
            .text,
            #""zsh""#,
            "the first bash on your PATH, else /bin/bash, else ksh, sh or dash, else your login shell",
            user: true,
            "The shell commands run in."
        )
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
