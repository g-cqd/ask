import Foundation

@testable import AskAI

extension HTTPRequest {
    /// The body as text, for a test to read.
    var bodyText: String { String(decoding: body, as: UTF8.self) }
}
