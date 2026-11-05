internal import AemiJSON
internal import Foundation

/// The newest official VS Code build and the Copilot Chat inside it, read from the build itself: VS Code's update service names the
/// build's archive and commit, and HTTP ranges read the archive's directory, its `product.json` and `extensions/copilot/package.json`
/// (about 800 KB of a 350 MB archive). Since VS Code 1.121 Copilot Chat ships in VS Code; the marketplace's copy stopped at 0.48.
struct VSCodeBuild: Sendable {
    let transport: any HTTPTransport

    static let update = URL.constant("https://update.code.visualstudio.com/api/update/darwin-arm64/stable/latest")
    static let downloads = "vscode.download.prss.microsoft.com"
    static let app = "Visual Studio Code.app/Contents/Resources/app/"
    static let product = app + "product.json"
    static let copilot = app + "extensions/copilot/package.json"

    /// The versions the newest build carries.
    func latest() async throws -> CopilotClientVersion {
        let release = try await CopilotHTTP(transport: transport)
            .json(request(Self.update, range: nil), as: Release.self)
        guard !release.version.isEmpty, let archive = URL(string: release.url), archive.scheme == "https",
            archive.host == Self.downloads, archive.path.contains("/\(release.version)/")
        else { throw SignInError.invalidResponse("VS Code release") }
        let files = try await read([Self.product, Self.copilot], from: archive)
        let product = try AemiJSON.JSONDecoder().decode(Product.self, from: files[Self.product] ?? [])
        let chat = try AemiJSON.JSONDecoder().decode(Package.self, from: files[Self.copilot] ?? [])
        let version = CopilotClientVersion(vscode: product.version, chat: chat.version)
        guard product.commit == release.version, product.version == release.productVersion, chat.name == "copilot-chat",
            version.isPlain
        else { throw SignInError.invalidResponse("VS Code build") }
        return version
    }

    /// The files `names` in the archive at `archive`, each as its bytes.
    private func read(_ names: [String], from archive: URL) async throws -> [String: [UInt8]] {
        let tail = try await bytes(archive, "bytes=-65536", limit: 65_536)
        guard let (offset, size) = ZipDirectory.locate(tail: tail), size <= 4 << 20,
            let entries = ZipDirectory.entries(
                try await bytes(archive, "bytes=\(offset)-\(offset + size - 1)", limit: size),
                named: Set(names)
            )
        else { throw SignInError.invalidResponse("VS Code archive") }
        var files: [String: [UInt8]] = [:]
        for name in names {
            guard let entry = entries[name], entry.compressedSize <= Inflate.limit else {
                throw SignInError.invalidResponse("VS Code archive")
            }
            let span = ZipDirectory.span(of: entry)
            let local = try await bytes(archive, "bytes=\(entry.offset)-\(entry.offset + span - 1)", limit: span)
            guard let payload = ZipDirectory.payload(local, of: entry) else {
                throw SignInError.invalidResponse("VS Code archive")
            }
            files[name] = payload
        }
        return files
    }

    /// The bytes of `range` of `url`, which must come back as a partial response.
    private func bytes(_ url: URL, _ range: String, limit: Int) async throws -> [UInt8] {
        let response = try await transport.collecting(request(url, range: range), limit: limit)
        guard response.status == 206 else { throw SignInError.rejected(status: response.status) }
        return response.body
    }

    private func request(_ url: URL, range: String?) -> HTTPRequest {
        var headers = [("accept", range == nil ? "application/json" : "application/octet-stream")]
        if let range { headers.append(("range", range)) }
        return HTTPRequest(url: url, method: "GET", headers: headers, body: [], allowsRedirects: false)
    }

    private struct Release: Decodable {
        let url: String
        let productVersion: String
        let version: String
    }

    private struct Product: Decodable {
        let version: String
        let commit: String
    }

    private struct Package: Decodable {
        let name: String
        let version: String
    }
}
