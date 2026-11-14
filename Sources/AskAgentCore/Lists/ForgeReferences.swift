internal import AemiJSON

/// `#123` in a message (roadmap 0186): a pull request's or an issue's state, title and body attached after what was typed, as a task's
/// is (``ListReferences``), each once, in the order named. Only a number that starts a word in the typed line counts, at most
/// ``limit``. What is read from GitHub is done by the caller; one that cannot be read stays text, and the message goes as typed.
public enum ForgeReferences {
    public static let marker = "\n\n--- github #"
    /// The most references read for one message.
    public static let limit = 5
    /// The most characters of a body attached.
    public static let bodyLimit = 4_000

    /// A GitHub repository, as the workspace's `origin` names it.
    public struct Repository: Equatable, Sendable {
        public let owner: String
        public let name: String
    }

    /// A pull request or an issue, as attached.
    public struct Item: Equatable, Sendable {
        public let number: Int
        public let title: String
        /// `open`, `closed`, or `merged` for a merged pull request.
        public let state: String
        /// `pull request` or `issue`.
        public let kind: String
        public let author: String
        public let url: String
        public let body: String
    }

    /// The numbers of the `#123` that start a word in the typed line, in order, each once, at most ``limit``.
    public static func numbers(in text: String) -> [Int] {
        var found: [Int] = []
        // A word of digits alone: `#4x` and `#t4` are not numbers; `Int` reads ASCII digits only.
        for word in ListReferences.hashWords(in: SkillInvocation.shown(text)) {
            guard let number = Int(word), !found.contains(number) else { continue }
            found.append(number)
            if found.count == limit { break }
        }
        return found
    }

    /// The repository of a GitHub remote URL (`https://github.com/o/r.git`, `git@github.com:o/r.git`, `ssh://git@github.com/o/r`).
    public static func repository(fromRemote url: String) -> Repository? {
        let trimmed = String(url.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
        let prefixes = ["https://github.com/", "http://github.com/", "git@github.com:", "ssh://git@github.com/"]
        guard let prefix = prefixes.first(where: trimmed.hasPrefix) else { return nil }
        var path = trimmed.dropFirst(prefix.count)
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy(isName) else { return nil }
        return Repository(owner: String(parts[0]), name: String(parts[1]))
    }

    /// A pull request or issue from GitHub's `/repos/{owner}/{repo}/issues/{number}` answer, or nil for anything else.
    public static func item(from json: [UInt8]) -> Item? {
        (try? AemiJSON.JSONDecoder().decode(Answer.self, from: json)).flatMap(item)
    }

    /// The items of a list answer (`/issues?state=open`, `/pulls`), in its order; an entry that is not one is left out.
    public static func items(fromList json: [UInt8]) -> [Item] {
        ((try? AemiJSON.JSONDecoder().decode([Answer].self, from: json)) ?? []).compactMap(item)
    }

    private static func item(_ decoded: Answer) -> Item? {
        guard let number = decoded.number, let title = decoded.title, let state = decoded.state else { return nil }
        let pull = decoded.pull_request
        return Item(
            number: number,
            title: title,
            state: pull?.merged_at != nil ? "merged" : state,
            kind: pull != nil ? "pull request" : "issue",
            author: decoded.user?.login ?? "",
            url: decoded.html_url ?? "",
            body: decoded.body ?? ""
        )
    }

    /// `text` with `items` attached after it.
    public static func attach(_ text: String, items: [Item]) -> String {
        text + items.map(section).joined()
    }

    private static func section(_ item: Item) -> String {
        let body =
            item.body.count > bodyLimit
            ? String(item.body.prefix(bodyLimit)) + "\n[cut at \(bodyLimit) characters]" : item.body
        // Everything GitHub gave is others' text (ADR-0150): said so, each field on one line, and neither the address, which has
        // a line of its own, nor the body able to close the section.
        let line = { (text: String) in text.split(whereSeparator: \.isNewline).joined(separator: " ") }
        let by = item.author.isEmpty ? "" : " by \(line(item.author))"
        let address = UntrustedText.insideAttachment(line(item.url))
        return "\(marker)\(item.number) ---\n\(UntrustedText.notice(from: "GitHub, written by others"))\n"
            + "\(item.kind) #\(item.number) (\(line(item.state)))\(by): \(line(item.title))\n\(address)\n\n"
            + UntrustedText.insideAttachment(body) + "\n--- end of #\(item.number) ---"
    }

    private static func isName(_ part: Substring) -> Bool {
        !part.isEmpty && part != "." && part != ".."
            && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    // swift-format-ignore: AlwaysUseLowerCamelCase
    private struct Answer: Decodable {
        let number: Int?
        let title: String?
        let state: String?
        let html_url: String?
        let body: String?
        let user: User?
        let pull_request: Pull?

        struct User: Decodable { let login: String? }
        struct Pull: Decodable { let merged_at: String? }
    }
}
