internal import AskAgentCore
internal import Foundation
internal import System

/// Which session a run writes to: a new one, the one written last (`--continue`), or a named one (`--resume`).
enum SessionChoice {
    case new
    case latest
    case named(String)

    /// The chosen session, opened and locked, or nil for a new one, which is created when first needed.
    /// `--continue` with no session here starts a new one, and says so through `note`.
    /// - Parameters:
    ///   - directory: the project's sessions.
    ///   - note: told when `--continue` found nothing to continue.
    /// - Returns: the open session, or nil.
    func open(in directory: SessionDirectory, note: (String) -> Void) -> SessionRecorder? {
        let path: String
        switch self {
            case .new: return nil
            case .latest:
                guard let latest = directory.sessions().first else {
                    note("No earlier session here; starting a new one.")
                    return nil
                }
                path = latest.path
            case .named(let query):
                do { path = try directory.resolve(query) } catch { fail("ask: \(error)", code: 66) }
        }
        do {
            return SessionRecorder(try SessionFile.open(at: FilePath(path)))
        } catch .inUse {
            fail("ask: this session is open in another ask: \(path)", code: 75)
        } catch {
            fail("ask: cannot open \(path): \(error)", code: 66)
        }
    }
}
