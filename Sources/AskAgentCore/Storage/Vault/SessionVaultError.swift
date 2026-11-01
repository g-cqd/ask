/// Why the state directory's keys could not be made or kept.
public enum SessionVaultError: Error, Equatable {
    /// `keys.json` exists already: making new keys would lock every session the old ones encrypted.
    case keysExist
    /// No `keys.json`: encryption was never set up.
    case noKeys
    /// A file could not be written: the errno.
    case write(errno: Int32)
}
