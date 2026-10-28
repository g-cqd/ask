public import AskAI

/// Loads the layers of ask's configuration from disk and reports what it found (ADR-0031).
///
/// Everything is read and validated before anything is returned, so a caller either gets a whole new
/// configuration or an error and keeps the one it had. That is what makes reloading safe: a half-edited file
/// cannot leave ask half-configured.
public struct ConfigurationLoader: Sendable {
    /// The user's file: `~/.config/ask/config.json`.
    public let userPath: String
    /// The project's file: `<project>/.ask/config.json`.
    public let projectPath: String
    /// Where trust is kept: `~/.config/ask/trusted.json`.
    public let trustPath: String
    public let environment: [String: String]

    /// What a successful load found.
    public struct Result: Sendable, Equatable {
        public var configuration: Configuration
        /// Files that applied, lowest layer first.
        public var applied: [String]
        /// Things the user should know that did not stop the load: an untrusted or changed project file, an
        /// environment variable that was ignored.
        public var notices: [String]
    }

    /// A loader for `project`, an absolute path, with ask's configuration in `configDirectory`.
    public init(project: String, configDirectory: String, environment: [String: String]) {
        userPath = configDirectory + "/config.json"
        trustPath = configDirectory + "/trusted.json"
        projectPath = project + "/.ask/config.json"
        self.environment = environment
    }

    /// Reads every layer and applies them, then the flags.
    /// - Parameters:
    ///   - model: the `--model` flag, if given.
    ///   - provider: the `--provider` flag, if given.
    ///   - maxTurns: the `--max-turns` flag, if given.
    ///   - compactAt: the `--compact-at` flag, if given.
    ///   - network: the `--network` flag, if given.
    ///   - write: the `--write` flag, if given.
    ///   - read: the `--read` flag, if given.
    ///   - thinking: the `--thinking` flag, if given; default explicitly resets a lower layer.
    /// - Returns: the new configuration and what it was made from.
    /// - Throws: ``ConfigurationError`` for any file that exists, applies, and is not valid.
    public func load(
        model: String? = nil, provider: String? = nil, maxTurns: Int? = nil, compactAt: CompactionThreshold? = nil,
        network: SandboxPolicy.Network? = nil, write: PathSetting? = nil, read: PathSetting? = nil,
        thinking: ThinkingLevel? = nil
    ) throws(ConfigurationError) -> Result {
        var configuration = Configuration.defaults
        var applied: [String] = []
        var notices: [String] = []
        if let user = try ConfigurationFile.load(userPath) {
            configuration = configuration.applying(user, from: .file(userPath))
            applied.append(userPath)
        }
        if let bytes = try ConfigurationFileReader.read(projectPath) {
            switch try ProjectTrust.load(trustPath).standing(of: projectPath, bytes: bytes) {
                case .trusted:
                    let project = try ConfigurationFile.parse(bytes, path: projectPath, isProject: true)
                    configuration = configuration.applying(project, from: .file(projectPath))
                    applied.append(projectPath)
                case .unknown:
                    notices.append("\(projectPath) is ignored: run `ask trust` here to use it.")
                case .changed:
                    notices.append(
                        "\(projectPath) changed since you trusted it, so it is ignored: run `ask trust` to use it.")
            }
        }
        configuration = configuration.applying(environment: environment, problems: &notices)
        configuration = configuration.applying(
            model: model, provider: provider, maxTurns: maxTurns, compactAt: compactAt, network: network,
            write: write, read: read, thinking: thinking)
        return Result(configuration: configuration, applied: applied, notices: notices)
    }
}
