internal import AskAI
internal import Foundation

/// The verified secret of the `agy` this machine has.
func installedClientSecret(transport: URLSessionTransport) async throws -> String {
    let path = AgyBinary.locate(environment: LaunchEnvironment.values, home: NSHomeDirectory()) {
        candidate in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    guard let path else { throw AgySecretError.binaryNotFound }
    let candidates = try AgyClientSecret.candidates(inFileAt: URL(filePath: path))
    guard !candidates.isEmpty else { throw AgySecretError.noCandidates }
    guard let secret = try await AgyClientSecret.verified(candidates, transport: transport) else {
        throw AgySecretError.notVerified
    }
    return secret
}
