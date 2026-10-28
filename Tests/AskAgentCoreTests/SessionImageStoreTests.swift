import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// Pictures a tool returned are kept beside the session by content hash, not inline (roadmap 0084).
@Suite("A session keeps tool-result pictures in files named for their hash, and degrades when one is gone")
struct SessionImageStoreTests {
    private let directory: URL
    private let big = ImagePart(
        mediaType: "image/png", data: (0 ..< 3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var sessionPath: FilePath { FilePath(directory.appending(path: "s.jsonl").path) }
    private var imagesPath: String { directory.appending(path: "images").path }
    private var stored: [String] { (try? FileManager.default.contentsOfDirectory(atPath: imagesPath)) ?? [] }

    private func result(_ images: [ImagePart]) -> SessionPayload {
        .toolResult(callID: "c", content: "read it", isError: false, images: images)
    }

    private func images(of file: borrowing SessionFile) -> [ImagePart] {
        guard case .toolResult(_, _, _, let images)? = file.tree.entries.last?.payload else { return [] }
        return images
    }

    @Test func `a picture is stored once under its hash and a resumed session gets the same bytes`() throws {
        do {
            var file = try SessionFile.create(at: sessionPath)
            try file.append(.user("look"))
            try file.append(result([big, big]))
            try file.append(result([big]))
        }
        let name = SessionImageStore.hash(of: big.data)
        #expect(stored == [name], "three reads, one file")
        let log = try Data(contentsOf: directory.appending(path: "s.jsonl"))
        #expect(log.count < 4_096, "the log holds references, not 4 MB of base64")
        let attributes = try FileManager.default.attributesOfItem(atPath: imagesPath + "/" + name)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let reopened = try SessionFile.open(at: sessionPath)
        #expect(reopened.issues.isEmpty)
        #expect(images(of: reopened) == [big])
    }

    @Test func `a picture whose file is missing or changed becomes a line of text`() throws {
        do {
            var file = try SessionFile.create(at: sessionPath)
            try file.append(.user("look"))
            try file.append(result([big]))
        }
        let path = imagesPath + "/" + SessionImageStore.hash(of: big.data)
        try Data("tampered".utf8).write(to: URL(fileURLWithPath: path))
        for _ in 0 ..< 2 {
            let reopened = try SessionFile.open(at: sessionPath)
            guard case .toolResult(_, let content, _, let images)? = reopened.tree.entries.last?.payload else {
                Issue.record("the result was lost")
                return
            }
            #expect(images.isEmpty)
            #expect(
                content.hasSuffix(
                    "an image read here is no longer available: the file in the session's images directory is missing or damaged]"
                ))
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func `a session written with the picture inline still opens`() throws {
        let inline = ImagePart(mediaType: "image/png", data: [1, 2, 3])
        var tree = SessionTree()
        try tree.append(.user("look"))
        try tree.append(result([inline]))
        let bytes = try SessionLog.snapshot(tree)
        #expect(String(decoding: bytes, as: UTF8.self).contains("AQID"))
        try Data(bytes).write(to: directory.appending(path: "s.jsonl"))
        let reopened = try SessionFile.open(at: sessionPath)
        #expect(images(of: reopened) == [inline])
        #expect(stored.isEmpty)
    }

    @Test func `a fork finds the pictures of its parent`() throws {
        var file = try SessionFile.create(at: sessionPath)
        try file.append(.user("look"))
        try file.append(result([big]))
        let forked = try file.fork(to: FilePath(directory.appending(path: "f.jsonl").path))
        #expect(images(of: forked) == [big])
        #expect(stored.count == 1)
    }
}
