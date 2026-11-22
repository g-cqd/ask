internal import AskAI

// The keys at the top of a configuration file that hold one value, each declared once (roadmap 0209): its catalog row, how a file's
// value is read and how it is written back. The sections (`ui`, `sandbox`, …) are declared in their own tables.
// @dl:disable near-clone -- a table of settings is data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension ConfigurationFile {
    static let settings = SettingTable<ConfigurationFile>(
        "",
        [
            .string(
                SettingCatalog.row(
                    "model",
                    .text,
                    #""a-model-id""#,
                    "the provider's default",
                    "The model to use; /model changes it for the session."
                ),
                \.model
            ),
            .string(
                SettingCatalog.row(
                    "provider",
                    .text,
                    #""a-connection""#,
                    "the first account that can answer",
                    "The connection to use."
                ),
                \.provider
            ),
            .choice(
                SettingCatalog.row(
                    "thinking",
                    SettingCatalog.words(ThinkingLevel.self),
                    #""default""#,
                    "default",
                    "How much the model thinks."
                ),
                \.thinking
            ),
            .field(
                SettingCatalog.row(
                    "maxTurns",
                    .structured,
                    "100",
                    "100 in the sandbox, no limit with --no-sandbox",
                    "The most model requests one prompt may make, or null for no limit."
                ),
                \.maxTurns
            ) { container, key, _ in
                try ConfigurationFile.decodeMaxTurns(container, key: key)
            } write: {
                $0 == Configuration.noTurnLimit ? "null" : String($0)
            },
            .field(
                SettingCatalog.row(
                    "compactAt",
                    .structured,
                    "0.75",
                    "0.75",
                    "When the conversation is summarised: a share of the window up to 1, or a number of tokens."
                ),
                \.compactAt
            ) { container, key, _ in
                try ConfigurationFile.decodeCompactAt(container, key: key)
            } write: {
                "\($0)"
            },
            .choice(
                SettingCatalog.row(
                    "keepAwake",
                    SettingCatalog.words(KeepAwakeMode.self),
                    #""working""#,
                    "working",
                    "When ask keeps the Mac from sleeping."
                ),
                \.keepAwake
            ),
            .flag(
                SettingCatalog.row("keepDisplayAwake", .boolean, "false", "false", "Whether the display stays on too."),
                \.keepDisplayAwake
            ),
            .choice(
                SettingCatalog.row(
                    "sessionEncryption",
                    SettingCatalog.words(SessionEncryptionMode.self),
                    #""on""#,
                    "asked at first start",
                    "Whether new sessions are encrypted: on, off, or asked when each begins."
                ),
                \.sessionEncryption
            ),
            .flag(
                SettingCatalog.row(
                    "sessionCompression",
                    .boolean,
                    "false",
                    "false",
                    "Whether session files are compressed."
                ),
                \.sessionCompression
            ),
            .flag(
                SettingCatalog.row(
                    "codemode",
                    .boolean,
                    "true",
                    "true",
                    "Whether the model may run one script over the tools in place of many calls."
                ),
                \.codemode
            ),
            .choice(
                SettingCatalog.row(
                    "taskScope",
                    SettingCatalog.words(TaskScope.self),
                    #""session""#,
                    "session",
                    "A task list for each session, or one for the workspace."
                ),
                \.taskScope
            ),
            .choice(
                SettingCatalog.row(
                    "sessionPassword",
                    SettingCatalog.words(SessionPasswordMode.self),
                    #""remember""#,
                    "asked at first start",
                    "Whether the key the password opens is kept in the keychain, or the password asked at every start."
                ),
                \.sessionPassword
            ),
            .choice(
                SettingCatalog.row(
                    "credentials",
                    SettingCatalog.words(CredentialStorage.self),
                    #""auto""#,
                    "auto",
                    user: true,
                    "Where keys and sign-in tokens are kept."
                ),
                \.credentials
            ),
            .field(
                SettingCatalog.row(
                    "modelScopes",
                    .structured,
                    #"[{"path": "~/work", "providers": ["work"]}]"#,
                    "none",
                    user: true,
                    "Which providers serve a repository, by its path, remote or git identity; the first rule that matches decides."
                ),
                \.modelScopes
            ) { container, key, _ in
                try container.decode([ModelScopeDecoded].self, forKey: key).map(\.scope)
            } write: {
                $0.count == 1 ? "1 rule" : "\($0.count) rules"
            },
            .list(
                SettingCatalog.row(
                    "presets",
                    .structured,
                    #"["swift"]"#,
                    "none",
                    "Sets of MCP servers ask knows: swift connects apple-docs and swift-search."
                ),
                \.presets
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
