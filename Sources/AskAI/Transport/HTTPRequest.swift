public import Foundation
internal import Synchronization

/// One HTTP request.
public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    /// Header fields, in order.
    public var headers: [(name: String, value: String)]
    public var body: [UInt8]
    /// Whether HTTP redirects may be followed. Credential-pinned clients disable them.
    public var allowsRedirects: Bool

    /// A request with these fields.
    public init(
        url: URL, method: String, headers: [(name: String, value: String)], body: [UInt8], allowsRedirects: Bool = true
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.allowsRedirects = allowsRedirects
    }

    public static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        (lhs.url, lhs.method, lhs.body, lhs.allowsRedirects) == (rhs.url, rhs.method, rhs.body, rhs.allowsRedirects)
            && lhs.headers.elementsEqual(rhs.headers) { $0.name == $1.name && $0.value == $1.value }
    }
}
