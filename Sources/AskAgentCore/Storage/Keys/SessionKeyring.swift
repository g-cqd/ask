internal import CryptoKit
internal import Foundation

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

    /// The key an encrypted session's search index is sealed under (t209), derived like the pictures' key, for another use.
    var searchKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: userKey, info: Data("ask.search.v1".utf8), outputByteCount: 32)
    }

    /// The key an encrypted session's pictures are sealed under: one for every session of the user key, so the store shares them.
    var imageKey: SymmetricKey {
        HKDF<SHA256>
            .deriveKey(
                inputKeyMaterial: userKey,
                info: Data("ask.images.v1".utf8),
                outputByteCount: 32
            )
    }
}
