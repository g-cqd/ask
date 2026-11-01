/// Why a session key could not be made, opened or read.
enum SessionKeyError: Error, Equatable {
    /// The password does not open the user key.
    case wrongPassword
    /// The recovery code reads, but does not open the user key.
    case wrongRecoveryCode
    /// The text is not a recovery code: the wrong length, or a character the code does not use.
    case unreadableRecoveryCode
    /// `keys.json` is not one this version reads.
    case unreadableKeyFile
    /// `keys.json` asks for a derivation outside the bounds ask accepts.
    case derivationOutOfBounds
    /// The envelope's data key was sealed under another user key.
    case otherUserKey
    /// The envelope was changed or is not one.
    case damagedEnvelope
}
