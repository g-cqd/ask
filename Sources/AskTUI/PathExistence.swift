internal import Foundation
internal import Synchronization

/// Whether a path in the project is on the disk (roadmap 0215), each answered once: a streamed reply lays its last block out again on
/// every delta, and the same path would be looked for each time. ``PathDisplay`` only asks about paths inside the project.
final class PathExistence: Sendable {
    static let shared = PathExistence()
    private let known = Mutex<[String: Bool]>([:])
    /// The most answers kept; past it they are forgotten together, so a long session cannot grow it without end.
    private static let limit = 4_096

    func exists(_ path: String) -> Bool {
        if let answer = known.withLock({ $0[path] }) { return answer }
        let answer = FileManager.default.fileExists(atPath: path)
        known.withLock { known in
            if known.count >= Self.limit { known.removeAll(keepingCapacity: true) }
            known[path] = answer
        }
        return answer
    }
}
