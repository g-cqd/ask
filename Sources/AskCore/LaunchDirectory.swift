/// Where ask runs when the directory it was started in is gone (review of 2026-11-11, note n64).
///
/// A shell keeps the directory it is in by handle. When that directory is removed and made again, or its volume is mounted again, the
/// path is there but the handle is dead: the system then reports no current directory at all, and everything ask resolves against it,
/// the project, its sessions, a command's directory, resolves against nothing.
public enum LaunchDirectory {
    public enum Resolution: Sendable, Equatable {
        /// The current directory is known: nothing to do.
        case current
        /// It is not, and the shell's own record of it (`PWD`) names a directory that is there: enter it.
        case enter(String)
        /// It is not, and nothing says where to go.
        case missing
    }

    /// What to do, given the current directory as the system reports it (empty when it has none), the shell's `PWD`, and whether a
    /// path is a directory now.
    public static func resolve(current: String, shell: String?, isDirectory: (String) -> Bool) -> Resolution {
        guard current.isEmpty else { return .current }
        guard let shell, shell.hasPrefix("/"), isDirectory(shell) else { return .missing }
        return .enter(shell)
    }
}
