import Synchronization

/// Resolves once the output seen so far contains a text: lets a test act after a command printed, without
/// sleeping.
final class Printed: Sendable {
    private let needle: String
    private let state = Mutex<(text: String, waiter: CheckedContinuation<Void, Never>?, seen: Bool)>(("", nil, false))

    init(_ needle: String) { self.needle = needle }

    func received(_ bytes: [UInt8]) {
        let waiter: CheckedContinuation<Void, Never>? = state.withLock { state in
            state.text += String(decoding: bytes, as: UTF8.self)
            guard !state.seen, state.text.contains(needle) else { return nil }
            state.seen = true
            return state.waiter.take()
        }
        waiter?.resume()
    }

    func seen() async {
        await withCheckedContinuation { continuation in
            let already = state.withLock { state in
                if !state.seen { state.waiter = continuation }
                return state.seen
            }
            if already { continuation.resume() }
        }
    }
}
