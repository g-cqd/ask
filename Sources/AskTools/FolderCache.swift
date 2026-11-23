internal import AskAgentCore
internal import Darwin

/// The canonical form of a project's files for the `@` picker, each folder resolved once (security and performance audit 2026-11-22,
/// PERF-04): a plain file is its folder's canonical form and its name, since only a link can lead elsewhere; a link is resolved whole,
/// as ``CanonicalPath`` resolves any path. 10,000 files took 194 ms resolved one by one.
struct FolderCache {
    let directory: String
    private var resolved: [String: String] = [:]
    private var unresolvable: Set<String> = []

    init(directory: String) { self.directory = directory }

    /// For `path`, relative to the project: nil when it is not a file (a folder, a link to one, or gone); otherwise its canonical form,
    /// itself nil when it cannot be resolved.
    mutating func canonicalFile(_ path: String) -> String?? {
        var info = stat()
        guard lstat(directory + "/" + path, &info) == 0 else { return nil }
        switch info.st_mode & S_IFMT {
            case S_IFREG:
                let slash = path.lastIndex(of: "/")
                let parent = slash.map { String(path[..<$0]) } ?? ""
                let name = slash.map { String(path[path.index(after: $0)...]) } ?? path
                guard let folder = folder(parent) else { return .some(nil) }
                return .some((folder == "/" ? "" : folder) + "/" + name)
            case S_IFLNK:
                // Where it leads decides: a link to a folder is no file, and one that leads nowhere is gone.
                var target = stat()
                guard stat(directory + "/" + path, &target) == 0, target.st_mode & S_IFMT == S_IFREG else { return nil }
                return .some(CanonicalPath.of(path, relativeTo: directory))
            default: return nil
        }
    }

    /// The canonical form of the folder `relative` names, the project's own for "", resolved once.
    private mutating func folder(_ relative: String) -> String? {
        if let known = resolved[relative] { return known }
        if unresolvable.contains(relative) { return nil }
        guard
            let canonical = CanonicalPath.of(relative.isEmpty ? directory : directory + "/" + relative, relativeTo: "/")
        else {
            unresolvable.insert(relative)
            return nil
        }
        resolved[relative] = canonical
        return canonical
    }
}
