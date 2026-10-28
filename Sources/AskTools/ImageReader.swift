internal import AskAI
internal import CoreGraphics
internal import Foundation
internal import ImageIO
internal import UniformTypeIdentifiers

/// Turns the bytes of an image file into one that is safe to send to a model (roadmap 0084).
///
/// The type is read from the first bytes, not the file name. An image that is too large in pixels or bytes is scaled
/// down and re-encoded rather than sent, because one oversized image makes a provider refuse every later request of the
/// conversation, not only that turn. The same bounding serves pages of a PDF and frames of a video.
enum ImageReader {
    /// The long side, in pixels, past which an image is scaled down.
    static let maximumSide = 2000
    /// The size of the image as base64, in bytes, below which it is sent as it is. 4.5 MiB leaves room under
    /// Anthropic's 5 MB limit. These numbers and the order below are pi's (`image-resize-core.js`); the owner chose
    /// to adopt them (2026-10-28).
    static let maximumEncodedBytes = 4_718_592
    /// JPEG qualities tried after PNG, in pi's order.
    static let qualities: [Double] = [0.80, 0.85, 0.70, 0.55, 0.40]
    /// Types a provider accepts as they are, when single-frame and within the limits.
    private static let passThrough: Set<String> = ["image/png", "image/jpeg", "image/webp"]

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

    /// An image bounded for sending.
    struct Fitted {
        var part: ImagePart
        var width: Int
        var height: Int
    }

    /// The media type the first bytes name, or nil when they are not a supported image.
    ///
    /// PNG, JPEG, GIF and WebP are sent as they are when they fit; BMP, TIFF, HEIC and AVIF are decoded by ImageIO and
    /// sent as PNG or JPEG, because no provider takes them (measured decode in diary 2026-10-28-06).
    static func mediaType(of bytes: [UInt8]) -> String? {
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }
        // BMP: "BM", then the size, then two reserved fields that are zero.
        if bytes.count >= 14, bytes[0] == 0x42, bytes[1] == 0x4D, bytes[6 ... 9].allSatisfy({ $0 == 0 }) {
            return "image/bmp"
        }
        guard bytes.count >= 12 else { return nil }
        let box = Array(bytes[4 ..< 12])
        if bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8 ..< 12]) == Array("WEBP".utf8) { return "image/webp" }
        if box.starts(with: Array("ftyp".utf8)) {
            switch String(decoding: box[4...], as: UTF8.self) {
                case "avif", "avis": return "image/avif"
                case "heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1": return "image/heic"
                default: return nil
            }
        }
        return nil
    }

    /// The image, bounded.
    /// - Parameters:
    ///   - bytes: the file.
    ///   - allowance: what the model's provider accepts, beyond ask's own bounds.
    /// - Returns: the picture to send and a line describing it.
    /// - Throws: ``Failure`` when the bytes are not an image, are animated, cannot be decoded, or cannot be made to fit.
    static func read(_ bytes: [UInt8], allowance: Allowance = Allowance()) throws(Failure) -> Result {
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
            ["image/png", "image/gif", "image/bmp"].contains(type)
            || (properties[kCGImagePropertyHasAlpha] as? Bool) == true
        let name = type.dropFirst("image/".count)
        if passThrough.contains(type), frames == 1, max(width, height) <= maximumSide, allowance.admits(type: type),
            allowance.admits(count: bytes.count)
        {
            return Result(
                part: ImagePart(mediaType: type, data: bytes),
                summary: "image \(name), \(width)×\(height), \(bytes.count) bytes")
        }

        let fitted = try fit(favoursPNG: favoursPNG, longSide: max(width, height), allowance: allowance) { side in
            // ImageIO decodes JPEG and HEIC at reduced size, which a full decode and a separate scale cannot do
            // (diary 2026-10-28-05 and -06: faster, and 3–15× less memory than vImage, Core Image or Metal).
            CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: side
                ] as CFDictionary)
        }
        return Result(
            part: fitted.part,
            summary: "image \(name), \(width)×\(height), \(bytes.count) bytes, sent as "
                + "\(fitted.part.mediaType.dropFirst(6)) \(fitted.width)×\(fitted.height), \(fitted.part.data.count) bytes"
        )
    }

    /// Encodes what `render` makes at a long side, at the largest size and best format that stays within the limits.
    ///
    /// Fit within the long side limit (never up); try PNG, then JPEG at each quality, and take the first that is small
    /// enough. If none is, shrink by a quarter and try again, down to one pixel (pi's strategy). PNG goes first only for
    /// an image likely to be flat; measured on this machine, a photograph costs ~300 ms and 3–5 MB as PNG against
    /// ~20 ms and 0.4–0.7 MB as JPEG (diary 2026-10-28-05).
    /// - Parameters:
    ///   - favoursPNG: whether the picture is likely flat or transparent.
    ///   - longSide: the picture's own long side.
    ///   - allowance: what the model's provider accepts, beyond ask's own bounds.
    ///   - render: the picture scaled so its long side is at most the given number of pixels.
    /// - Returns: the encoded picture and its size.
    /// - Throws: ``Failure/undecodable`` when `render` gives nothing, ``Failure/cannotFit`` when even one pixel is too big.
    static func fit(
        favoursPNG: Bool, longSide: Int, allowance: Allowance = Allowance(), render: (Int) -> CGImage?
    ) throws(Failure) -> Fitted {
        var side = min(maximumSide, longSide)
        while true {
            guard let scaled = render(side) else { throw .undecodable }
            let jpegs = qualities.map { (UTType.jpeg, Optional($0)) }
            let attempts: [(UTType, Double?)] = favoursPNG ? [(.png, nil)] + jpegs : jpegs + [(.png, nil)]
            for (format, quality) in attempts {
                let mediaType = format == .png ? "image/png" : "image/jpeg"
                guard allowance.admits(type: mediaType), let encoded = encode(scaled, as: format, quality: quality),
                    allowance.admits(count: encoded.count)
                else { continue }
                return Fitted(
                    part: ImagePart(mediaType: mediaType, data: [UInt8](encoded)), width: scaled.width,
                    height: scaled.height)
            }
            guard side > 1 else { throw .cannotFit }
            side = max(1, side * 3 / 4)
        }
    }

    /// `image` redrawn with its long side at most `side`, or itself when it is already that small.
    static func scaled(_ image: CGImage, toLongSide side: Int) -> CGImage? {
        let long = max(image.width, image.height)
        guard side < long else { return image }
        let width = max(1, image.width * side / long)
        let height = max(1, image.height * side / long)
        guard
            // @dl:accept -- a bitmap context is made the same way for a scaled image and a drawn page; the arguments differ, so sharing would take as many
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
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
