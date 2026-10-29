internal import AemiJSON
internal import Darwin
internal import Foundation

/// Why credentials could not be read or written. Paths are reported; contents never are.
public enum CredentialFileError: Error, Sendable, Equatable {
    /// Group or other users can read or write the file. It is refused, as ssh refuses an exposed key.
    case exposed(path: String, mode: Int)
    /// The file exists but is not credentials.
    case damaged(path: String)
    /// A system call failed.
    case io(path: String, errno: Int32)
    /// Another ask held the short lock that serialises saves for longer than this one waited.
    case locked(path: String)
    /// The selected registration was removed or authenticated as another identity after it was selected.
    case connectionChanged(path: String)
    /// Registration metadata needs a newer writer; interpreting and rewriting it would be unsafe.
    case newerFormat(path: String)
    /// The file says a record's secrets are in the secret store (the Keychain), and the store has no item for it.
    case secretMissing(path: String, record: String)
    /// The secret store refused a read or a write; the file was left as it was.
    case secretStore(path: String, status: Int32)
}
