internal import Darwin
internal import Synchronization

// Writing to a job and stopping it; apart from Job.swift to keep each file under the
// 250-line ceiling.
extension Job {
    // MARK: - Input and stopping

    /// Sends `bytes` to standard input.
    /// - Returns: false when input is closed or the job has ended.
    func write(_ bytes: [UInt8]) -> Bool {
        state.withLock { state in
            guard let input = state.input else { return false }
            if case .terminated = input.yield(bytes) { return false }
            return true
        }
    }

    /// Closes standard input, so the command sees end-of-file.
    func closeInput() {
        state.withLock { state in
            state.input?.finish()
            state.input = nil
        }
    }

    /// Asks the job to stop; ``ended()`` says when it has.
    func stop() { state.withLock { $0.task }?.cancel() }

    /// Signals the job's whole process group at once, for exit paths that cannot wait.
    func signalGroup(_ signal: Int32) {
        guard let pid = state.withLock({ $0.status == .running ? $0.pid : nil }) else { return }
        kill(-pid, signal)
    }
}
