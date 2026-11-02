import Foundation
import Synchronization
import Testing

@testable import AskAI

/// The Copilot connection sends the newest VS Code's version and the Copilot Chat built into it, as VS Code itself does, read from the
/// official build at most once an hour.
@Suite("Copilot requests carry the newest VS Code and Copilot Chat versions, checked hourly")
struct CopilotVersionsTests {
    private func transport(release: String = VSCodeBuildServer.release(), zip: [UInt8] = VSCodeBuildServer.zip())
        -> CopilotTestTransport
    {
        VSCodeBuildServer.transport(release: release, zip: zip)
    }

    private func source(_ transport: CopilotTestTransport) -> (CopilotVersions, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-copilot-versions-\(UUID().uuidString)")
        let cache = root.appending(path: "copilot-vscode-version.json")
        return (CopilotVersions(cache: cache, transport: transport), cache)
    }

    @Test func `with no cache the newest versions are read, kept, and not read again within the hour`() async {
        let transport = transport()
        let (versions, _) = source(transport)
        #expect(await versions.current(now: 10_000) == CopilotClientVersion(vscode: "1.150.2", chat: "0.80.1"))
        #expect(transport.requests.count == 5)
        #expect(await versions.current(now: 10_000 + 3_599) == CopilotClientVersion(vscode: "1.150.2", chat: "0.80.1"))
        #expect(transport.requests.count == 5)
        _ = await versions.current(now: 10_000 + 3_600)
        #expect(transport.requests.count == 10)
    }

    @Test func `a cache dated after now is read again`() async {
        let transport = transport()
        let (versions, _) = source(transport)
        _ = await versions.current(now: 10_000)
        _ = await versions.current(now: 9_000)
        #expect(transport.requests.count == 10)
    }

    @Test func `when the check fails the last versions read stay, and it is tried again after five minutes`() async {
        let working = transport()
        let (versions, cache) = source(working)
        _ = await versions.current(now: 10_000)
        let failing = CopilotTestTransport { _ in CopilotTestTransport.reply("", status: 503) }
        let offline = CopilotVersions(cache: cache, transport: failing)
        #expect(await offline.current(now: 20_000) == CopilotClientVersion(vscode: "1.150.2", chat: "0.80.1"))
        #expect(failing.requests.count == 1)
        _ = await offline.current(now: 20_000 + 299)
        #expect(failing.requests.count == 1)
        _ = await offline.current(now: 20_000 + 300)
        #expect(failing.requests.count == 2)
    }

    @Test func `with nothing read yet a failed check uses the versions ask was built with`() async {
        let (versions, _) = source(CopilotTestTransport { _ in CopilotTestTransport.reply("", status: 500) })
        #expect(await versions.current(now: 10_000) == .known)
    }

    @Test(arguments: [
        VSCodeBuildServer.release(version: "1.150.2\r\nx-evil: 1"),
        VSCodeBuildServer.release(commit: ""),
        VSCodeBuildServer.release(url: "https://evil.example/\(VSCodeBuildServer.commit)/VSCode-darwin-arm64.zip"),
        VSCodeBuildServer.release(
            url: "http://vscode.download.prss.microsoft.com/\(VSCodeBuildServer.commit)/VSCode-darwin-arm64.zip"
        ),
        VSCodeBuildServer.release(url: "https://vscode.download.prss.microsoft.com/other/VSCode-darwin-arm64.zip"),
        VSCodeBuildServer.release(version: "1.150.3")
    ])
    func `a release that is not the official build's, or does not match it, is not used`(release: String) async {
        let (versions, _) = source(transport(release: release))
        #expect(await versions.current(now: 10_000) == .known)
    }

    @Test(arguments: [
        VSCodeBuildServer.zip(commit: String(repeating: "ef56", count: 10)),
        VSCodeBuildServer.zip(name: "copilot"),
        VSCodeBuildServer.zip(chat: "0.80.1 (evil)"),
        VSCodeBuildServer.zip(vscode: "1.150.3")
    ])
    func `a build whose files do not match its release is not used`(zip: [UInt8]) async {
        let (versions, _) = source(transport(zip: zip))
        #expect(await versions.current(now: 10_000) == .known)
    }

    @Test func `a server that ignores the range is not read whole, nor one that answers a range with the whole`() async
    {
        let (versions, _) = source(VSCodeBuildServer.transport(ranges: false))
        #expect(await versions.current(now: 10_000) == .known)
        let (whole, _) = source(VSCodeBuildServer.transport(rangeStatus: 200))
        #expect(await whole.current(now: 10_000) == .known)
    }

    @Test func `a directory said to be over 4 MiB is not asked for`() async {
        var zip = VSCodeBuildServer.zip()
        let size = zip.count - 22 + 12
        zip[size ..< size + 4] = [0, 0, 0x50, 0][...]
        let transport = transport(zip: zip)
        let (versions, _) = source(transport)
        #expect(await versions.current(now: 10_000) == .known)
        #expect(transport.requests.count == 2)
    }

    @Test func `the headers name the versions as VS Code does`() {
        let version = CopilotClientVersion(vscode: "1.150.2", chat: "0.80.1")
        let credential = CopilotCredentials(
            githubToken: "g",
            accessToken: "a",
            expiresAt: 1,
            apiURL: CopilotProtocol.defaultAPI,
            machineID: "m",
            deviceID: "d"
        )
        let headers = CopilotProtocol.chatHeaders(
            credential,
            session: "s",
            interaction: "i",
            userInitiated: true,
            version: version
        )
        let value = { (name: String) in headers.filter { $0.name == name }.map(\.value) }
        #expect(value("user-agent") == ["GitHubCopilotChat/0.80.1"])
        #expect(value("editor-version") == ["vscode/1.150.2"])
        #expect(value("editor-plugin-version") == ["copilot-chat/0.80.1"])
        #expect(value("x-github-api-version") == ["2026-01-09"])
    }

    @Test(arguments: ["1.144.0", "0.72", "10.0.0.1"])
    func `plain versions are accepted`(text: String) { #expect(CopilotClientVersion.isPlain(text)) }

    @Test(arguments: ["", "1", "1..2", "1.2.3.4.5", "1.2a", "1.2 ", "1234567.1", "-1.2", "١.٢", "１.２"])
    func `anything else is not`(text: String) { #expect(!CopilotClientVersion.isPlain(text)) }
}
