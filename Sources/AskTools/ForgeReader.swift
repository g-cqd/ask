public import AskAgentCore
public import Foundation

/// The workspace's GitHub repository, read for `#123` (roadmap 0186): the repository from `git remote get-url origin`, then GitHub's
/// API, with `GITHUB_TOKEN` when the person set one (the owner, 2026-11-12; never `gh`'s). Public repositories need none. Each read has
/// three seconds; one that fails, or a workspace that is not on GitHub, gives nothing, and nothing waits on it.
public enum ForgeReader {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The pull requests and issues `text` names, in the order named.
    public static func items(
        for text: String,
        workspace: String,
        token: String?,
        path: String?,
        fetch: Fetch? = nil
    ) async -> [ForgeReferences.Item] {
        let numbers = ForgeReferences.numbers(in: text)
        guard !numbers.isEmpty, let repository = await repository(of: workspace, path: path) else { return [] }
        let fetch = fetch ?? live
        let read = await withTaskGroup(of: (Int, ForgeReferences.Item?).self) { group in
            for number in numbers {
                group.addTask {
                    let data = await get("\(base(repository))/issues/\(number)", token: token, fetch: fetch)
                    let item = data.flatMap { ForgeReferences.item(from: Array($0)) }
                    return (number, item?.number == number ? item : nil)
                }
            }
            var read: [Int: ForgeReferences.Item] = [:]
            for await (number, item) in group { read[number] = item }
            return read
        }
        return numbers.compactMap { read[$0] }
    }

    /// The open pull requests and issues of the workspace's repository, most recently updated first, at most 30.
    public static func openItems(
        workspace: String,
        token: String?,
        path: String?,
        fetch: Fetch? = nil
    ) async -> [ForgeReferences.Item] {
        guard let repository = await repository(of: workspace, path: path),
            let data = await get(
                "\(base(repository))/issues?state=open&sort=updated&per_page=30",
                token: token,
                fetch: fetch ?? live
            )
        else { return [] }
        return ForgeReferences.items(fromList: Array(data))
    }

    /// The number of the open pull request whose head is `branch` of the repository's owner, or nil.
    public static func branchPullRequest(
        branch: String,
        workspace: String,
        token: String?,
        path: String?,
        fetch: Fetch? = nil
    ) async -> Int? {
        guard !branch.isEmpty, branch.allSatisfy({ !$0.isWhitespace && !"&#?%".contains($0) }),
            let repository = await repository(of: workspace, path: path),
            let data = await get(
                "\(base(repository))/pulls?state=open&head=\(repository.owner):\(branch)&per_page=1",
                token: token,
                fetch: fetch ?? live
            )
        else { return nil }
        return ForgeReferences.items(fromList: Array(data)).first?.number
    }

    /// The workspace's current branch, or nil when HEAD is detached or it is not a repository.
    public static func currentBranch(workspace: String, path: String?) async -> String? {
        guard let git = CommandCheck.executable("git", path: path) else { return nil }
        let outcome = await CommandCheck.run(
            git,
            ["-C", workspace, "symbolic-ref", "--quiet", "--short", "HEAD"],
            environment: CommandCheck.environment(path: path),
            deadline: .seconds(2)
        )
        guard case .ran(let ran) = outcome, ran.status == 0 else { return nil }
        let branch = ran.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    private static let live: Fetch = { try await URLSession.shared.data(for: $0) }

    private static func base(_ repository: ForgeReferences.Repository) -> String {
        "https://api.github.com/repos/\(repository.owner)/\(repository.name)"
    }

    private static func repository(of workspace: String, path: String?) async -> ForgeReferences.Repository? {
        guard let git = CommandCheck.executable("git", path: path) else { return nil }
        let outcome = await CommandCheck.run(
            git,
            ["-C", workspace, "remote", "get-url", "origin"],
            environment: CommandCheck.environment(path: path),
            deadline: .seconds(2)
        )
        guard case .ran(let ran) = outcome, ran.status == 0 else { return nil }
        return ForgeReferences.repository(fromRemote: ran.output)
    }

    /// The body of a GET of GitHub's API that answered 200 within three seconds, or nil.
    private static func get(_ address: String, token: String?, fetch: Fetch) async -> Data? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ask", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await fetch(request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return data
    }
}
