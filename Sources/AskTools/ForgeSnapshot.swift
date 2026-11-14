internal import AemiJSON
internal import AskAgentCore

/// What ask shows of the workspace's GitHub repository before anything is asked (roadmap 0186): its open pull requests and issues
/// for the `#` picker, and its branch's pull request for the status bar.
///
/// It is one value so that a child process can read it (ADR-0152): a process's first request loads the system's network stack,
/// about 6 MB of resident memory, which an ask nobody has spoken to yet would hold for a number in its status bar. `ask forge
/// DIRECTORY` prints one as JSON; ``read(by:workspace:token:path:deadline:)`` runs that and reads what it printed.
public struct ForgeSnapshot: Equatable, Sendable, Codable {
    /// A pull request or an issue, as the picker lists it.
    public struct Entry: Equatable, Sendable, Codable {
        public let number: Int
        /// `pull request` or `issue`.
        public let kind: String
        public let title: String
    }

    /// The open pull requests and issues, most recently updated first.
    public var open: [Entry]
    /// The open pull request of the workspace's branch.
    public var pullRequest: Int?

    public init(open: [Entry] = [], pullRequest: Int? = nil) {
        self.open = open
        self.pullRequest = pullRequest
    }

    /// The snapshot read here, in this process: what `ask forge` does.
    public static func read(
        workspace: String,
        token: String?,
        path: String?,
        fetch: ForgeReader.Fetch? = nil
    ) async -> ForgeSnapshot {
        let open = await ForgeReader.openItems(workspace: workspace, token: token, path: path, fetch: fetch)
        let branch = await ForgeReader.currentBranch(workspace: workspace, path: path)
        let pull = await ForgeReader.branchPullRequest(
            branch: branch ?? "",
            workspace: workspace,
            token: token,
            path: path,
            fetch: fetch
        )
        return ForgeSnapshot(
            open: open.map { Entry(number: $0.number, kind: $0.kind, title: $0.title) },
            pullRequest: pull
        )
    }

    /// The snapshot read by `executable forge WORKSPACE`, a child that ends with it: empty, and no child, for a workspace that is not
    /// on GitHub; nil when the child could not run, failed, outlived `deadline`, or printed something else.
    ///
    /// The token goes in the child's environment, never among its arguments, which any process on the machine can read.
    public static func read(
        by executable: String,
        workspace: String,
        token: String?,
        path: String?,
        deadline: Duration = .seconds(12)
    ) async -> ForgeSnapshot? {
        guard await ForgeReader.repository(of: workspace, path: path) != nil else { return ForgeSnapshot() }
        var environment = CommandCheck.environment(path: path)
        if let token, !token.isEmpty { environment["GITHUB_TOKEN"] = token }
        let outcome = await CommandCheck.run(
            executable,
            ["forge", workspace],
            environment: environment,
            deadline: deadline
        )
        guard case .ran(let ran) = outcome, ran.status == 0 else { return nil }
        return ForgeSnapshot(json: Array(ran.output.utf8))
    }

    /// The snapshot as JSON, one line.
    public func encoded() -> [UInt8] {
        (try? AemiJSON.JSONEncoder().encodeToBytes(self)) ?? Array("{\"open\":[]}".utf8)
    }

    /// The snapshot `json` holds, or nil when it is not one.
    public init?(json: [UInt8]) {
        guard let decoded = try? AemiJSON.JSONDecoder().decode(ForgeSnapshot.self, from: json) else { return nil }
        self = decoded
    }
}
