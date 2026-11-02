import Foundation

@testable import AskAI

/// VS Code's update service and download server, as tests need them: the release names an archive made by ``TestZip``, which is served in
/// ranges, and everything else is the `other` handler's.
enum VSCodeBuildServer {
    static let commit = String(repeating: "ab12", count: 10)
    static let archive =
        "https://vscode.download.prss.microsoft.com/dbazure/download/stable/\(commit)/VSCode-darwin-arm64.zip"

    static func release(url: String = archive, version: String = "1.150.2", commit: String = commit) -> String {
        #"{"url":"\#(url)","name":"\#(version)","version":"\#(commit)","productVersion":"\#(version)"}"#
    }

    static func zip(
        vscode: String = "1.150.2",
        commit: String = commit,
        name: String = "copilot-chat",
        chat: String = "0.80.1"
    ) -> [UInt8] {
        TestZip.make([
            ("Visual Studio Code.app/Contents/Info.plist", String(repeating: "plist ", count: 50)),
            (VSCodeBuild.product, #"{"nameShort":"Code","version":"\#(vscode)","commit":"\#(commit)"}"#),
            (VSCodeBuild.copilot, #"{"name":"\#(name)","publisher":"GitHub","version":"\#(chat)"}"#)
        ])
    }

    static func transport(
        release: String = release(),
        zip: [UInt8] = zip(),
        ranges: Bool = true,
        rangeStatus: Int = 206,
        other: @escaping @Sendable (HTTPRequest) -> HTTPStreamingResponse = { _ in
            CopilotTestTransport.reply("{}", status: 404)
        }
    ) -> CopilotTestTransport {
        CopilotTestTransport { request in
            // The archive is served from any host, so that only ask's own check refuses one that is not the official server's.
            if request.url.host == "update.code.visualstudio.com" { return CopilotTestTransport.reply(release) }
            guard request.url.path.hasSuffix(".zip") else { return other(request) }
            guard ranges, let range = request.headers.first(where: { $0.name == "range" })?.value else {
                return bytes(zip, status: 200)
            }
            return bytes(slice(zip, range), status: rangeStatus)
        }
    }

    /// `bytes=a-b` or `bytes=-n` of `data`, cut at its end as a server does.
    static func slice(_ data: [UInt8], _ range: String) -> [UInt8] {
        let spec = range.dropFirst("bytes=".count)
        if spec.hasPrefix("-"), let count = Int(spec.dropFirst()) { return Array(data.suffix(count)) }
        let parts = spec.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] < data.count else { return [] }
        return Array(data[parts[0] ... min(parts[1], data.count - 1)])
    }

    static func bytes(_ data: [UInt8], status: Int) -> HTTPStreamingResponse {
        HTTPStreamingResponse(
            status: status,
            headers: [:],
            body: AsyncThrowingStream { stream in
                stream.yield(data)
                stream.finish()
            }
        )
    }
}
