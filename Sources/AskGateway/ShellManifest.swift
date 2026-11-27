internal import AemiJSON
internal import AskCore
package import CryptoKit
internal import Darwin
internal import Foundation

/// The signed manifest of the gateway's static web shell (ADR-0170): every served asset's SHA-256, signed with the owner's Ed25519
/// release key over a domain-separated prefix (`ask-gateway-shell/1\n` + `manifest.json` bytes) so the browser's service worker can
/// pin the key and refuse any unverified file or update.
package struct ShellManifest: Codable, Sendable, Equatable {
    package enum Failure: Error, Equatable, CustomStringConvertible {
        case directoryUnreadable
        case emptyShell
        case invalidSignature
        case tamperedFile(String)
        case missingFile(String)

        package var description: String {
            switch self {
                case .directoryUnreadable: "the shell directory cannot be read"
                case .emptyShell: "the shell directory contains no files to sign"
                case .invalidSignature: "manifest.sig is not a valid signature for manifest.json"
                case .tamperedFile(let path): "\(path) does not match its signed SHA-256"
                case .missingFile(let path): "\(path) listed in manifest.json is missing"
            }
        }
    }

    package static let domainPrefix = Array("ask-gateway-shell/1\n".utf8)
    package static let excluded: Set<String> = ["/sw.js", "/manifest.json", "/manifest.sig"]

    package let version: Int
    package let publicKey: String
    package let files: [String: String]

    /// Eight groups of four hex digits of SHA-256 of the Ed25519 public key, matching ``GatewayKeys/fingerprint(_:)``.
    package static func fingerprint(of key: Curve25519.Signing.PublicKey) -> String {
        GatewayKeys.fingerprint(rawRepresentation: key.rawRepresentation)
    }

    /// Hashes every regular file under `directory` (except `sw.js`, `manifest.json` and `manifest.sig`), writes `manifest.json` and
    /// `manifest.sig` atomically, and returns the manifest.
    package static func signDirectory(
        _ directory: String,
        with key: Curve25519.Signing.PrivateKey
    ) throws(Failure) -> ShellManifest {
        guard let resolvedPointer = realpath(directory, nil) else { throw .directoryUnreadable }
        defer { free(resolvedPointer) }
        let root = String(cString: resolvedPointer)
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { throw .directoryUnreadable }
        var hashes: [String: String] = [:]
        while let item = enumerator.nextObject() as? String {
            if item.hasPrefix(".") || item.contains("/.") { continue }
            let full = root + "/" + item
            var info = stat()
            guard lstat(full, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            let webPath = "/" + item
            if excluded.contains(webPath) { continue }
            guard let data = FileManager.default.contents(atPath: full) else { throw .directoryUnreadable }
            hashes[webPath] = sha256Hex(data)
        }
        guard !hashes.isEmpty else { throw .emptyShell }
        let manifest = ShellManifest(
            version: 1,
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            files: hashes
        )
        var encoder = AemiJSON.JSONEncoder()
        encoder.options.keyOrder = .sorted
        guard let jsonBytes = try? encoder.encodeToBytes(manifest),
            let signature = try? key.signature(for: Data(domainPrefix + jsonBytes))
        else { throw .directoryUnreadable }
        do {
            try Data(jsonBytes).write(to: URL(fileURLWithPath: root + "/manifest.json"), options: .atomic)
            try Data(signature).write(to: URL(fileURLWithPath: root + "/manifest.sig"), options: .atomic)
        } catch {
            throw .directoryUnreadable
        }
        return manifest
    }

    /// Verifies `manifest.json`, `manifest.sig` and every listed file in `directory` against `pinnedKey` (or the manifest's own key on
    /// first use when `pinnedKey` is nil).
    package static func verifyDirectory(
        _ directory: String,
        pinnedKey: Curve25519.Signing.PublicKey? = nil
    ) throws(Failure) -> ShellManifest {
        guard let jsonData = FileManager.default.contents(atPath: directory + "/manifest.json"),
            let sigData = FileManager.default.contents(atPath: directory + "/manifest.sig"),
            let manifest = try? AemiJSON.JSONDecoder().decode(ShellManifest.self, from: Array(jsonData)),
            manifest.version == 1,
            let keyBytes = Base64URL.decode(manifest.publicKey),
            let manifestKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        else { throw .invalidSignature }
        let expectedKey = pinnedKey ?? manifestKey
        guard expectedKey.rawRepresentation == manifestKey.rawRepresentation,
            expectedKey.isValidSignature(sigData, for: Data(domainPrefix + Array(jsonData)))
        else { throw .invalidSignature }
        for (webPath, expectedHash) in manifest.files {
            guard let data = FileManager.default.contents(atPath: directory + webPath) else {
                throw .missingFile(webPath)
            }
            guard sha256Hex(data) == expectedHash else { throw .tamperedFile(webPath) }
        }
        return manifest
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
