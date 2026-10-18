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
