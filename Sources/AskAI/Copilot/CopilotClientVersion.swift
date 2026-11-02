/// The VS Code and Copilot Chat versions a Copilot request names, as VS Code sends them (`envService.ts`, `baseFetchFetcher.ts`).
public struct CopilotClientVersion: Sendable, Equatable, Codable {
    /// VS Code's version, as `editor-version: vscode/<it>`.
    public let vscode: String
    /// Copilot Chat's, as `editor-plugin-version: copilot-chat/<it>` and `user-agent: GitHubCopilotChat/<it>`.
    public let chat: String

    public init(vscode: String, chat: String) {
        self.vscode = vscode
        self.chat = chat
    }

    /// The newest when ask was built (VS Code 1.144.0, whose built-in Copilot Chat is 0.72.0), used until a check succeeds.
    public static let known = CopilotClientVersion(vscode: "1.144.0", chat: "0.72.0")

    var userAgent: String { "GitHubCopilotChat/\(chat)" }

    /// Whether both versions are plain, so neither can carry anything into a header.
    var isPlain: Bool { Self.isPlain(vscode) && Self.isPlain(chat) }

    /// Two to four dot-separated numbers of at most six digits each.
    static func isPlain(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return (2 ... 4).contains(parts.count)
            && parts.allSatisfy { part in
                (1 ... 6).contains(part.count) && part.allSatisfy { $0.isASCII && $0.isNumber }
            }
    }
}
