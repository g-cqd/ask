internal import AemiJSON
internal import Darwin
internal import Foundation

/// The sessions this computer shares: each live ask's description beside its viewer socket.
enum SharedSessions {
    /// The descriptions in `folder` whose process is alive and whose socket is there, in id order; a stale pair is removed.
    static func read(_ folder: String) -> [ViewerEndpoint.Description] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted()
            .compactMap { name -> ViewerEndpoint.Description? in
                let path = folder + "/" + name
                guard let data = FileManager.default.contents(atPath: path),
                    let description = try? AemiJSON.JSONDecoder()
                        .decode(ViewerEndpoint.Description.self, from: Array(data)),
                    let pid = pid_t(description.id)
                else { return nil }
                let socket = folder + "/\(description.id).sock"
                // A process gone without stopping its endpoint (a crash, a signal) leaves its pair behind.
                guard kill(pid, 0) == 0 || errno == EPERM, FileManager.default.fileExists(atPath: socket) else {
                    unlink(path)
                    unlink(socket)
                    return nil
                }
                return description
            }
    }
}
