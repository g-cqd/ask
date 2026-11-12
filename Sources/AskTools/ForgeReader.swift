public import AskAgentCore
public import Foundation

/// `#123` read from the workspace's GitHub repository (roadmap 0186): the repository from `git remote get-url origin`, each number from
/// GitHub's issues API (which answers for pull requests too), with `GITHUB_TOKEN` when the person set one (the owner, 2026-11-12; never
/// `gh`'s). Public repositories need none. Each read has three seconds; one that fails, or a workspace that is not on GitHub, attaches
/// nothing, and the message goes as typed.
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
        let fetch = fetch ?? { try await URLSession.shared.data(for: $0) }
        let read = await withTaskGroup(of: (Int, ForgeReferences.Item?).self) { group in
            for number in numbers {
                group.addTask { (number, await item(number, in: repository, token: token, fetch: fetch)) }
            }
            var read: [Int: ForgeReferences.Item] = [:]
            for await (number, item) in group { read[number] = item }
            return read
        }
        return numbers.compactMap { read[$0] }
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

    private static func item(
        _ number: Int,
        in repository: ForgeReferences.Repository,
        token: String?,
        fetch: Fetch
    ) async -> ForgeReferences.Item? {
        guard
            let url = URL(
                string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/issues/\(number)"
            )
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ask", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await fetch(request), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return ForgeReferences.item(from: Array(data)).flatMap { $0.number == number ? $0 : nil }
    }
}
