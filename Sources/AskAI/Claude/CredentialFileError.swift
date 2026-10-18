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
}
