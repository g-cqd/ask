public import Foundation

/// One recorded session in a project's directory.
public struct SessionListing: Sendable, Equatable {
    /// The session file.
    public let path: String
    /// When it was last written: what `--continue` goes by.
    public let modified: Date

    /// The file name, which is how `--resume` names it.
    public var name: String { (path as NSString).lastPathComponent }
}
