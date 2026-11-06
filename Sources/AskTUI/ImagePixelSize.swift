/// A picture's width and height in pixels, read from the start of its file (roadmap 0208): PNG, GIF, JPEG and WebP, the kinds a
/// tool returns (roadmap 0084). Nothing is decoded; a header that is cut short, or a kind it does not know, says nothing.
enum ImagePixelSize {
    /// The size, or nil.
    static func read(_ data: [UInt8]) -> (width: Int, height: Int)? {
        if starts(data, with: [0x89, 0x50, 0x4E, 0x47]) { return png(data) }
        if starts(data, with: Array("GIF8".utf8)) { return gif(data) }
        if starts(data, with: [0xFF, 0xD8]) { return jpeg(data) }
        if starts(data, with: Array("RIFF".utf8)), data.count >= 12, Array(data[8 ..< 12]) == Array("WEBP".utf8) {
            return webp(data)
        }
        return nil
    }

    private static func starts(_ data: [UInt8], with prefix: [UInt8]) -> Bool {
        data.count >= prefix.count && Array(data[..<prefix.count]) == prefix
    }

    /// The integer in `count` bytes from `at`, in the byte order given; nil past the end.
    private static func number(_ data: [UInt8], _ at: Int, _ count: Int, bigEndian: Bool) -> Int? {
        guard at >= 0, at + count <= data.count else { return nil }
        let bytes = data[at ..< at + count]
        return (bigEndian ? Array(bytes) : bytes.reversed()).reduce(0) { $0 << 8 | Int($1) }
    }

    private static func big(_ data: [UInt8], _ at: Int, _ count: Int) -> Int? {
        number(data, at, count, bigEndian: true)
    }

    private static func little(_ data: [UInt8], _ at: Int, _ count: Int) -> Int? {
        number(data, at, count, bigEndian: false)
    }

    /// The IHDR chunk, first after the signature: width and height, four bytes each.
    private static func png(_ data: [UInt8]) -> (width: Int, height: Int)? {
        guard let width = big(data, 16, 4), let height = big(data, 20, 4) else { return nil }
        return (width, height)
    }

    /// The logical screen: width and height, two bytes each, after `GIF87a` or `GIF89a`.
    private static func gif(_ data: [UInt8]) -> (width: Int, height: Int)? {
        guard let width = little(data, 6, 2), let height = little(data, 8, 2) else { return nil }
        return (width, height)
    }

    /// The first start-of-frame marker (`FFC0` to `FFCF`, not `C4`, `C8` or `CC`), walking the segments by their lengths.
    private static func jpeg(_ data: [UInt8]) -> (width: Int, height: Int)? {
        var at = 2
        while at + 4 <= data.count, data[at] == 0xFF {
            let marker = data[at + 1]
            guard let length = big(data, at + 2, 2), length >= 2 else { return nil }
            if (0xC0 ... 0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                guard let height = big(data, at + 5, 2), let width = big(data, at + 7, 2) else { return nil }
                return (width, height)
            }
            at += 2 + length
        }
        return nil
    }

    /// The first chunk after `WEBP`: `VP8X` holds the canvas, `VP8 ` a lossy frame, `VP8L` a lossless one.
    private static func webp(_ data: [UInt8]) -> (width: Int, height: Int)? {
        guard data.count >= 16 else { return nil }
        switch String(decoding: data[12 ..< 16], as: UTF8.self) {
            case "VP8X":
                guard let width = little(data, 24, 3), let height = little(data, 27, 3) else { return nil }
                return (width + 1, height + 1)
            case "VP8 ":
                guard let width = little(data, 26, 2), let height = little(data, 28, 2) else { return nil }
                return (width & 0x3FFF, height & 0x3FFF)
            case "VP8L":
                guard data.count >= 25, data[20] == 0x2F, let bits = little(data, 21, 4) else { return nil }
                return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
            default: return nil
        }
    }
}
