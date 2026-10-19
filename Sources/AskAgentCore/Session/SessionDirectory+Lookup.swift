internal import Foundation

/// Finding a recorded session: the one written last, or one by name.
extension SessionDirectory {
    /// The project's sessions, the one written last first. Damaged copies and temporary files are not sessions.
    public func sessions() -> [SessionListing] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { $0.hasSuffix(".jsonl") }
            .compactMap { name -> SessionListing? in
                let file = path + "/" + name
                guard let modified = (try? manager.attributesOfItem(atPath: file))?[.modificationDate] as? Date
                else { return nil }
                return SessionListing(path: file, modified: modified)
            }
            .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.name > $1.name }
    }

    /// The session `query` names: a path as given, else the session whose name is `query`, with or without
    /// `.jsonl`, or the only one whose name starts with it.
    /// - Parameter query: a path, a session's name, or the start of one.
    /// - Returns: the session's path.
    /// - Throws: ``SessionLookupError`` when no single session matches.
    public func resolve(_ query: String) throws(SessionLookupError) -> String {
        if query.contains("/") { return query }
        let listed = sessions()
        if let exact = listed.first(where: { $0.name == query || $0.name == query + ".jsonl" }) { return exact.path }
        let matches = listed.filter { $0.name.hasPrefix(query) }
        guard let only = matches.first else { throw .notFound(query) }
        guard matches.count == 1 else { throw .ambiguous(query, candidates: matches.map(\.name)) }
        return only.path
    }
}
