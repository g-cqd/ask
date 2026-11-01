internal import CryptoKit

/// One encrypted file's data key, and the envelope its header carries it in.
struct FileKey: Sendable, Equatable {
    let key: SymmetricKey
    let envelope: [UInt8]
}
