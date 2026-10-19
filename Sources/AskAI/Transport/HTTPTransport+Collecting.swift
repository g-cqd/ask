extension HTTPTransport {
    /// Sends `request` and collects the whole answer, for the small bodies of tokens, sign-ins and errors.
    /// - Parameters:
    ///   - request: what to send.
    ///   - limit: the most body bytes accepted, so a broken server cannot grow memory without bound.
    /// - Returns: the status and the body.
    /// - Throws: the transport's own error, ``HTTPTransportError/bodyTooLarge(limit:)``, or `CancellationError`; the
    ///   caller names them in its own terms.
    func collecting(_ request: HTTPRequest, limit: Int = 64 << 10) async throws -> (status: Int, body: [UInt8]) {
        let reply = try await send(request)
        return (reply.status, try await reply.collect(limit: limit))
    }
}
