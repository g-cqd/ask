internal import CryptoKit

/// What a process holds to read and write encrypted sessions: `keys.json`, and the user key it opened (ADR-0138, section 4). Each
/// encrypted file gets a data key of its own, carried in its header's envelope.
public struct SessionKeyring: Sendable {
    let keys: SessionKeys
    let userKey: SymmetricKey

    /// A new file's data key, and the envelope its header carries.
    func newFileKey() throws(SessionKeyError) -> FileKey {
        let key = SymmetricKey(size: .bits256)
        return FileKey(key: key, envelope: try keys.envelope(for: key, userKey: userKey))
    }

    /// The data key of the file whose header carries `envelope`.
    func fileKey(envelope: [UInt8]) throws(SessionKeyError) -> FileKey {
        FileKey(key: try keys.dataKey(in: envelope, userKey: userKey), envelope: envelope)
    }
}
