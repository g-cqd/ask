internal import CryptoKit

/// Reads a framed file as it arrives, a chunk at a time (ADR-0138, section 3), so opening one holds a frame, not the file, as
/// ``SessionLogReader`` does for JSONL (roadmap 0088). Each record goes to the caller as it is decoded; reading stops at the first frame
/// that does not check, which ``finish()`` calls a torn tail when nothing follows it and damage when something does.
struct FrameScanner: ~Copyable {
    /// What a frame gave.
    enum Record {
        case bytes([UInt8])
        /// A record longer than the limit: dropped unread, as an over-long JSONL line is.
        case tooLong
    }

    private(set) var header: FramedHeader?
    /// The data key, once the header has said which: given by ``keyFor`` when the header is read.
    private(set) var key: SymmetricKey?
    private let keyFor: (FramedHeader) throws(FramedFileError) -> SymmetricKey?
    private let recordLimit: Int
    private var inflater: Inflater?
    private var pending: [UInt8] = []
    private var index = 0
    /// Bytes fed so far, and up to the end of the last good frame.
    private var fed = 0
    private(set) var validLength = 0
    /// The frame that did not check, and where it ends: torn if the file ends there, damage if it goes on.
    private var failure: (index: Int, end: Int)?
    private var damagedHeader: FramedFileError?

    /// - Parameters:
    ///   - recordLimit: the longest record kept; a frame cannot hold more than this and its overhead.
    ///   - keyFor: the data key for the file whose header this is, nil when it is not encrypted; called once, when the header is read.
    init(recordLimit: Int = .max, keyFor: @escaping (FramedHeader) throws(FramedFileError) -> SymmetricKey?) {
        self.keyFor = keyFor
        self.recordLimit = recordLimit
    }

    /// A scanner for a file encrypted under `key`, or not encrypted when it is nil.
    init(key: SymmetricKey?, recordLimit: Int = .max) {
        self.init(recordLimit: recordLimit) { _ throws(FramedFileError) in key }
    }

    var frameCount: Int { index }

    mutating func feed(_ chunk: ArraySlice<UInt8>, _ record: (Record) throws(SessionLogError) -> Void)
        throws(FramedFileError)
    {
        fed += chunk.count
        guard failure == nil, damagedHeader == nil else { return }
        pending += chunk
        if header == nil {
            do throws(FramedFileError) {
                let parsed = try FramedHeader.parse(pending)
                key = parsed.encrypted ? try keyFor(parsed) : nil
                guard !parsed.encrypted || key != nil else { throw FramedFileError.needsKey }
                header = parsed
                inflater = parsed.compressed ? try Inflater() : nil
                pending.removeFirst(parsed.bytes.count)
                validLength = parsed.bytes.count
            } catch .truncatedHeader {
                return
            } catch {
                throw error
            }
        }
        try frames(record)
    }

    /// How the file ended. Throws when it ended before its header did.
    mutating func finish() throws(FramedFileError) -> FramedEnding {
        guard header != nil else {
            throw pending.starts(with: FrameFormat.magic) || pending.isEmpty ? .truncatedHeader : .notFramed
        }
        if let failure { return fed > failure.end ? .damaged(frame: failure.index) : .tornTail }
        return pending.isEmpty ? .clean : .tornTail
    }

    private mutating func frames(_ record: (Record) throws(SessionLogError) -> Void) throws(FramedFileError) {
        guard let header else { return }
        var offset = 0
        defer {
            // After a failure nothing more is read, so nothing is kept.
            if failure == nil { pending.removeFirst(offset) } else { pending = [] }
        }
        while pending.count - offset >= FrameFormat.frameHeaderLength {
            let length = Int(FrameFormat.readLE32(pending, at: offset))
            guard FrameFormat.readLE32(pending, at: offset + 5) == FrameFormat.crc32(pending[offset ..< (offset + 5)]),
                FrameFormat.Kind(rawValue: pending[offset + 4]) != nil
            else {
                // A frame header is written whole or cut short; one that is whole and wrong was changed.
                fail(end: validLength + FrameFormat.frameHeaderLength)
                return
            }
            guard pending.count - offset - FrameFormat.frameHeaderLength >= length else { return }
            let start = offset + FrameFormat.frameHeaderLength
            let opened = open(pending[start ..< (start + length)], header: header)
            guard let opened else {
                fail(end: validLength + FrameFormat.frameHeaderLength + length)
                return
            }
            do { try record(opened) } catch { throw .record(error) }
            offset = start + length
            validLength += FrameFormat.frameHeaderLength + length
            index += 1
        }
    }

    private mutating func fail(end: Int) {
        failure = (index, end)
    }

    /// A frame's record: decrypted, decompressed and checked; nil when any step fails.
    private func open(_ body: ArraySlice<UInt8>, header: FramedHeader) -> Record? {
        var plain = body
        if header.encrypted, let key {
            let data = FrameFormat.authenticatedData(headerDigest: header.digest, index: index)
            guard let box = try? AES.GCM.SealedBox(combined: plain),
                let opened = try? AES.GCM.open(box, using: key, authenticating: data)
            else { return nil }
            plain = Array(opened)[...]
        }
        guard let inflater else { return plain.count > recordLimit ? .tooLong : .bytes(Array(plain)) }
        // Compressed only: the record's CRC-32 follows its deflate data.
        let data = header.encrypted ? plain : plain.dropLast(4)
        guard header.encrypted || plain.count >= 4 else { return nil }
        switch inflater.decompress(data, limit: recordLimit) {
            case .invalid: return nil
            case .tooLong: return .tooLong
            case .bytes(let record):
                if !header.encrypted,
                    FrameFormat.crc32(record[...]) != FrameFormat.readLE32(Array(plain.suffix(4)), at: 0)
                {
                    return nil
                }
                return .bytes(record)
        }
    }
}
