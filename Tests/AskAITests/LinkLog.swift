import Foundation
import Synchronization

/// The links a sign-in showed, in order.
final class LinkLog: Sendable {
    private let links = Mutex<[URL]>([])
    var all: [URL] { links.withLock { $0 } }
    func add(_ url: URL) { links.withLock { $0.append(url) } }
}
