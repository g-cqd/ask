/// Reads what a zip archive's end and central directory say, so a few files can be taken from a large archive by HTTP ranges without
/// downloading it. Only what VS Code's builds use: no zip64, no encryption, stored or deflated files.
enum ZipDirectory {
    /// Where the central directory is, from the archive's last bytes; nil without an end record, or for a zip64 archive.
    static func locate(tail: [UInt8]) -> (offset: Int, size: Int)? {
        for start in stride(from: tail.count - 22, through: 0, by: -1)
        where tail.matches([0x50, 0x4B, 0x05, 0x06], at: start) {
            guard let size = tail.u32(start + 12), let offset = tail.u32(start + 16), size != 0xFFFF_FFFF,
                offset != 0xFFFF_FFFF
            else { return nil }
            return (offset, size)
        }
        return nil
    }

    /// The entries of `directory` whose names are in `wanted`; nil when the directory is malformed.
    static func entries(_ directory: [UInt8], named wanted: Set<String>) -> [String: ZipEntry]? {
        var found: [String: ZipEntry] = [:]
        var at = 0
        while at < directory.count {
            guard directory.matches([0x50, 0x4B, 0x01, 0x02], at: at), let method = directory.u16(at + 10),
                let compressed = directory.u32(at + 20), let size = directory.u32(at + 24),
                let nameLength = directory.u16(at + 28), let extra = directory.u16(at + 30),
                let comment = directory.u16(at + 32),
                let offset = directory.u32(at + 42), at + 46 + nameLength <= directory.count
            else { return nil }
            let name = String(decoding: directory[(at + 46) ..< (at + 46 + nameLength)], as: UTF8.self)
            if wanted.contains(name) {
                found[name] = ZipEntry(
                    name: name,
                    method: method,
                    compressedSize: compressed,
                    size: size,
                    offset: offset
                )
            }
            at += 46 + nameLength + extra + comment
        }
        return found
    }

    /// How many bytes from an entry's offset hold its local header and data, allowing for a local extra field of up to 1 KiB.
    static func span(of entry: ZipEntry) -> Int { 30 + entry.name.utf8.count + 1_024 + entry.compressedSize }

    /// The file's bytes, from what was read at its offset; nil when that is not its local header or is cut short.
    static func payload(_ local: [UInt8], of entry: ZipEntry) -> [UInt8]? {
        guard local.matches([0x50, 0x4B, 0x03, 0x04], at: 0), let nameLength = local.u16(26), let extra = local.u16(28)
        else {
            return nil
        }
        let start = 30 + nameLength + extra
        guard start + entry.compressedSize <= local.count else { return nil }
        let data = Array(local[start ..< (start + entry.compressedSize)])
        switch entry.method {
            case 0: return data.count == entry.size ? data : nil
            case 8: return Inflate.raw(data, size: entry.size)
            default: return nil
        }
    }
}

extension [UInt8] {
    fileprivate func matches(_ bytes: [UInt8], at start: Int) -> Bool {
        start >= 0 && start + bytes.count <= count && self[start ..< (start + bytes.count)].elementsEqual(bytes)
    }

    fileprivate func u16(_ at: Int) -> Int? {
        guard at >= 0, at + 2 <= count else { return nil }
        return Int(self[at]) | Int(self[at + 1]) << 8
    }

    fileprivate func u32(_ at: Int) -> Int? {
        guard let low = u16(at), let high = u16(at + 2) else { return nil }
        return low | high << 16
    }
}
