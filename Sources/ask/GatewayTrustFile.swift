internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskGateway
internal import AskSession
internal import Foundation

/// Where this computer keeps the controller keys it trusts: `<config>/gateway/trusted.json`, owner-only, replaced whole (ADR-0089).
enum GatewayTrustFile {
    static var path: String {
        let configuration = (ConfigurationSource.here.loader.trustPath as NSString).deletingLastPathComponent
        return configuration + "/gateway/trusted.json"
    }

    /// The trusted controllers; none when the file is missing. A file that does not read stops the command, so a typo is never
    /// taken for an empty list.
    static func load() -> GatewayTrust {
        guard let data = FileManager.default.contents(atPath: path) else { return GatewayTrust() }
        guard let trust = try? AemiJSON.JSONDecoder().decode(GatewayTrust.self, from: Array(data)) else {
            fail("ask: \(path) cannot be read as the gateway's trusted controllers.", code: 65)
        }
        return trust
    }

    static func save(_ trust: GatewayTrust) {
        let folder = (path as NSString).deletingLastPathComponent
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        do {
            try FileManager.default.createDirectory(
                atPath: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try AtomicFile.replace(URL(fileURLWithPath: path), with: encoder.encodeToBytes(trust))
        } catch {
            fail("ask: cannot write \(path): \(error)", code: 73)
        }
    }
}
