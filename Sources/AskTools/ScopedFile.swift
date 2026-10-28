internal import AskAI
internal import AskAgentCore
internal import Darwin
internal import Foundation

/// File access that a swapped directory or link cannot redirect between the sandbox's check and the use (roadmap 0058, ADR-0085).
///
/// `FileTools.authorized` resolves a path and asks the policy about the result, and the tool then used that path by name. A job the
/// sandbox lets write in the workspace can rename a directory away and put a link to a protected one in its place after the check
/// and before the use: measured, 2 of 6,000 writes landed in ask's configuration directory. The cure is not a better check but not
/// looking the name up twice: open the object, ask the kernel where it really is (`F_GETPATH`), authorize that, and use only the
/// descriptor. Writing works relative to a directory descriptor verified the same way, one component at a time, never following a
/// link. Used when the policy restricts anything; with nothing restricted there is nothing to redirect around.
enum ScopedFile {
    /// The whole contents of the file at `url`, read through one descriptor whose real location the policy has agreed to.
    /// - Parameters:
    ///   - url: the file, as resolved by the first check.
    ///   - path: the name to show in a failure.
    ///   - limit: the most bytes a file may have.
    ///   - context: where the sandbox is.
    /// - Returns: the bytes.
    /// - Throws: a ``ToolFailure`` for a missing, unreadable, oversized or protected file.
    static func read(_ url: URL, shownAs path: String, limit: Int, in context: ToolContext) throws(ToolFailure)
        -> [UInt8]
    {
        let (descriptor, size) = try openRegular(url, shownAs: path, limit: limit, in: context)
        defer { close(descriptor) }
        var bytes = [UInt8](repeating: 0, count: size)
        var filled = 0
        while filled < size {
            let count = bytes.withUnsafeMutableBytes {
                unsafe Darwin.read(descriptor, $0.baseAddress! + filled, size - filled)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }  // The file shrank while being read: what was there is what there is.
            filled += count
        }
        bytes.removeLast(size - filled)
        return bytes
    }

