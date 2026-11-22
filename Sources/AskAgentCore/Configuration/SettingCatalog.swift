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

    static let all: [Setting] = beforeOpeners + openers

    // @dl:disable near-clone -- the rows below are the catalog's data: a key, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape

    static let top: [Setting] = ConfigurationFile.settings.all.map(\.row)

    static let sandbox: [Setting] = SandboxSection.settings.all.map(\.row)

    static let approvals: [Setting] = ApprovalsSection.settings.all.map(\.row)

    static let skills: [Setting] = SkillsSection.settings.all.map(\.row)

    static let environment: [Setting] = EnvironmentSection.settings.all.map(\.row)
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
