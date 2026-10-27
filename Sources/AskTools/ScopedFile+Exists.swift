internal import AskAgentCore
internal import Darwin
internal import Foundation

extension ScopedFile {
    /// Metadata-only readiness check. Verify the opened object's actual location, never trust a swapped path.
    static func exists(_ url: URL, shownAs path: String, in context: ToolContext) throws(ToolFailure) -> Bool {
        let descriptor = open(url.path, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return false }
            throw ToolFailure.notPermitted(path)
        }
        defer { close(descriptor) }
        try verify(descriptor, for: .read, appending: nil, shownAs: path, in: context)
        return true
    }
}