    /// A descriptor on the file, opened without following a link, whose real location the policy allows reading. The caller closes it.
    /// - Parameters:
    ///   - url: the file, as resolved by the first check.
    ///   - path: the name to show in a failure.
    ///   - context: where the sandbox is.
    /// - Returns: the open descriptor.
    /// - Throws: a ``ToolFailure`` for a missing, unreadable or protected file.
    static func openVerified(_ url: URL, shownAs path: String, in context: ToolContext) throws(ToolFailure) -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw ToolFailure(errno == ENOENT ? "No file at \(path)." : "Cannot read \(path).")
        }
        do { try verify(descriptor, for: .read, appending: nil, shownAs: path, in: context) } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    /// A verified descriptor on a regular file of at most `limit` bytes, and its size. The caller closes the descriptor.
    /// - Throws: a ``ToolFailure`` for a missing, unreadable, protected, irregular or oversized file.
    static func openRegular(_ url: URL, shownAs path: String, limit: Int, in context: ToolContext)
        throws(ToolFailure) -> (descriptor: Int32, size: Int)
    {
        let descriptor = try openVerified(url, shownAs: path, in: context)
        var failure: ToolFailure?
        do {
            let size = try regularSize(of: descriptor, shownAs: path)
            if size <= limit { return (descriptor, size) }
            failure = ToolFailure("\(path) is \(size) bytes, over the \(limit)-byte limit.")
        } catch {
            failure = error
        }
        close(descriptor)
        throw failure ?? ToolFailure.notPermitted(path)
    }

    /// The size of the regular file `descriptor` is open on.
    /// - Throws: a ``ToolFailure`` when it is not a regular file.
    static func regularSize(of descriptor: Int32, shownAs path: String) throws(ToolFailure) -> Int {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ToolFailure("Cannot read \(path).")
        }
        return Int(info.st_size)
    }

    /// The first `count` bytes of the file, read through a verified descriptor. Empty when it cannot be read or is not allowed.
    static func header(of url: URL, count: Int, in context: ToolContext) -> [UInt8] {
        guard let descriptor = try? openVerified(url, shownAs: url.lastPathComponent, in: context) else { return [] }
        defer { close(descriptor) }
        return prefix(of: descriptor, count: count)
    }

    /// Up to `count` bytes from the start of what `descriptor` is open on.
    static func prefix(of descriptor: Int32, count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let filled = bytes.withUnsafeMutableBytes { unsafe Darwin.read(descriptor, $0.baseAddress!, count) }
        return filled > 0 ? Array(bytes.prefix(filled)) : []
    }

    /// Copies the verified file into a private temporary directory, under the same extension, for a framework that can only open a
    /// path; it works on the copy, which nothing can redirect, and the copy is removed afterwards.
    /// - Parameters:
    ///   - url: the file, as resolved by the first check.
    ///   - path: the name to show in a failure.
    ///   - limit: the most bytes the file may have.
    ///   - context: where the sandbox is.
    ///   - body: what to do with the copy.
    /// - Returns: what `body` returns.
    /// - Throws: a ``ToolFailure`` for a missing, protected, oversized or uncopyable file, or what `body` throws.
    static func withCopy<Result>(
        of url: URL, shownAs path: String, limit: Int, in context: ToolContext,
        _ body: (URL) async throws(ToolFailure) -> Result
    ) async throws(ToolFailure) -> Result {
        let (source, _) = try openRegular(url, shownAs: path, limit: limit, in: context)
        defer { close(source) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-read-\(UUID().uuidString)")
        guard
            (try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil
        else { throw ToolFailure("Cannot read \(path).") }
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: "file." + url.pathExtension)
        let target = open(copy.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard target >= 0 else { throw ToolFailure("Cannot read \(path).") }
        defer { close(target) }
        guard fcopyfile(source, target, nil, copyfile_flags_t(COPYFILE_DATA)) == 0 else {
            throw ToolFailure("Cannot read \(path).")
        }
        return try await body(copy)
    }

    /// Replaces or creates the file at `url` with `bytes`, atomically, creating its directories, without ever naming a directory twice.
    /// - Parameters:
    ///   - bytes: what the file is to hold.
    ///   - url: the file, as resolved by the first check.
    ///   - path: the name to show in a failure.
    ///   - context: where the sandbox is.
    ///   - flush: how a descriptor is made durable; only tests give one, to see when and to make it fail.
    /// - Throws: a ``ToolFailure`` if the write is protected, or cannot be done.
    static func write(
        _ bytes: [UInt8], to url: URL, shownAs path: String, in context: ToolContext,
        flush: (Int32) -> Int32 = FileFlush.barrier
    ) throws(ToolFailure) {
        let name = url.lastPathComponent
        var missing: [String] = []
        var base = url.deletingLastPathComponent().path
        var directory = open(base, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        // The deepest directory that exists; what lies below it is made one component at a time.
        while directory < 0, errno == ENOENT, base != "/" {
            missing.insert((base as NSString).lastPathComponent, at: 0)
            base = (base as NSString).deletingLastPathComponent
            directory = open(base, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard directory >= 0 else { throw ToolFailure("Cannot write \(path): \(String(cString: strerror(errno))).") }
        defer { close(directory) }
        for component in missing {
            try verify(directory, for: .write, appending: component, shownAs: path, in: context)
            if mkdirat(directory, component, 0o777) != 0, errno != EEXIST {
                throw ToolFailure("Cannot write \(path): \(String(cString: strerror(errno))).")
            }
            // A link put there since is not followed: it fails, and nothing is written.
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ToolFailure("Cannot write \(path): a directory on its way was replaced.") }
            close(directory)
            directory = next
        }
        try verify(directory, for: .write, appending: name, shownAs: path, in: context)
        try replace(name, in: directory, with: bytes, shownAs: path, flush: flush)
    }

    /// Writes `bytes` beside `name` under a name of its own, then renames it over `name`, keeping the permissions of what it replaces.
    private static func replace(
        _ name: String, in directory: Int32, with bytes: [UInt8], shownAs path: String, flush: (Int32) -> Int32
    ) throws(ToolFailure) {
        let temporary = ".ask-write-\(UUID().uuidString)"
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o666)
        guard file >= 0 else { throw ToolFailure("Cannot write \(path): \(String(cString: strerror(errno))).") }
        defer { close(file) }
        var written = 0
        while written < bytes.count {
            let count = bytes.withUnsafeBytes {
                unsafe Darwin.write(file, $0.baseAddress! + written, bytes.count - written)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                unlinkat(directory, temporary, 0)
                throw ToolFailure("Cannot write \(path): \(String(cString: strerror(errno))).")
            }
            written += count
        }
        var existing = stat()
        if fstatat(directory, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 { fchmod(file, existing.st_mode & 0o7777) }
        // Before the rename, so the new name never reaches the disk ahead of the bytes it names.
        guard flush(file) == 0 else {
            let failure = String(cString: strerror(errno))
            unlinkat(directory, temporary, 0)
            throw ToolFailure("Cannot write \(path): its bytes could not be flushed (\(failure)).")
        }
        guard renameat(directory, temporary, directory, name) == 0 else {
            let failure = String(cString: strerror(errno))
            unlinkat(directory, temporary, 0)
            throw ToolFailure("Cannot write \(path): \(failure).")
        }
        // After it, so the new name is on the disk before the model is told the file is written. The file is in place and stays.
        guard flush(directory) == 0 else {
            throw ToolFailure(
                "Cannot write \(path): the directory could not be flushed (\(String(cString: strerror(errno)))).")
        }
    }

    /// Refuses unless the policy allows `capability` at the real location of `descriptor`, with `name` below it when given.
    static func verify(
        _ descriptor: Int32, for capability: SandboxCapability, appending name: String?, shownAs path: String,
        in context: ToolContext
    ) throws(ToolFailure) {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
            throw ToolFailure.notPermitted(path)
        }
        let real = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let target = name.map { real + "/" + $0 } ?? real
        if case .denied = context.sandbox.authorize(capability, path: target, relativeTo: context.workingDirectory) {
            throw ToolFailure.notPermitted(path)
        }
    }
}
