import Darwin
import Synchronization

/// Resolves once the command has printed `child <pid>`.
final class Started: Sendable {
    private let state = Mutex<(text: String, waiter: CheckedContinuation<pid_t, any Error>?, pid: pid_t?)>(
        ("", nil, nil))

    func received(_ bytes: [UInt8]) {
        let ready: (CheckedContinuation<pid_t, any Error>, pid_t)? = state.withLock { state in
            state.text += String(decoding: bytes, as: UTF8.self)
            guard state.pid == nil,
                let line = state.text.split(separator: "\n").first(where: { $0.hasPrefix("child ") }),
                let pid = pid_t(line.dropFirst(6))
            else { return nil }
            state.pid = pid
            return state.waiter.take().map { ($0, pid) }
        }
        if let (waiter, pid) = ready { waiter.resume(returning: pid) }
    }

    func child() async throws -> pid_t {
        try await withCheckedThrowingContinuation { continuation in
            let pid: pid_t? = state.withLock { state in
                if state.pid == nil { state.waiter = continuation }
                return state.pid
            }
            if let pid { continuation.resume(returning: pid) }
        }
    }
}
