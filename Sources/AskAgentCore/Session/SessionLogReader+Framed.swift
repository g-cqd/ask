internal import System

/// Reading a framed session (ADR-0138): the frames' records are the JSONL lines, each whole, given to the same recovery a JSONL file
/// gets; a frame that does not check becomes an issue, so the first change rewrites the file and keeps the original as it was.
extension SessionLogReader {
    // swiftlint:disable:next function_parameter_count
    func recoverFramed(
        first: ArraySlice<UInt8>,
        _ descriptor: FileDescriptor,
        size: Int,
        limits: SessionLog.Limits,
        images: SessionImageStore?,
        keyring: SessionKeyring?
    ) throws(SessionFileError) -> RecoveredSession {
        var recovery = SessionLogRecovery(limits: limits, images: images)
        var fileKey: FileKey?
        var scanner = FrameScanner(recordLimit: limits.maximumLineBytes) { header throws(FramedFileError) in
            guard let keyring else { throw .needsKey }
            do throws(SessionKeyError) {
                fileKey = try keyring.fileKey(envelope: header.envelope)
            } catch .otherUserKey {
                throw .otherKey
            } catch {
                throw .damagedHeader
            }
            return fileKey?.key
        }
        var number = 0
        var decoded = 0
        // A record each: the archive's limit applies to what the frames hold, not to their compressed size.
        let consume = { (record: FrameScanner.Record) throws(SessionLogError) -> Void in
            number += 1
            guard case .bytes(let line) = record else {
                recovery.skipTooLong(number: number)
                return
            }
            decoded += line.count + 1
            guard decoded <= limits.maximumArchiveBytes else { throw .archiveTooLarge(decoded) }
            try recovery.consume(line[...], number: number, isFinal: false)
        }
        do { try scanner.feed(first, consume) } catch { throw Self.sessionError(error) }
        try readChunks(descriptor, size: size, from: first.count) { chunk throws(SessionFileError) in
            do throws(FramedFileError) { try scanner.feed(chunk, consume) } catch { throw Self.sessionError(error) }
            return true
        }
        do { return try finish(&scanner, recovery: recovery, fileKey: fileKey) } catch {
            throw Self.sessionError(error)
        }
    }

    private func finish(
        _ scanner: inout FrameScanner,
        recovery: SessionLogRecovery,
        fileKey: FileKey?
    ) throws(FramedFileError) -> RecoveredSession {
        let ending: FramedEnding
        do throws(FramedFileError) {
            ending = try scanner.finish()
        } catch .truncatedHeader {
            // A crash while the file was first written: nothing in it, as an empty JSONL file holds nothing.
            return RecoveredSession(tree: SessionTree(), issues: [.missingHeader])
        }
        guard let header = scanner.header else { throw .truncatedHeader }
        var result = recovery.result
        var issues = result.issues
        switch ending {
            case .clean: break
            case .tornTail: issues.append(.tornFinalFrame(frame: scanner.frameCount))
            case .damaged(let frame): issues.append(.damagedFrame(frame: frame))
        }
        result = RecoveredSession(
            tree: result.tree,
            issues: issues,
            formatVersion: result.formatVersion,
            framing: FramedOpening(header: header, frameCount: scanner.frameCount, fileKey: fileKey)
        )
        return result
    }

    static func sessionError(_ error: FramedFileError) -> SessionFileError {
        switch error {
            case .needsKey: .locked
            case .otherKey: .otherKey
            case .record(let failure): .log(failure)
            case .notFramed, .truncatedHeader, .damagedHeader, .unsupportedVersion, .notResumable, .compression:
                .unreadableHeader
        }
    }
}
