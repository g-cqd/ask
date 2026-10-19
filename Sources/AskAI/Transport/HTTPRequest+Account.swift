internal import Foundation

extension HTTPRequest {
    /// A request to an account or sign-in endpoint: it asks for JSON, and says who is asking.
    /// - Parameters:
    ///   - method: `GET` or `POST`.
    ///   - url: where to send it.
    ///   - contentType: the body's type, when there is a body.
    ///   - body: the body.
    /// - Returns: the request.
    static func account(_ method: String, _ url: URL, contentType: String? = nil, body: [UInt8] = []) -> HTTPRequest {
        var headers: [(name: String, value: String)] = [("content-type", contentType ?? "application/json")]
        headers += [("accept", "application/json"), ("user-agent", "ask")]
        return HTTPRequest(url: url, method: method, headers: headers, body: body)
    }
}
