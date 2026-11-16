internal import Darwin
internal import Foundation

/// What the process has taken of memory, and a watch over it. JavaScriptCore has no public limit on what a script may
/// allocate (a script asking for 4 GB got them in 0.4 s; diary 2026-11-15-17), so the host watches itself and ends.
package enum CodemodeMemory {
    /// What the system says of the process `pid`: its physical footprint in bytes (what it has dirtied, which is what the
    /// system charges it) and when it started, which with its id says which process it is. Nil when unknown, as for one that
    /// is gone.
    package static func usage(of pid: Int32) -> (footprint: Int, started: UInt64)? {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            unsafe pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                unsafe proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        return status == 0 ? (Int(usage.ri_phys_footprint), usage.ri_proc_start_abstime) : nil
    }

    /// This process's physical footprint in bytes. 0 when unknown.
    package static func footprint() -> Int { usage(of: getpid())?.footprint ?? 0 }

    /// Calls `exceeded` once, from a thread of its own, when the footprint passes `limit` bytes. Looked at every 2 ms: a script
    /// can take 10 MB a millisecond.
    package static func watch(limit: Int, exceeded: @escaping @Sendable () -> Void) {
        Thread.detachNewThread {
            while footprint() <= limit { usleep(2000) }
            exceeded()
        }
    }
}
