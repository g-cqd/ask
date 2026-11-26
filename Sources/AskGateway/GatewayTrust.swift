package import CryptoKit
package import Foundation

/// The controller keys a node trusts (ADR-0170): only a controller holding one of them can open a channel to it. Kept by the node in
/// its configuration folder; adding and removing are the person's alone, at the node.
package struct GatewayTrust: Codable, Sendable, Equatable {
    /// One trusted controller.
    package struct Controller: Codable, Sendable, Equatable {
        /// Its public key, base64.
        package let key: String
        /// What the person called it, such as the browser it was made in.
        package let label: String
        /// When it was trusted, ISO 8601.
        package let added: String
    }

    package private(set) var controllers: [Controller] = []

    package init() {}

    /// Trusts `key` as `label`; false when it already was.
    package mutating func trust(_ key: Curve25519.KeyAgreement.PublicKey, label: String, at date: Date = Date()) -> Bool
    {
        let encoded = key.rawRepresentation.base64EncodedString()
        guard !controllers.contains(where: { $0.key == encoded }) else { return false }
        controllers.append(Controller(key: encoded, label: label, added: ISO8601DateFormatter().string(from: date)))
        return true
    }

    /// Stops trusting the controllers `selector` names: a whole key, or the start of a fingerprint (8 hex digits or more, spaces
    /// ignored); an ambiguous start removes nothing.
    /// - Returns: the controllers removed.
    package mutating func untrust(_ selector: String) -> [Controller] {
        let matches = controllers.filter { Self.matches($0, selector) }
        let shortStart = GatewayKeys.publicKey(selector) == nil
        guard !matches.isEmpty, !(shortStart && matches.count > 1) else { return [] }
        controllers.removeAll { controller in matches.contains(controller) }
        return matches
    }

    /// Whether `key` is trusted.
    package func trusts(_ key: Curve25519.KeyAgreement.PublicKey) -> Bool {
        let encoded = key.rawRepresentation.base64EncodedString()
        return controllers.contains { $0.key == encoded }
    }

    /// The trusted keys, for sealing a list to each.
    package var keys: [Curve25519.KeyAgreement.PublicKey] { controllers.compactMap { GatewayKeys.publicKey($0.key) } }

    private static func matches(_ controller: Controller, _ selector: String) -> Bool {
        if let key = GatewayKeys.publicKey(selector) {
            return key.rawRepresentation.base64EncodedString() == controller.key
        }
        let start = selector.lowercased().filter { !$0.isWhitespace }
        guard start.count >= 8, start.allSatisfy(\.isHexDigit), let key = GatewayKeys.publicKey(controller.key) else {
            return false
        }
        return GatewayKeys.fingerprint(key).filter { !$0.isWhitespace }.hasPrefix(start)
    }
}
