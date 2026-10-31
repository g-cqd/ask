internal import Foundation
internal import Testing

@testable import AskTools

/// `/reload` refuses a new build whose signature is not the running build's (owner, 2026-10-31, roadmap 0153 and 0110): a signed ask
/// moves only into a build that meets its own designated requirement, so something else placed at its path is never started with the
/// session and its grants. An ad-hoc build has no identity to compare, which the check says rather than refusing every unsigned
/// rebuild. Copies of /usr/bin/true, signed ad hoc, stand in for builds: signing ad hoc needs no keychain.
@Suite("A reload starts only a build signed as the running one is")
struct BuildSignatureTests {
    private func signedCopy(identifier: String?) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-signature-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "ask").path
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: path)
        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments =
            identifier.map { ["--force", "--sign", "-", "--identifier", $0, path] } ?? ["--remove-signature", path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)
        return path
    }

    @Test func `a build that meets the running build's requirement may be started`() throws {
        let build = try signedCopy(identifier: "ask")
        #expect(BuildSignature.check(build, against: #"identifier "ask""#) == .sameSigner)
    }

    @Test func `a build signed as something else is refused, and says why`() throws {
        let build = try signedCopy(identifier: "not-ask")
        guard case .refused(let reason) = BuildSignature.check(build, against: #"identifier "ask""#) else {
            Issue.record("a build under another identifier was accepted")
            return
        }
        #expect(reason.contains("not signed as the running build"), "\(reason)")
    }

    @Test func `an unsigned or missing build is refused`() throws {
        let unsigned = try signedCopy(identifier: nil)
        #expect(BuildSignature.check(unsigned, against: #"identifier "ask""#) != .sameSigner)
        #expect(BuildSignature.check("/nonexistent/ask", against: #"identifier "ask""#) != .sameSigner)
    }

    @Test func `with no running identity nothing is compared, and that is said`() throws {
        let build = try signedCopy(identifier: "anything")
        #expect(BuildSignature.check(build, against: nil) == .unsignedRunning)
    }

    /// The test runner is one of Apple's platform binaries, which carry no team identifier, as an ad-hoc build does not either.
    @Test func `a running process without a team identifier holds builds to nothing`() {
        #expect(BuildSignature.runningRequirement() == nil)
    }
}
