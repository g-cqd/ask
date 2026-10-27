internal import AemiJSON
internal import Darwin
internal import Foundation

extension ConfigEditor {
    /// Commits one setting to the file it came from, taking the *display text* a row shows. The file is
    /// read again first, so a change made elsewhere between opening the editor and pressing Enter is
    /// not overwritten wholesale, and the text is re-parsed against the file's actual current value.
    public func commit(_ text: String, at path: [String]) throws(ConfigEditor.Error) {
        let latest = try reopen()
        let typed: Value
        do {
            typed = try latest.value(text, at: path)
        } catch {
            throw .configuration(error)
        }
        return try latest.commitTyped(typed, at: path)
    }

    /// Commits a typed value by re-reading first, so a change made elsewhere is not overwritten wholesale.
    public func commit(path: [String], value: Value) throws(ConfigEditor.Error) {
        try reopen().commitTyped(value, at: path)
    }

    /// The file as it is now, so a commit never overwrites a change made since the editor opened.
    private func reopen() throws(ConfigEditor.Error) -> ConfigEditor {
        do {
            return try ConfigEditor(path: path, isProject: isProject)
        } catch {
            throw .cannotWrite(path: self.path, reason: String(describing: error))
        }
    }

    /// Commits an already-typed value, shared by both entry points.
    func commitTyped(_ value: Value, at setting: [String]) throws(ConfigEditor.Error) {
        let candidate = Self.applying(value, at: setting, to: root)
        if candidate == root { return }
        let stripped = Self.stripped(candidate, path: [])
        let strippedBytes: [UInt8]
        do {
            strippedBytes = try Self.encoding(
                of: stripped.value, pretty: false, indent: "", separator: .javaScript,
                trailingNewline: false)
        } catch {
            throw .cannotWrite(path: self.path, reason: String(describing: error))
        }
        do {
            _ = try ConfigurationFile.parse(strippedBytes, path: self.path, isProject: isProject)
        } catch {
            throw .configuration(error)
        }
        let bytes: [UInt8]
        do {
            bytes = try Self.encoding(
                of: candidate, pretty: pretty, indent: indent,
                separator: foundationSeparator ? .foundation : .javaScript, trailingNewline: trailingNewline)
        } catch {
            throw .cannotWrite(path: self.path, reason: String(describing: error))
        }
        try Self.writeAtomically(bytes, to: self.path, preserving: mode)
    }

    /// The file's permission bits when it exists, so a save keeps a file the person chose to share or keep private.
    private var mode: mode_t? {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_mode & 0o777 : nil
    }
    /// The write itself: one fresh file, flushed and renamed over the target, never a partial one in place.
    private static func run(_ bytes: [UInt8], to path: String, mode: mode_t) throws(ConfigEditor.Error) {
        let temporary =
            (path as NSString).deletingLastPathComponent
            + "/.ask-config-\(UUID().uuidString).tmp"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode)
        guard descriptor >= 0 else {
            throw ConfigEditor.Error.cannotWrite(path: path, reason: String(cString: strerror(errno)))
        }
        do {
            try write(bytes, to: descriptor, path: path)
            guard fchmod(descriptor, mode) == 0, fsync(descriptor) == 0 else {
                throw ConfigEditor.Error.cannotWrite(path: path, reason: String(cString: strerror(errno)))
            }
            guard Darwin.close(descriptor) == 0 else {
                throw ConfigEditor.Error.cannotWrite(path: path, reason: String(cString: strerror(errno)))
            }
            guard rename(temporary, path) == 0 else {
                throw ConfigEditor.Error.cannotWrite(path: path, reason: String(cString: strerror(errno)))
            }
        } catch let error as ConfigEditor.Error {
            close(descriptor)
            try? FileManager.default.removeItem(atPath: temporary)
            throw error
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(atPath: temporary)
            throw ConfigEditor.Error.cannotWrite(path: path, reason: String(describing: error))
        }
    }

    private static func write(_ bytes: [UInt8], to descriptor: Int32, path: String) throws(ConfigEditor.Error) {
        var written = 0
        while written < bytes.count {
            let count = bytes.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress! + written, bytes.count - written)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw ConfigEditor.Error.cannotWrite(path: path, reason: String(cString: strerror(errno)))
            }
            written += count
        }
    }
}

extension ConfigEditor {
    /// Writes `bytes` to a fresh file beside `path`, flushes it, and renames it over the target.
    static func writeAtomically(_ bytes: [UInt8], to path: String, preserving mode: mode_t?) throws(ConfigEditor.Error)
    {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw ConfigEditor.Error.cannotWrite(path: path, reason: String(describing: error))
        }
        try Self.run(bytes, to: path, mode: mode ?? 0o600)
        let directoryDescriptor = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if directoryDescriptor >= 0 {
            _ = fsync(directoryDescriptor)
            close(directoryDescriptor)
        }
    }
}
