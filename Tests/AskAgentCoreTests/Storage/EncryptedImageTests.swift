import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// An encrypted session's pictures (ADR-0138, roadmap 0182 phase 3c): sealed in the store, named by an HMAC rather than their hash, and
/// read back by the session; a reader without the key gets the line of text a missing picture leaves.
@Suite
struct EncryptedImageTests {
    private let directory: URL
    private let keyring: SessionKeyring
    private let picture = ImagePart(
        mediaType: "image/png",
        data: (0 ..< 200_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
    )

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-images-enc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
    }

    private var sessionPath: FilePath { FilePath(directory.appending(path: "s.jsonl").path) }
    private var stored: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "images").path)) ?? []
    }

    @Test
    func `an encrypted session's picture is sealed, named by an HMAC, and read back`() throws {
        do {
            var file = try SessionFile.create(
                at: sessionPath,
                format: .init(compressed: true, encrypted: true),
                keyring: keyring
            )
            try file.append(.toolResult(callID: "c", content: "look", isError: false, images: [picture]))
        }
        #expect(stored.count == 1)
        let name = try #require(stored.first)
        #expect(name != SessionImageStore.hash(of: picture.data), "the name does not say which picture it is")
        let onDisk = try [UInt8](Data(contentsOf: directory.appending(path: "images/" + name)))
        #expect(onDisk != picture.data && !onDisk.starts(with: Array(picture.data.prefix(64))))
        let reopened = try SessionFile.open(at: sessionPath, keyring: keyring)
        guard case .toolResult(_, _, _, let images, _)? = reopened.tree.entries.last?.payload else {
            Issue.record("no tool result")
            return
        }
        #expect(images == [picture])
    }

    @Test
    func `the store without the key reads nothing it sealed, and a plain session's pictures stay as they were`() throws
    {
        let sealed = SessionImageStore(besideSessionAt: sessionPath.string, key: keyring.imageKey)
        let plain = SessionImageStore(besideSessionAt: sessionPath.string)
        let name = try sealed.put(picture.data)
        #expect(sealed.get(name) == picture.data)
        #expect(plain.get(name) == nil)
        let plainName = try plain.put(picture.data)
        #expect(plainName == SessionImageStore.hash(of: picture.data) && plain.get(plainName) == picture.data)
        #expect(sealed.get(plainName) == nil)
    }
}
