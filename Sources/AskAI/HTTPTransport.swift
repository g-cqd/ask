public import Foundation
internal import Synchronization

/// One HTTP request.
public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    /// Header fields, in order.
    public var headers: [(name: String, value: String)]
    public var body: [UInt8]

    /// A request with these fields.
    public init(url: URL, method: String, headers: [(name: String, value: String)], body: [UInt8]) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    public static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        lhs.url == rhs.url && lhs.method == rhs.method && lhs.body == rhs.body
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
    }
}

/// A response whose body arrives as it is received.
public struct HTTPStreamingResponse: Sendable {
    public let status: Int
    /// The body, one chunk per network delivery. Ends when the response ends; throws if it is cut.
    public let body: AsyncThrowingStream<[UInt8], any Error>

    /// A response with this status and body.
    public init(status: Int, body: AsyncThrowingStream<[UInt8], any Error>) {
        self.status = status
        self.body = body
    }

    /// The whole body, for small responses such as errors and tokens.
    /// - Parameter limit: the most bytes to accept, so a broken server cannot grow memory without bound.
    /// - Returns: every byte of the body.
    /// - Throws: ``HTTPTransportError/bodyTooLarge(limit:)``, or the error that cut the body.
    public func collect(limit: Int = 1 << 20) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for try await chunk in body {
            bytes += chunk
            guard bytes.count <= limit else { throw HTTPTransportError.bodyTooLarge(limit: limit) }
        }
        return bytes
    }
}

/// Why a request did not complete.
public enum HTTPTransportError: Error, Sendable, Equatable {
    /// The connection failed before a response arrived, with the system's description.
    case failed(String)
    case bodyTooLarge(limit: Int)
}

/// Sends HTTP requests. Injected, so the provider client is tested without a network.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns as soon as the response's status is known.
    /// - Throws: ``HTTPTransportError/failed(_:)`` when no response arrives, or `CancellationError`.
    func send(_ request: HTTPRequest) async throws -> HTTPStreamingResponse
}

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
        let delegate = StreamingDelegate(body: continuation)
        task.delegate = delegate
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (head: CheckedContinuation<Int, any Error>) in
                delegate.awaitHead(head)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        return HTTPStreamingResponse(status: status, body: body)
    }
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
    private let head = Mutex<CheckedContinuation<Int, any Error>?>(nil)

    init(body: AsyncThrowingStream<[UInt8], any Error>.Continuation) { self.body = body }

    func awaitHead(_ continuation: CheckedContinuation<Int, any Error>) {
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
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        head.withLock { $0.take() }?.resume(returning: status)
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
