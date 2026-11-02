import Testing

@testable import AskAI

/// A few files read out of a zip archive's ranges, as ``VSCodeBuild`` reads VS Code's official build: anything malformed is refused.
@Suite("Files are read from a zip archive's directory, stored or deflated, and nothing malformed is believed")
struct ZipDirectoryTests {
    private static let names: Set<String> = ["b.json"]

    private func read(_ archive: [UInt8], _ name: String = "b.json") -> [UInt8]? {
        guard let (offset, size) = ZipDirectory.locate(tail: Array(archive.suffix(64))),
            let entry = ZipDirectory.entries(Array(archive[offset ..< offset + size]), named: [name])?[name]
        else { return nil }
        return ZipDirectory.payload(Array(archive[entry.offset...].prefix(ZipDirectory.span(of: entry))), of: entry)
    }

    @Test(arguments: [true, false])
    func `a wanted file is read, deflated or stored`(deflate: Bool) {
        let archive = TestZip.make([("a.txt", "first"), ("b.json", #"{"version":"1.2"}"#)], deflate: deflate)
        #expect(read(archive).map { String(decoding: $0, as: UTF8.self) } == #"{"version":"1.2"}"#)
    }

    @Test func `a file that is not wanted is not listed`() {
        let archive = TestZip.make([("a.txt", "first")])
        let (offset, size) = try! #require(ZipDirectory.locate(tail: archive))
        #expect(ZipDirectory.entries(Array(archive[offset ..< offset + size]), named: Self.names) == [:])
    }

    @Test func `an archive without an end record, or a zip64 one, is not located`() {
        #expect(ZipDirectory.locate(tail: Array(repeating: 0, count: 100)) == nil)
        #expect(ZipDirectory.locate(tail: [0x50, 0x4B, 0x05]) == nil)
        var archive = TestZip.make([("b.json", "x")])
        for index in (archive.count - 6) ..< (archive.count - 2) { archive[index] = 0xFF }
        #expect(ZipDirectory.locate(tail: archive) == nil)
    }

    @Test func `a directory that is not one is refused`() {
        let archive = TestZip.make([("b.json", "x")])
        let (offset, size) = try! #require(ZipDirectory.locate(tail: archive))
        var directory = Array(archive[offset ..< offset + size])
        #expect(ZipDirectory.entries(Array(directory.prefix(40)), named: Self.names) == nil)
        #expect(ZipDirectory.entries(Array(directory.prefix(50)), named: Self.names) == nil)
        directory[0] = 0
        #expect(ZipDirectory.entries(directory, named: Self.names) == nil)
    }

    @Test func `a read that is cut short, or is not a local header, gives nothing`() throws {
        let archive = TestZip.make([("b.json", String(repeating: "y", count: 300))], deflate: false)
        let (offset, size) = try #require(ZipDirectory.locate(tail: archive))
        let entry = try #require(
            ZipDirectory.entries(Array(archive[offset ..< offset + size]), named: Self.names)?["b.json"]
        )
        #expect(ZipDirectory.payload(Array(archive.prefix(100)), of: entry) == nil)
        var unsigned = archive
        unsigned[0] = 0
        #expect(ZipDirectory.payload(unsigned, of: entry) == nil)
        let other = ZipEntry(
            name: "b.json",
            method: 12,
            compressedSize: entry.compressedSize,
            size: entry.size,
            offset: 0
        )
        #expect(ZipDirectory.payload(archive, of: other) == nil)
        let wrongSize = ZipEntry(
            name: "b.json",
            method: 0,
            compressedSize: entry.compressedSize,
            size: entry.size + 1,
            offset: 0
        )
        #expect(ZipDirectory.payload(archive, of: wrongSize) == nil)
    }

    @Test func `deflated data that inflates to more or less than its size is refused`() {
        let data = TestZip.deflated(Array(String(repeating: "z", count: 1_000).utf8))
        #expect(Inflate.raw(data, size: 1_000)?.count == 1_000)
        #expect(Inflate.raw(data, size: 999) == nil)
        #expect(Inflate.raw(data, size: 1_001) == nil)
        #expect(Inflate.raw(data, size: Inflate.limit + 1) == nil)
        #expect(Inflate.raw(data, size: Int.max - 1) == nil)
        #expect(Inflate.raw([], size: 10) == nil)
    }
}
