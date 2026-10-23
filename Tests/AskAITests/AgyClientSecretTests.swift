internal import Foundation
internal import Testing

@testable import AskAI

/// Finding the Antigravity client's OAuth secret in an installed `agy`, without trusting its shape (roadmap 0052).
///
/// Probed on the real binary, 1.4.2 and 1.4.6 (diary 2026-10-23-13): three `GOCSPX-` strings lie in the string table, two of them
/// adjacent with no separator, so a greedy match returns a 70-byte value that is in no file; only one 35-byte string is accepted
/// by Google's token endpoint, and the other two answer `invalid_client`.
struct AgyClientSecretTests {
    private static let real = "GOCSPX-" + String(repeating: "a", count: 28)
    private static let decoy = "GOCSPX-" + String(repeating: "Z", count: 28)

    private func image(_ pieces: [String], padding: Int = 20) -> [UInt8] {
        var bytes: [UInt8] = []
        for piece in pieces {
            bytes += (0 ..< padding).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) | 0x80 }
            bytes += Array(piece.utf8)
        }
        return bytes + [0, 0, 0]
    }

    @Test func `a planted secret in binary noise is found at its exact length`() {
        #expect(AgyClientSecret.candidates(in: image([Self.real])).first == Self.real)
    }

    @Test func `underscores and hyphens belong to a secret, as in the real ones`() {
        let mixed = "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t-"
        let secret = String(mixed.prefix(35))
        #expect(secret.utf8.count == 35 && secret.contains("_") && secret.dropFirst(7).contains("-"))
        #expect(AgyClientSecret.candidates(in: image([secret])).first == secret)
    }

    @Test func `two secrets with no separator are two candidates, never one oversized value`() {
        let found = AgyClientSecret.candidates(in: image([Self.real + Self.decoy], padding: 0))
        #expect(found.prefix(2).sorted() == [Self.decoy, Self.real].sorted())
        #expect(!found.contains(Self.real + Self.decoy))
        #expect(found.allSatisfy { $0.utf8.count <= 47 })
    }

    @Test func `exact-length candidates come first, in the order they appear, and repeats are dropped`() {
        let found = AgyClientSecret.candidates(in: image([Self.decoy, Self.real, Self.decoy]))
        #expect(Array(found.prefix(2)) == [Self.decoy, Self.real])
        #expect(Set(found).count == found.count)
        #expect(found.filter { $0.utf8.count == 35 }.count == 2)
        let lengths = found.map(\.utf8.count)
        #expect(lengths.firstIndex { $0 != 35 } ?? lengths.count >= 2)
    }

    @Test(arguments: [" ", "\u{7f}", "\u{0}", "é", "/", "+", "="])
    func `a character Google never puts in a secret ends it`(_ stop: String) {
        let short = "GOCSPX-" + String(repeating: "q", count: 28)
        let found = AgyClientSecret.candidates(in: image([short + stop + String(repeating: "q", count: 20)]))
        #expect(found.first == short)
        #expect(!found.contains { $0.contains(stop) })
    }

    @Test func `a prefix with too little after it, or cut off by the end of the image, is not a candidate`() {
        #expect(AgyClientSecret.candidates(in: image(["GOCSPX-short"])).isEmpty)
        #expect(AgyClientSecret.candidates(in: Array(("GOCSPX-" + String(repeating: "a", count: 10)).utf8)).isEmpty)
        #expect(AgyClientSecret.candidates(in: []).isEmpty)
        #expect(AgyClientSecret.candidates(in: Array("GOCSPX".utf8)).isEmpty)
    }

    @Test func `a longer body, as a future version might use, is offered too, after every exact-length candidate`() {
        let longer = "GOCSPX-" + String(repeating: "b", count: 33)
        let found = AgyClientSecret.candidates(in: image([longer, Self.real]))
        #expect(found.contains(Self.real) && found.contains(longer))
        let firstOther = found.firstIndex { $0.utf8.count != 35 } ?? found.count
        #expect(found.prefix(firstOther).allSatisfy { $0.utf8.count == 35 })
        #expect(found.suffix(from: firstOther).allSatisfy { $0.utf8.count != 35 })
        #expect(found.firstIndex(of: Self.real)! < firstOther && found.firstIndex(of: longer)! >= firstOther)
    }

    @Test(arguments: Array(0 ... 70))
    func `a secret straddling a read boundary is found wherever the boundary falls`(_ shift: Int) throws {
        let bytes = image([Self.real, "GOCSPX-" + String(repeating: "c", count: 40)], padding: shift)
        let url = FileManager.default.temporaryDirectory.appending(path: "agy-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        let whole = AgyClientSecret.candidates(in: bytes)
        #expect(whole.first == Self.real)
        for chunk in [64, 65, 100] {
            let piecewise = try AgyClientSecret.candidates(inFileAt: url, chunkSize: chunk)
            #expect(piecewise == whole, "chunk \(chunk): the same list, not only the same first")
        }
        #expect(try AgyClientSecret.candidates(inFileAt: url).first == Self.real)
    }

    @Test func `a file that cannot be read is an error that names the file and no secret`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "agy-absent-\(UUID().uuidString)")
        #expect(throws: AgySecretError.unreadable(path: missing.path)) {
            try AgyClientSecret.candidates(inFileAt: missing)
        }
        let directory = FileManager.default.temporaryDirectory
        #expect(throws: AgySecretError.unreadable(path: directory.path)) {
            try AgyClientSecret.candidates(inFileAt: directory)
        }
    }

    @Test func `the finder does not hold the whole binary in memory`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "agy-big-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let block = [UInt8](repeating: 0x41, count: 1 << 20)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        for _ in 0 ..< 24 { try handle.write(contentsOf: block) }
        try handle.write(contentsOf: Array(Self.real.utf8))
        try handle.close()
        #expect(try AgyClientSecret.candidates(inFileAt: url).first == Self.real)
    }
}
