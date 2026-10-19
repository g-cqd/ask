/// What the callback listener does with one request.
enum LoopbackVerdict: Equatable, Sendable {
    /// Answer with this status and a static error page, and keep waiting.
    case ignored(status: Int)
    /// The provider redirected back with this code for this sign-in.
    case accepted(code: String)
    /// The provider redirected back with an error, for this sign-in, named by this allowlisted word.
    case failed(code: String)

    /// The verdict on `request` for a sign-in expecting `path` and `state`, on `port`.
    ///
    /// Only a `GET` on the exact path from this machine is considered. A request with the wrong or missing `state` is
    /// refused and ignored: a stray request must not be able to end, or complete, someone else's sign-in.
    static func of(_ request: LoopbackRequest?, path: String, state: String, port: UInt16) -> LoopbackVerdict {
        guard let request else { return .ignored(status: 400) }
        guard request.method == "GET", LoopbackRequest.allows(host: request.host, port: port), request.path == path
        else {
            return .ignored(status: 404)
        }
        guard request.value(of: "state") == state else { return .ignored(status: 400) }
        if let error = request.value(of: "error") { return .failed(code: safe(error)) }
        guard let code = request.value(of: "code"), !code.isEmpty else { return .ignored(status: 400) }
        return .accepted(code: code)
    }

    /// An error code as the provider words it: lower-case letters and underscores, or nothing the user is shown.
    private static func safe(_ code: String) -> String {
        let fits =
            (1 ... 64).contains(code.utf8.count) && code.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F }
        return fits ? code : "error"
    }
}
