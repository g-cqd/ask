internal import Darwin

/// How a file, or the directory it is in, is made durable before the next step (roadmap 0060, ADR-0089).
///
/// Replacing a file by renaming a new one over it is only crash-safe if the new bytes reach the disk before the rename does, and the
/// rename itself reaches the disk before the caller is told it worked. Plain `fsync` on macOS does not make the drive order its
/// writes, so a rename can survive a crash that its bytes did not; the barrier does, for a fraction of a full flush. Measured on this
/// machine, a 2 KB replace by rename: 0.105 ms with no flush, 0.12 ms with `fsync`, 0.47 ms with the barrier on the file and the
/// directory, 6.0 ms with `F_FULLFSYNC` (more than the 5 ms action budget on its own). Sessions use the barrier for the same reason
/// (ADR-0017); this is the same rule, `AemiIO`'s `.barrier`, for the writers that cannot depend on it.
public enum FileFlush {
    /// Orders everything written through `descriptor`, a file or a directory, before whatever is written after it.
    /// - Parameter descriptor: an open descriptor.
    /// - Returns: 0, or -1 with `errno` set. Falls back to `fsync` where the barrier is not supported.
    public static func barrier(_ descriptor: Int32) -> Int32 {
        if fcntl(descriptor, F_BARRIERFSYNC) != -1 { return 0 }
        return fsync(descriptor)
    }
}
