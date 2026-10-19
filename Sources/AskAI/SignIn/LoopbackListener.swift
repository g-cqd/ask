internal import Darwin
internal import Dispatch
internal import Synchronization

/// A one-shot listener for the browser's redirect at the end of an authorization-code sign-in.
///
/// It binds `127.0.0.1` only, answers with static pages that never echo the query, and returns the code from the first
/// valid callback; what counts as valid is ``LoopbackVerdict``. It serves one connection at a time with a one-second
/// read timeout, so a stalled tab delays the real callback by that much and no more. The port is free again the
/// moment the wait ends, however it ends.
///
/// This replaces an HTTP server framework: the redirect is one GET, once, on this machine (ADR-0036).
public final class LoopbackListener: Sendable {
    private static let queue = DispatchQueue(label: "ask.signin.loopback", qos: .userInitiated)

    private struct State {
        var descriptor: Int32?
        var running = false
        var stop = false
    }

    /// The port this listener holds.
    public let port: UInt16
    private let state: Mutex<State>

    private init(descriptor: Int32, port: UInt16) {
        self.port = port
        state = Mutex(State(descriptor: descriptor))
    }

    /// Starts listening on `127.0.0.1:port`; port 0 takes any free port, which is for tests, since a redirect address
    /// is fixed.
    /// - Throws: ``LoopbackError/bindFailed(errno:)``, which the caller answers with a pasted address.
    public static func bind(port: UInt16) throws(LoopbackError) -> LoopbackListener {
        let (descriptor, bound) = try LoopbackSockets.listen(port: port)
        return LoopbackListener(descriptor: descriptor, port: bound)
    }

    /// Waits for the callback and returns its code.
    /// - Parameters:
    ///   - path: the exact path the provider redirects to.
    ///   - expected: the `state` value this sign-in sent; a callback without it is ignored.
    /// - Returns: the authorization code.
    /// - Throws: ``SignInError/authorizationFailed(_:)`` when the provider reports an error for this sign-in, or
    ///   ``SignInError/cancelled`` when the task is cancelled or the listener closed.
    public func authorization(path: String, state expected: String) async throws(SignInError) -> String {
        let claimed = state.withLock { (state: inout State) -> Int32? in
            guard let descriptor = state.descriptor, !state.running, !state.stop else { return nil }
            state.running = true
            return descriptor
        }
        guard let descriptor = claimed else { throw .cancelled }
        let result: Result<String, SignInError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Self.queue.async {
                    let result = self.serve(descriptor, path: path, state: expected)
                    self.release()
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            close()
        }
        return try result.get()
    }

    /// Stops listening. A wait in progress ends as cancelled, within a tenth of a second.
    public func close() {
        state.withLock { (state: inout State) in
            state.stop = true
            if !state.running, let descriptor = state.descriptor {
                Darwin.close(descriptor)
                state.descriptor = nil
            }
        }
    }

    // MARK: - Serving

    private func serve(_ descriptor: Int32, path: String, state expected: String) -> Result<String, SignInError> {
        while true {
            if state.withLock({ $0.stop }) { return .failure(.cancelled) }
            guard let client = LoopbackSockets.accept(descriptor, milliseconds: 100) else { continue }
            defer { Darwin.close(client) }
            let request = LoopbackSockets.head(of: client, limit: LoopbackRequest.limit)
                .flatMap { LoopbackRequest(parsing: $0) }
            switch LoopbackVerdict.of(request, path: path, state: expected, port: port) {
                case .accepted(let code):
                    reply(200, to: client)
                    return .success(code)
                case .failed(let code):
                    reply(400, to: client)
                    return .failure(.authorizationFailed(code))
                case .ignored(let status): reply(status, to: client)
            }
        }
    }

    /// Closes the socket once the wait is over, so the port is free before the caller learns the outcome.
    private func release() {
        state.withLock { (state: inout State) in
            if let descriptor = state.descriptor { Darwin.close(descriptor) }
            state.descriptor = nil
            state.running = false
        }
    }

    private func reply(_ status: Int, to client: Int32) {
        let page = status == 200 ? Self.successPage : Self.errorPage
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found"][status] ?? "Error"
        let head =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\n"
            + "Referrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Length: \(page.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
        LoopbackSockets.write(Array((head + page).utf8), to: client)
    }

    private static let successPage =
        "<!doctype html><meta charset=utf-8><title>Signed in</title><p>Sign-in complete. You can close this window and return to ask.</p>"
    private static let errorPage =
        "<!doctype html><meta charset=utf-8><title>Sign-in failed</title><p>Sign-in could not be completed. Return to ask and try again.</p>"
}
