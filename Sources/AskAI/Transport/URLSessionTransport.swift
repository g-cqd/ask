public import Foundation
internal import Synchronization

/// ``HTTPTransport`` over URLSession, delivering the body in the chunks the system receives.
///
/// The default session is created on the first request, not with the transport: creating a URLSession loads
/// the networking stack, which a screen that has not sent anything yet should not pay for at launch.
public struct URLSessionTransport: HTTPTransport {
    private let provided: URLSession?
    private let lazySession = LazySession()

    /// A transport on `session`, by default an ephemeral one, created on first use: no cookies, cache or
    /// credentials on disk.
    public init(session: URLSession? = nil) { self.provided = session }

    private var session: URLSession { provided ?? lazySession.value }

    public func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for header in request.headers { urlRequest.addValue(header.value, forHTTPHeaderField: header.name) }
        urlRequest.httpBody = request.body.isEmpty ? nil : Data(request.body)

        let (body, continuation) = AsyncThrowingStream<[UInt8], any Error>.makeStream()
        let task = session.dataTask(with: urlRequest)
        let delegate = StreamingDelegate(body: continuation, allowsRedirects: request.allowsRedirects)
        task.delegate = delegate
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
        let (status, headers) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (head: CheckedContinuation<(Int, [String: String]), any Error>) in
                delegate.awaitHead(head)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        return HTTPStreamingResponse(status: status, headers: headers, body: body)
    }

    /// An ephemeral session made once, on first use, by whichever request needs it first.
    private final class LazySession: Sendable {
        private let session = Mutex<URLSession?>(nil)

        var value: URLSession {
            session.withLock { existing in
                if let existing { return existing }
                let created = URLSession(configuration: .ephemeral)
                existing = created
                return created
            }
        }
    }

    /// Bridges one data task's delegate callbacks to a status continuation and a body stream.
    private final class StreamingDelegate: NSObject, URLSessionDataDelegate, Sendable {
        private let body: AsyncThrowingStream<[UInt8], any Error>.Continuation
        /// Resumed exactly once: by the response, or by completion when no response came.
        private let head = Mutex<CheckedContinuation<(Int, [String: String]), any Error>?>(nil)

        private let allowsRedirects: Bool

        init(body: AsyncThrowingStream<[UInt8], any Error>.Continuation, allowsRedirects: Bool) {
            self.body = body
            self.allowsRedirects = allowsRedirects
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(allowsRedirects ? request : nil)
        }

        func awaitHead(_ continuation: CheckedContinuation<(Int, [String: String]), any Error>) {
            head.withLock { $0 = continuation }
        }

        /// The completion-handler form runs on the session's serial delegate queue with the data and completion
        /// callbacks, so their order is the delivery order. The `async` form's ordering relative to them is not
        /// documented. It passes the same tests; no race was observed, so this is a choice for a stated
        /// guarantee, not a fix.
        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
        ) {
            let http = response as? HTTPURLResponse
            // Header names are case-insensitive; lowercased keys make lookups exact.
            var headers: [String: String] = [:]
            for (name, value) in http?.allHeaderFields ?? [:] {
                if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
            }
            head.withLock { $0.take() }?.resume(returning: (http?.statusCode ?? 0, headers))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            body.yield([UInt8](data))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            if let pending = head.withLock({ $0.take() }) {
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    pending.resume(throwing: CancellationError())
                } else {
                    pending.resume(throwing: HTTPTransportError.failed(error?.localizedDescription ?? "no response"))
                }
            }
            if let error { body.finish(throwing: error) } else { body.finish() }
        }
    }
}
