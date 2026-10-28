/// Which of ask's own environment variables a command the model runs may see (ADR-0106).
///
/// A command inherits ask's environment, which holds whatever the person exported, and what a command prints comes back to the model and
/// goes to the provider. So ask withholds the variables it reads credentials from itself, and what the person configures, and nothing else:
/// a person's own variables are theirs to withhold, because ask cannot know which of them are secret.
public struct CommandEnvironment: Sendable, Equatable {
    /// Exact names a command is not given.
    public var withheld: Set<String>
    /// Prefixes: a command is not given a name that starts with one.
    public var withheldPrefixes: [String]
    /// Exact names a command is given even though ask would withhold them.
    public var passed: Set<String>
    /// The shell the person chose for commands (`zsh`, a path, ...), nil when ask chooses (roadmap 0091).
    public var shell: String?

    /// Nothing withheld: every variable is inherited. The library's default, so a caller that wants protection says so.
    public static let inherit = CommandEnvironment()

    /// A policy with these names.
    public init(
        withheld: Set<String> = [], withheldPrefixes: [String] = [], passed: Set<String> = [], shell: String? = nil
    ) {
        self.shell = shell
        self.withheld = withheld
        self.withheldPrefixes = withheldPrefixes
        self.passed = passed
    }

    /// The policy for a run: the variables ask itself reads credentials from, then what the person configured.
    ///
    /// A configured `pass` lets a credential through, because the person asked. A name the configuration both passes and withholds is
    /// withheld, so that a project's file, which may only withhold, can take back what the user's file passed.
    /// - Parameters:
    ///   - credentials: exact names ask reads credentials from.
    ///   - credentialPrefixes: prefixes of such names.
    ///   - configured: the `environment` section, layered.
    public init(credentials: Set<String>, credentialPrefixes: [String], configured: EnvironmentSection) {
        let exact = configured.withhold.filter { !$0.hasSuffix("*") }
        let prefixes = configured.withhold.filter { $0.hasSuffix("*") }.map { String($0.dropLast()) }
        let taken = { (name: String) in exact.contains(name) || prefixes.contains { name.hasPrefix($0) } }
        self.init(
            withheld: credentials.union(exact), withheldPrefixes: credentialPrefixes + prefixes,
            passed: Set(configured.pass.filter { !taken($0) }), shell: configured.shell)
    }

    /// Whether a command is denied the variable called `name`. Names are matched as written: the environment is case-sensitive.
    public func withholds(_ name: String) -> Bool {
        !passed.contains(name) && (withheld.contains(name) || withheldPrefixes.contains { name.hasPrefix($0) })
    }

    /// `environment` without what is withheld; every value that stays is exactly as it was.
    public func filtered(_ environment: [String: String]) -> [String: String] {
        environment.filter { !withholds($0.key) }
    }
}
