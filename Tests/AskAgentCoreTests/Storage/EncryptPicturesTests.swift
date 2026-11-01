import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// `/encrypt on` and the pictures a session stored before it (roadmap 0182): sealed again under the image key, and the unencrypted copy
/// removed unless another session of the project still names it.
@Suite
struct EncryptPicturesTests {
    private let directory: URL
    private let keyring: SessionKeyring
    private let shared = ImagePart(
        mediaType: "image/png",
        data: (0 ..< 50_000).map { UInt8(truncatingIfNeeded: $0 &* 3) }
    )
    private let own = ImagePart(mediaType: "image/png", data: (0 ..< 50_000).map { UInt8(truncatingIfNeeded: $0 &* 5) })

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-encrypt-pictures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }
    private func exists(_ picture: ImagePart) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appending(path: "images/" + SessionImageStore.hash(of: picture.data)).path
        )
    }

    @Test(arguments: [SessionFormat.plain, SessionFormat(compressed: true, encrypted: false)])
    func `encrypting removes the clear copy of a picture only this session names`(other: SessionFormat) throws {
        do {
            var neighbour = try SessionFile.create(at: path("neighbour.jsonl"), format: other)
            try neighbour.append(.toolResult(callID: "n", content: "shared", isError: false, images: [shared]))
        }
        var file = try SessionFile.create(at: path("s.jsonl"))
        try file.append(.toolResult(callID: "c", content: "both", isError: false, images: [shared, own]))
        #expect(exists(shared) && exists(own))
        try file.change(to: SessionFormat(compressed: false, encrypted: true), keyring: keyring)
        #expect(!exists(own), "only this session named it")
        #expect(exists(shared), "the neighbour still names it")
        _ = consume file
        let reopened = try SessionFile.open(at: path("s.jsonl"), keyring: keyring)
        guard case .toolResult(_, _, _, let images, _)? = reopened.tree.entries.last?.payload else {
            Issue.record("no tool result")
            return
        }
        #expect(images == [shared, own])
    }

    @Test
    func `a neighbour that cannot be read keeps every clear copy`() throws {
        let unreadable = directory.appending(path: "unreadable.jsonl")
        try Data("{}".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        var file = try SessionFile.create(at: path("s.jsonl"))
        try file.append(.toolResult(callID: "c", content: "own", isError: false, images: [own]))
        try file.change(to: SessionFormat(compressed: false, encrypted: true), keyring: keyring)
        #expect(exists(own), "the unreadable file might name it")
    }
}
