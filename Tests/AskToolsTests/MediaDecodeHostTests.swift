import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// Security review 2026-11-25 (N-A2 / R-DES-2): verifies the Seatbelt policy and end-to-end JSON protocol used by
/// `ask decode-media` so untrusted image/PDF/video decoding runs without network, writes, or keychain access.
@Suite("Sandboxed media decoder helper (N-A2)")
struct MediaDecodeHostTests {
    @Test func `sandbox policy denies network and writes and restricts reads to the copy and binary folders`() {
        let policy = MediaDecodeHost.sandboxPolicy(
            for: "/private/tmp/ask-read-123/file.png",
            executable: "/usr/local/bin/ask"
        )
        #expect(policy.network == .none)
        #expect(policy.write == .roots([]))
        #expect(policy.read == .roots(["/private/tmp/ask-read-123", "/usr/local/bin"]))

        let profile = SeatbeltProfile(policy)
        #expect(profile.text.contains("(deny default)"))
        #expect(!profile.text.contains("(allow network*)"))
    }

    @Test func `decodes a valid PNG through the local host protocol and refuses malformed inputs`() async throws {
        // 1x1 transparent PNG.
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let png = try #require(Data(base64Encoded: pngBase64))
        let dir = FileManager.default.temporaryDirectory.appending(path: "ask-media-host-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appending(path: "dot.png")
        try png.write(to: file)

        let ok = await MediaDecodeHost.decodeLocally(
            MediaDecodeHost.Request(kind: .image, filePath: file.path, shownPath: "dot.png")
        )
        #expect(!ok.isError)
        #expect(ok.images.count == 1)
        #expect(ok.images[0].mediaType == "image/png")

        let bogus = dir.appending(path: "bad.png")
        try Data("not a png".utf8).write(to: bogus)
        let failed = await MediaDecodeHost.decodeLocally(
            MediaDecodeHost.Request(kind: .image, filePath: bogus.path, shownPath: "bad.png")
        )
        #expect(failed.isError)
        #expect(failed.images.isEmpty)
    }
}
