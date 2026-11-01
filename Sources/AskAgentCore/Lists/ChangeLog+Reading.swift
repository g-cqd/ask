internal import AemiJSON
internal import Foundation

extension ChangeLog {
    /// The file at `path` replayed; `format` is kept for a file not made yet, an existing file's own header deciding otherwise.
    static func read(_ path: String, format: SessionFormat, keyring: SessionKeyring?) throws -> State {
        var state = State(format: format)
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return state }
        guard data.count <= largest else { throw SessionFileError.log(.archiveTooLarge(data.count)) }
        let bytes = [UInt8](data)
        state.knownSize = bytes.count
        var records: [ArraySlice<UInt8>]
        if bytes.starts(with: FrameFormat.magic) {
            records = try framedRecords(bytes, keyring: keyring, into: &state)
        } else {
            state.format = .plain
            records = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
            // A file ends with a line feed; what follows the last one is a record cut short.
            if let last = records.last, !last.isEmpty { state.clean = false }
            records.removeLast()
        }
        for record in records { replay(record, into: &state) }
        return state
    }

    /// One record made, or dropped when it does not read or apply; one of a kind a later ask wrote makes the list read-only.
    private static func replay(_ record: ArraySlice<UInt8>, into state: inout State) {
        let change: List.Change
        do {
            change = try AemiJSON.JSONDecoder().decode(List.Change.self, from: Array(record))
        } catch let newer as ListRecordError {
            state.newerKind = newer.kind
            return
        } catch {
            state.clean = false
            return
        }
        guard (try? state.list.apply(change)) != nil else {
            state.clean = false
            return
        }
        state.changes.append(change)
    }

    /// A framed file's records, its format, key and whether it ended cleanly kept in `state`, with a writer to append to it when so.
    private static func framedRecords(
        _ bytes: [UInt8],
        keyring: SessionKeyring?,
        into state: inout State
    ) throws -> [ArraySlice<UInt8>] {
        let header: FramedHeader
        do { header = try FramedHeader.parse(bytes) } catch { throw SessionLogReader.sessionError(error) }
        state.format = SessionFormat(compressed: header.compressed, encrypted: header.encrypted)
        if header.encrypted {
            guard let keyring else { throw SessionFileError.locked }
            do { state.fileKey = try keyring.fileKey(envelope: header.envelope) } catch {
                throw SessionFileError.otherKey
            }
        }
        let read: FramedRead
        do { read = try FramedReader.read(bytes, key: state.fileKey?.key) } catch {
            throw SessionLogReader.sessionError(error)
        }
        state.clean = read.ending == .clean
        if state.clean {
            state.framer = try? FramedWriter(continuing: header, after: read.frameCount, key: state.fileKey?.key)
        }
        return read.records.map { $0[...] }
    }
}
