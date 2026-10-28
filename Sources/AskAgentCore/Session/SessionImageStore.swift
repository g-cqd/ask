internal import AskAI
internal import CryptoKit
internal import Foundation

/// Where a session keeps the pictures its tool results returned: one file per distinct picture, named for the SHA-256 of its bytes, in
/// an `images` directory beside the session files (roadmap 0084).
///
/// A picture inline in the log is base64, a third larger than the picture and past the log's line limit when it is large, which
/// would cost the whole record on resume. In the store it is written once however often it is read, by every session of the project,
/// and a record carries only its hash. Files are private to the user (0600, in a 0700 directory). A file that is missing or whose
/// bytes no longer match its name is not trusted: the record degrades to a line of text (see ``WirePayload``).
struct SessionImageStore: Sendable, Equatable {
    /// The directory the pictures are in.
    let directory: String

    /// Key for the encoder's and the decoder's `userInfo`.
    static let userInfoKey = CodingUserInfoKey(rawValue: "ask.session.imageStore")!

    /// The store beside the session file at `sessionPath`.
    init(besideSessionAt sessionPath: String) {
        directory = (sessionPath as NSString).deletingLastPathComponent + "/images"
    }

    /// The hash that names `bytes`: 64 lowercase hexadecimal digits.
    static func hash(of bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes `bytes` if the store does not hold them yet.
    /// - Returns: their hash.
    /// - Throws: the error of the file system when they cannot be written; a record then keeps them inline.
    func put(_ bytes: [UInt8]) throws -> String {
        let name = Self.hash(of: bytes)
        let path = directory + "/" + name
        let manager = FileManager.default
        if manager.fileExists(atPath: path) { return name }
        try manager.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = path + ".\(UInt32.random(in: 0 ... .max)).tmp"
        guard manager.createFile(atPath: temporary, contents: Data(bytes), attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try manager.moveItem(atPath: temporary, toPath: path)
        } catch {
            try? manager.removeItem(atPath: temporary)
            if !manager.fileExists(atPath: path) { throw error }
        }
        return name
    }

    /// The bytes named `hash`, or nil when there is no such file, it cannot be read, or its bytes are not what its name says.
    func get(_ hash: String) -> [UInt8]? {
        guard hash.utf8.count == 64, hash.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }),
            let data = FileManager.default.contents(atPath: directory + "/" + hash)
        else { return nil }
        let bytes = [UInt8](data)
        return Self.hash(of: bytes) == hash ? bytes : nil
    }
}
