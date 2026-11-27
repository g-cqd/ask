internal import AemiJSON
internal import AskAI
internal import AskAgentCore
package import AskGateway
internal import Foundation

/// Where a computer keeps the gateway keys it trusts (`<config>/gateway/trusted.json` for controllers on a node, and
/// `<config>/gateway/nodes.json` for enrolled nodes on the gateway): owner-only, replaced whole (ADR-0089, ADR-0170).
package enum GatewayTrustFile {
    package enum Role: Sendable {
        case controllers
        case nodes

        var fileName: String {
            switch self {
                case .controllers: "trusted.json"
                case .nodes: "nodes.json"
            }
        }
    }

    package static func path(for role: Role = .controllers) -> String {
        let configuration = (ConfigurationSource.here.loader.trustPath as NSString).deletingLastPathComponent
        return configuration + "/gateway/" + role.fileName
    }

    package static var path: String { path(for: .controllers) }

    /// The trusted entries; none when the file is missing. A file that does not read stops the command, so a typo is never taken for
    /// an empty list.
    package static func load(_ role: Role = .controllers) -> GatewayTrust {
        let file = path(for: role)
        guard let data = FileManager.default.contents(atPath: file) else { return GatewayTrust() }
        guard let trust = try? AemiJSON.JSONDecoder().decode(GatewayTrust.self, from: Array(data)) else {
            fail("ask: \(file) cannot be read.", code: 65)
        }
        return trust
    }

    /// The trusted entries as the file says now; none when it is missing or does not read. Read again on each channel or connection.
    package static func current(_ role: Role = .controllers) -> GatewayTrust {
        guard let data = FileManager.default.contents(atPath: path(for: role)),
            let trust = try? AemiJSON.JSONDecoder().decode(GatewayTrust.self, from: Array(data))
        else { return GatewayTrust() }
        return trust
    }

    package static func save(_ trust: GatewayTrust, _ role: Role = .controllers) {
        let file = path(for: role)
        let folder = (file as NSString).deletingLastPathComponent
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        do {
            try FileManager.default.createDirectory(
                atPath: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try AtomicFile.replace(URL(fileURLWithPath: file), with: encoder.encodeToBytes(trust))
        } catch {
            fail("ask: cannot write \(file): \(error)", code: 73)
        }
    }
}
