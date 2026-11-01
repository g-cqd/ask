internal import CryptoKit

/// Reads a framed file (ADR-0138, section 3): every frame that checks, then how the file ended. A frame that does not check is a torn
/// tail when it is the last, and damage when frames follow it; reading stops there either way.
enum FramedReader {
    static func read(_ bytes: [UInt8], key: SymmetricKey?) throws(FramedFileError) -> FramedRead {
        let header = try FramedHeader.parse(bytes)
        guard !header.encrypted || key != nil else { throw .needsKey }
        let inflater = header.compressed ? try Inflater() : nil
        var records: [[UInt8]] = []
        var offset = header.bytes.count
        var index = 0
        var ending = FramedEnding.clean
        while offset < bytes.count {
            let remaining = bytes.count - offset
            guard remaining >= FrameFormat.frameHeaderLength else {
                ending = .tornTail
                break
            }
            let length = Int(FrameFormat.readLE32(bytes, at: offset))
            let check = FrameFormat.readLE32(bytes, at: offset + 5)
            guard check == FrameFormat.crc32(bytes[offset ..< (offset + 5)]),
                FrameFormat.Kind(rawValue: bytes[offset + 4]) != nil
            else {
                // A frame header is written whole or cut short; one that is whole and wrong was changed.
                ending = .damaged(frame: index)
                break
            }
            guard remaining - FrameFormat.frameHeaderLength >= length else {
                ending = .tornTail
                break
            }
            let start = offset + FrameFormat.frameHeaderLength
            let isLast = start + length == bytes.count
            guard
                let record = open(
                    bytes[start ..< (start + length)],
                    header: header,
                    key: key,
                    index: index,
                    inflater: inflater
                )
            else {
                ending = isLast ? .tornTail : .damaged(frame: index)
                break
            }
            records.append(record)
            offset = start + length
            index += 1
        }
        return FramedRead(header: header, records: records, ending: ending, validLength: offset, frameCount: index)
    }

    /// A frame's record: decrypted, decompressed and checked; nil when any step fails.
    private static func open(
        _ body: ArraySlice<UInt8>,
        header: FramedHeader,
        key: SymmetricKey?,
        index: Int,
        inflater: Inflater?
    ) -> [UInt8]? {
        var plain = body
        if header.encrypted, let key {
            let data = FrameFormat.authenticatedData(headerDigest: header.digest, index: index)
            guard let box = try? AES.GCM.SealedBox(combined: plain),
                let opened = try? AES.GCM.open(box, using: key, authenticating: data)
            else { return nil }
            plain = Array(opened)[...]
        }
        guard let inflater else { return Array(plain) }
        if header.encrypted { return inflater.decompress(plain) }
        // Compressed only: the record's CRC-32 follows its deflate data.
        guard plain.count >= 4 else { return nil }
        let data = plain.dropLast(4)
        let check = FrameFormat.readLE32(Array(plain.suffix(4)), at: 0)
        guard let record = inflater.decompress(data), FrameFormat.crc32(record[...]) == check else { return nil }
        return record
    }
}
