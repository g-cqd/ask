internal import Darwin
internal import Foundation

/// Stages a `/reload` candidate into a private, owner-only (`0500`) file inside `<config>/reload` before signature and self-check run
/// on it, and executes that private copy so no process can swap the binary on disk between the checks and `execve` (security audit
/// 2026-11-22, HIGH-10).
enum ReloadStaging {
    struct Failure: Error, Equatable, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    static let prefix = "ask-staged-"

    /// Copies `candidatePath` (`O_NOFOLLOW`, regular file only) into `<configDirectory>/reload/ask-staged-<uuid>` with `0500`
    /// permissions, preserving extended attributes (code signatures) and modification time, and returns the staged path.
    static func stage(_ candidatePath: String, configDirectory: String) throws(Failure) -> String {
        let folder = configDirectory + "/reload"
        do {
            try FileManager.default.createDirectory(
                atPath: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw Failure(reason: "could not create private reload directory")
        }
        _ = chmod(folder, 0o700)

        let src = open(candidatePath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard src >= 0 else {
            throw Failure(reason: "the executable could not be opened safely (symlinks are refused)")
        }
        defer { close(src) }

        var info = stat()
        guard fstat(src, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0 else {
            throw Failure(reason: "the candidate is not a non-empty regular file")
        }

        let stagedPath = folder + "/" + prefix + UUID().uuidString
        let dst = open(stagedPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o500)
        guard dst >= 0 else {
            throw Failure(reason: "could not create private staged executable")
        }
        let copied = fcopyfile(src, dst, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_XATTR)) == 0
        var times = [info.st_atimespec, info.st_mtimespec]
        _ = futimens(dst, &times)
        let modeOK = fchmod(dst, 0o500) == 0
        let synced = fsync(dst) == 0
        close(dst)
        guard copied, modeOK, synced else {
            unlink(stagedPath)
            throw Failure(reason: "could not copy candidate into private staging")
        }
        return stagedPath
    }

    /// Removes staged binaries from earlier reloads in `<configDirectory>/reload`, keeping `currentExecutablePath` (the running image,
    /// which `LaunchSignature` inspects on disk).
    static func sweepPrevious(configDirectory: String, keeping currentExecutablePath: String?) {
        let folder = configDirectory + "/reload"
        let keptCanonical = currentExecutablePath.flatMap { path -> String? in
            guard let ptr = realpath(path, nil) else { return path }
            defer { free(ptr) }
            return String(cString: ptr)
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            let candidate = folder + "/" + entry
            let resolved: String = {
                guard let ptr = realpath(candidate, nil) else { return candidate }
                defer { free(ptr) }
                return String(cString: ptr)
            }()
            if resolved != keptCanonical {
                unlink(candidate)
            }
        }
    }
}
