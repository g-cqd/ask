public import Foundation

/// The VS Code and Copilot Chat versions the Copilot connection names, read from the newest official build (``VSCodeBuild``) at most once
/// an hour, kept in a file beside the credentials; a
/// failed check keeps the last versions read, or ``CopilotClientVersion/known``, and is tried again after five minutes.
public struct CopilotVersions: Sendable {
    let cache: URL
    let transport: any HTTPTransport

    public init(cache: URL, transport: any HTTPTransport) {
        self.cache = cache
        self.transport = transport
    }

    /// The versions beside `file`'s credentials.
    public init(beside file: CredentialFile, transport: any HTTPTransport) {
        self.init(
            cache: file.url.deletingLastPathComponent().appending(path: "copilot-vscode-version.json"),
            transport: transport
        )
    }

    /// The versions to send at `now`: the kept ones while they hold, else newly read ones.
    public func current(now: Double) async -> CopilotClientVersion {
        let transport = transport
        return await KeptVersion(url: cache, isUsable: { $0.isPlain })
            .current(now: now, fallback: .known) { try? await VSCodeBuild(transport: transport).latest() }
    }
}
