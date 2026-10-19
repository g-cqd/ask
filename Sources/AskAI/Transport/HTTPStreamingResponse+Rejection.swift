extension HTTPStreamingResponse {
    /// The body of a response that failed, up to 64 KiB, and the seconds its `retry-after` header asked for.
    ///
    /// Only the seconds form of `retry-after` is read; the HTTP-date form is not used by the providers ask speaks to.
    func rejection() async -> (body: [UInt8], retryAfter: Double?) {
        let body = (try? await collect(limit: 64 << 10)) ?? []
        return (body, headers["retry-after"].flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil })
    }
}
