public import AskAgentCore
internal import Foundation
internal import Subprocess
internal import System

/// Lists a project's files for the `@` picker (roadmap 0048, ADR-0069).
///
/// In a git repository the list is git's own, tracked files and untracked files that are not ignored, so `.gitignore` means exactly what
/// it means to the user. Anywhere else, or when git cannot answer in time, a bounded walk lists what is there, skipping the directories
/// that are build output or tooling everywhere. Either way every path goes through the sandbox's read policy: a file ask may not read is
/// counted, not named.
public enum ProjectLister {
    /// The most files a listing keeps.
    public static let defaultLimit = 20_000

    /// How long git gets before the walk is used instead.
    public static let gitTimeout = Duration.seconds(5)

    /// Directories a walk never enters: version control, and what builds and tools write.
    static let skipped: Set<String> = [
        // @dl:accept -- a table of names: the list is the data, and it matches other string tables only as literals
        ".git", ".hg", ".svn", ".build", ".swiftpm", "node_modules", "DerivedData", "Pods", "__pycache__", ".venv",
        "venv", "target",
        "build", "dist", ".gradle", ".idea", ".cache"
    ]

    /// The files under `directory`.
    /// - Parameters:
    ///   - directory: the project directory, the working directory the picker's paths are relative to.
    ///   - policy: what ask may read.
    ///   - limit: the most paths to keep.
    ///   - gitWait: how long git may take before the directory is walked instead.
    /// - Returns: the listing. Never throws: a directory that cannot be read lists nothing.
    public static func list(
        in directory: String, policy: SandboxPolicy, limit: Int = defaultLimit, gitWait: Duration = gitTimeout
    ) async -> ProjectListing {
        let candidates: [String]
        if let listed = await gitFiles(in: directory, waitingAtMost: gitWait) {
            candidates = listed
        } else {
            candidates = await onThread { walk(directory, limit: limit * 2) }
        }
        return await onThread { readable(candidates, in: directory, policy: policy, limit: limit) }
    }

    /// Runs `work` on a thread of its own: a walk and a pass of path canonicalisation block, and the cooperative pool is not for blocking.
    private static func onThread<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.name = "ask.project-files"
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    /// git's list of the files in `directory`, or nil when it is not a git repository, git is missing, or it did not answer in time.
    static func gitFiles(in directory: String, waitingAtMost wait: Duration = gitTimeout) async -> [String]? {
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await runGit(in: directory) }
            group.addTask {
                // A cancelled sleep is git finishing first, and its answer is the one that counts.
                try? await ContinuousClock().sleep(for: wait)
                return nil
            }
            let first = await group.next() ?? nil
            // Cancelling stops a git that is still running: the group's other child is the one that finished.
            group.cancelAll()
            return first
        }
    }

    private static func runGit(in directory: String) async -> [String]? {
        do {
            let result = try await Subprocess.run(
                .path(FilePath("/usr/bin/git")),
                arguments: ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                workingDirectory: FilePath(directory), platformOptions: JobProcess.groupOptions(graceSeconds: 1),
                input: .none,
                output: .data(limit: 32 << 20),
                error: .discarded)
            guard result.terminationStatus == .exited(0) else { return nil }
            return result.standardOutput.split(separator: 0).compactMap { String(bytes: $0, encoding: .utf8) }
        } catch {
            return nil
        }
    }

    /// A bounded walk of `directory`: regular files only, never into a skipped directory or through a symbolic link to a directory.
    static func walk(_ directory: String, limit: Int) -> [String] {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [])
        else {
            return []
        }
        var found: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        while let url = walker.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skipped.contains(url.lastPathComponent) { walker.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, url.lastPathComponent != ".DS_Store" else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { found.append(String(path.dropFirst(prefix.count))) }
            if found.count >= limit { break }
        }
        return found
    }

    /// `candidates` that exist as files, ask may read, sorted, and no more than `limit`.
    static func readable(_ candidates: [String], in directory: String, policy: SandboxPolicy, limit: Int)
        -> ProjectListing
    {
        var listing = ProjectListing()
        var seen = Set<String>()
        for path in candidates.sorted() where seen.insert(path).inserted {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory + "/" + path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { continue }
            guard policy.isUnrestricted || policy.authorize(.read, path: path, relativeTo: directory).isAllowed else {
                listing.hidden += 1
                continue
            }
            if listing.paths.count == limit {
                listing.truncated = true
                break
            }
            listing.paths.append(path)
        }
        return listing
    }
}
