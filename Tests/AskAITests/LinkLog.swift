import Foundation
import Synchronization

@testable import AskAI

/// The links a sign-in showed, in order.
final class LinkLog: Sendable {
    private let links = Mutex<[URL]>([])
    var all: [URL] { links.withLock { $0 } }
    func add(_ prompt: SignInPrompt) { links.withLock { $0.append(prompt.url) } }
}
