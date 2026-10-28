internal import AskAI
internal import Foundation
internal import ImageIO
internal import UniformTypeIdentifiers

/// Turns the bytes of an image file into one that is safe to send to a model (roadmap 0084).
///
/// The type is read from the first bytes, not the file name. An image that is too large in pixels or bytes is scaled
/// down and re-encoded rather than sent, because one oversized image makes a provider refuse every later request of the
/// conversation, not only that turn.
enum ImageReader {
    /// The long side, in pixels, past which an image is scaled down.
    static let maximumSide = 2000
    /// The size of the image as base64, in bytes, below which it is sent as it is. 4.5 MiB leaves room under
    /// Anthropic's 5 MB limit. These numbers and the order below are pi's (`image-resize-core.js`); the owner chose
    /// to adopt them (2026-10-28).
    static let maximumEncodedBytes = 4_718_592
    /// JPEG qualities tried after PNG, in pi's order.
    static let qualities: [Double] = [0.80, 0.85, 0.70, 0.55, 0.40]

    /// The base64 size of `count` bytes.
    static func encodedSize(_ count: Int) -> Int { (count + 2) / 3 * 4 }

    /// What reading an image gave.
    struct Result: Equatable {
        var part: ImagePart
        /// The one line the model and the screen see: type, size in pixels, bytes, and what was done.
        var summary: String
    }

    enum Failure: Error, Equatable {
        case notAnImage
        case animated
        case undecodable
        case cannotFit
    }

    /// The media type the first bytes name, or nil when they are not a supported image.
    static func mediaType(of bytes: [UInt8]) -> String? {
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8 ..< 12]) == Array("WEBP".utf8) {
            return "image/webp"
        }
        return nil
    }

    /// The image, bounded.
    /// - Throws: ``Failure`` when the bytes are not an image, are animated, cannot be decoded, or cannot be made to fit.
    static func read(_ bytes: [UInt8]) throws(Failure) -> Result {
        guard let type = mediaType(of: bytes) else { throw .notAnImage }
        let data = Data(bytes)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) >= 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw .undecodable }
        let frames = CGImageSourceGetCount(source)
        // An animated PNG is refused (a model sees one frame at best); other animations send their first frame.
        if type == "image/png", frames > 1 { throw .animated }

        let favoursPNG =
            type == "image/png" || type == "image/gif" || (properties[kCGImagePropertyHasAlpha] as? Bool) == true
        let name = type.dropFirst("image/".count)
        let isFixed = type != "image/gif" && frames == 1
        if isFixed, max(width, height) <= maximumSide, encodedSize(bytes.count) < maximumEncodedBytes {
            return Result(
                part: ImagePart(mediaType: type, data: bytes),
                summary: "image \(name), \(width)×\(height), \(bytes.count) bytes")
        }

        // Fit within the long side limit (never up); try PNG, then JPEG at each quality, and take the first that is
        // small enough. If none is, shrink by a quarter and try again, down to one pixel (pi's strategy).
        var side = min(maximumSide, max(width, height))
        while true {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side
            ]
            guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw .undecodable
            }
            // Measured on this machine (diary 2026-10-28-05): encoding a photograph as PNG costs ~300 ms and gives
            // 3–4 MB where JPEG gives 0.4–0.7 MB in ~20 ms. So PNG goes first only for an image that is likely flat
            // (a PNG or GIF source, or anything with transparency); a photograph goes to JPEG first.
            let jpegs = qualities.map { (UTType.jpeg, Optional($0)) }
            let attempts: [(UTType, Double?)] = favoursPNG ? [(.png, nil)] + jpegs : jpegs + [(.png, nil)]
            for (format, quality) in attempts {
                guard let encoded = encode(scaled, as: format, quality: quality),
                    encodedSize(encoded.count) < maximumEncodedBytes
                else { continue }
                let mediaType = format == .png ? "image/png" : "image/jpeg"
                return Result(
                    part: ImagePart(mediaType: mediaType, data: [UInt8](encoded)),
                    summary: "image \(name), \(width)×\(height), \(bytes.count) bytes, sent as "
                        + "\(mediaType.dropFirst(6)) \(scaled.width)×\(scaled.height), \(encoded.count) bytes")
            }
            guard side > 1 else { throw .cannotFit }
            side = max(1, side * 3 / 4)
        }
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
