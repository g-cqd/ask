internal import Darwin
internal import Foundation

/// The process's own environment: read once, and blanked in place for the variables that must not outlive their use.
///
/// Another process of the same user can read this one's original environment with `sysctl(KERN_PROCARGS2)`, whatever ask's sandbox
/// says about files and `ps` (ADR-0112). `unsetenv` does not help: it edits the table and leaves the strings the kernel reports.
/// Only overwriting the strings changes what that call returns. A caller must therefore take its snapshot before blanking.
public enum ProcessEnvironment {
    /// The environment as the process holds it now.
    public static func snapshot() -> [String: String] { ProcessInfo.processInfo.environment }

    /// Overwrites the value of each variable whose name `hidden` accepts with NUL bytes, in the string the process was started with.
    ///
    /// The names stay, so the environment's shape is unchanged; only the values go. A later `getenv` returns an empty value.
    /// - Parameter hidden: decides from the name alone. It is never given a value.
    /// - Complexity: O(total bytes of the environment).
    public static func conceal(where hidden: (String) -> Bool) {
        // Invariant: `environ` is a nil-terminated array of NUL-terminated strings, and each entry is written only within its own length.
        var cursor = unsafe environ
        while let entry = unsafe cursor.pointee {
            let length = unsafe strlen(entry)
            if let equals = unsafe memchr(entry, 0x3D, length) {
                let nameLength = unsafe UnsafeRawPointer(equals) - UnsafeRawPointer(entry)
                let name = unsafe String(
                    decoding: UnsafeRawBufferPointer(start: entry, count: nameLength), as: UTF8.self)
                if hidden(name) { unsafe _ = memset(equals + 1, 0, length - nameLength - 1) }
            }
            unsafe cursor += 1
        }
    }
}
