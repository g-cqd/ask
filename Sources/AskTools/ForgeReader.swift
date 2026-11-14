internal import AskAI
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
        let found = await GitQuery.output(["symbolic-ref", "--quiet", "--short", "HEAD"], in: workspace, path: path)
        let branch = found?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return branch.isEmpty ? nil : branch
    }

    /// The most of an answer read: GitHub's list of 30 open items is well under it.
    static let maximumBytes = 4 * 1024 * 1024
    private static let transport = URLSessionTransport()

    /// A request through ask's transport: no cache or cookie kept on disk, no stored credential sent, no redirect followed (the
    /// system's shared session did all three: security audit 3), and no more than ``maximumBytes`` read.
    private static let live: Fetch = { request in
        guard let url = request.url else { throw URLError(.badURL) }
        let headers = (request.allHTTPHeaderFields ?? [:]).map { (name: $0.key, value: $0.value) }
        let reply = try await transport.send(
            HTTPRequest(url: url, method: "GET", headers: headers, body: [], allowsRedirects: false)
        )
        var bytes: [UInt8] = []
        for try await chunk in reply.body {
            bytes += chunk
            guard bytes.count <= maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badServerResponse)
        }
        return (Data(bytes), response)
    }

    private static func base(_ repository: ForgeReferences.Repository) -> String {
        "https://api.github.com/repos/\(repository.owner)/\(repository.name)"
    }

    private static func repository(of workspace: String, path: String?) async -> ForgeReferences.Repository? {
        await GitQuery.output(["remote", "get-url", "origin"], in: workspace, path: path)
            .flatMap(ForgeReferences.repository(fromRemote:))
    }

    /// The body of a GET of GitHub's API that answered 200 within three seconds, or nil.
    private static func get(_ address: String, token: String?, fetch: @escaping Fetch) async -> Data? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ask", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        // Three seconds for the whole answer: the transport's own patience is a model's, minutes long.
        let sent = request
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                guard let (data, response) = try? await fetch(sent), (response as? HTTPURLResponse)?.statusCode == 200
                else {
                    return nil
                }
                return data
            }
            group.addTask {
                try? await ContinuousClock().sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
