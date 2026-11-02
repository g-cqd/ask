import Compression
import Foundation

/// A zip archive made in a test: each file stored or deflated, with the local headers and central directory VS Code's builds have.
enum TestZip {
    static func make(_ files: [(name: String, text: String)], deflate: Bool = true) -> [UInt8] {
        var archive: [UInt8] = []
        var directory: [UInt8] = []
        for file in files {
            let raw = Array(file.text.utf8)
            let data = deflate ? deflated(raw) : raw
            let name = Array(file.name.utf8)
            let offset = archive.count
            archive += [0x50, 0x4B, 0x03, 0x04] + le16(20) + le16(0) + le16(deflate ? 8 : 0) + le32(0) + le32(0)
            archive += le32(data.count) + le32(raw.count) + le16(name.count) + le16(4) + name + [0, 0, 0, 0] + data
            directory +=
                [0x50, 0x4B, 0x01, 0x02] + le16(20) + le16(20) + le16(0) + le16(deflate ? 8 : 0) + le32(0) + le32(0)
            directory += le32(data.count) + le32(raw.count) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0)
            directory += le32(0) + le32(offset) + name
        }
        let start = archive.count
        archive += directory
        archive += [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        archive += le32(directory.count) + le32(start) + le16(0)
        return archive
    }

    static func deflated(_ raw: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: raw.count + 1_024)
        let written = output.withUnsafeMutableBufferPointer { out in
            raw.withUnsafeBufferPointer { input in
                compression_encode_buffer(
                    out.baseAddress!,
                    out.count,
                    input.baseAddress!,
                    raw.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        return Array(output.prefix(written))
    }

    static func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    static func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16(value >> 16 & 0xFFFF) }
}
