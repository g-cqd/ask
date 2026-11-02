/// One file in a zip archive's central directory: where its local header starts and how it is stored.
struct ZipEntry: Sendable, Equatable {
    let name: String
    /// 0 stored, 8 deflated.
    let method: Int
    let compressedSize: Int
    let size: Int
    /// The offset of its local header in the archive.
    let offset: Int
}
