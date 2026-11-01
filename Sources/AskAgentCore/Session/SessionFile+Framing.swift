/// A session kept as a framed file (ADR-0138): each JSONL line a frame, compressed, encrypted, or both.
extension SessionFile {
    /// A file's bytes, and for a framed file the writer that appends to it.
    struct Encoded: ~Copyable {
        let bytes: [UInt8]
        var framer: FramedWriter?
    }

    /// `snapshot`, newline-terminated JSONL, as the file `format` keeps it: as it is, or a header and a frame per line.
    static func encode(_ snapshot: [UInt8], format: SessionFormat, fileKey: FileKey?) throws(SessionFileError)
        -> Encoded
    {
        guard format.isFramed else { return Encoded(bytes: snapshot, framer: nil) }
        guard !format.encrypted || fileKey != nil else { throw .locked }
        do throws(FramedFileError) {
            var writer = try FramedWriter(
                compressed: format.compressed,
                key: format.encrypted ? fileKey?.key : nil,
                envelope: fileKey?.envelope ?? []
            )
            var bytes = writer.header.bytes
            for line in snapshot.split(separator: 0x0A, omittingEmptySubsequences: true) {
                bytes += try writer.append(Array(line))
            }
            return Encoded(bytes: bytes, framer: writer)
        } catch {
            throw SessionLogReader.sessionError(error)
        }
    }

    /// The bytes that append `record`, a newline-terminated line: as it is, or its frame.
    mutating func framed(_ record: [UInt8]) throws(SessionFileError) -> [UInt8] {
        guard framer != nil else { return record }
        do throws(FramedFileError) {
            return try framer!.append(Array(record.last == 0x0A ? record.dropLast() : record[...]))
        } catch {
            throw SessionLogReader.sessionError(error)
        }
    }

    /// Rewrites the file in `format`, for `/encrypt`: a new data key when encryption is turned on, none when it is turned off. The file
    /// as it was is not kept, unless it was read damaged and not yet repaired: damaged bytes are never discarded (ADR-0013). Undone if the
    /// rewrite fails.
    /// - Parameters:
    ///   - format: how the file is to be kept.
    ///   - keyring: the keys to encrypt under, when encryption is turned on.
    /// - Throws: ``SessionFileError/locked`` when encryption is asked for with no keys; an I/O error.
    public mutating func change(to format: SessionFormat, keyring: SessionKeyring? = nil) throws(SessionFileError) {
        guard format != self.format else { return }
        let previous = (self.format, self.keyring, fileKey)
        if let keyring { self.keyring = keyring }
        if format.encrypted, fileKey == nil {
            guard let keyring = self.keyring else { throw .locked }
            do { fileKey = try keyring.newFileKey() } catch { throw .locked }
        }
        if !format.encrypted { fileKey = nil }
        self.format = format
        let clearPictures = format.encrypted && !previous.0.encrypted ? clearPictureNames : []
        do {
            try rewrite(keepingOriginal: needsRewrite)
        } catch {
            (self.format, self.keyring, fileKey) = previous
            throw error
        }
        // The rewrite sealed them again; the clear copies go, unless another session may still name them.
        if !clearPictures.isEmpty { removeClearPictures(named: clearPictures) }
    }
}
