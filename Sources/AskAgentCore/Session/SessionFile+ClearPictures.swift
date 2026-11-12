internal import AskAI
internal import Darwin
internal import Foundation
internal import System

/// After `/encrypt on` (roadmap 0182): the pictures this session stored unencrypted are sealed again by the rewrite, under the image key;
/// their clear copies are removed, unless another session of the project may still name them.
extension SessionFile {
    /// The names, in the clear store, of the pictures this session holds.
    var clearPictureNames: Set<String> {
        Set(
            tree.entries.flatMap { entry -> [String] in
                switch entry.payload {
                    case .toolResult(_, _, _, let images, _), .user(_, let images):
                        return images.map { SessionImageStore.hash(of: $0.data) }
                    default: return []
                }
            }
        )
    }

    /// Removes the clear copies of `names` that no other file beside this session names. Plain and compressed files are searched (a
    /// damaged or versioned copy too); an encrypted one names pictures by HMAC, never by hash, so it is passed over; a file that cannot be
    /// read keeps every copy, since it might name any of them.
    func removeClearPictures(named names: Set<String>) {
        let directory = path.removingLastComponent().string
        let store = SessionImageStore(besideSessionAt: path.string)
        var unnamed = names
        let others = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        for other in others where other != path.lastComponent?.string && other != "images" && !other.hasSuffix(".tmp") {
            guard !unnamed.isEmpty else { break }
            guard let text = Self.searchable(directory + "/" + other) else {
                if Self.isEncryptedSession(directory + "/" + other) { continue }
                return
            }
            unnamed = unnamed.filter { !text.contains($0) }
        }
        for name in unnamed { unlink(store.directory + "/" + name) }
    }

    /// The text of a plain or compressed file, nil for one that is encrypted or cannot be read.
    private static func searchable(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.starts(with: FrameFormat.magic) else { return String(decoding: bytes, as: UTF8.self) }
        guard let header = try? FramedHeader.parse(bytes), !header.encrypted,
            let read = try? FramedReader.read(bytes, key: nil)
        else { return nil }
        return String(decoding: Array(read.records.joined(separator: [0x0A])), as: UTF8.self)
    }

    private static func isEncryptedSession(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path), let header = try? FramedHeader.parse([UInt8](data))
        else {
            return false
        }
        return header.encrypted
    }
}
