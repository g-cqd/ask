#if canImport(ImageIO)
    internal import CoreGraphics
    internal import Foundation
    internal import ImageIO
    internal import UniformTypeIdentifiers
#endif

/// A picture made a PNG for the terminal (roadmap 0208): kitty draws PNG or raw pixels, so a JPEG, GIF or WebP is decoded and encoded
/// again, at the size it is shown, never larger than its own (a GIF's first frame). Where ImageIO is missing, nothing is made, and
/// such a picture keeps its line only.
enum PictureTranscode {
    /// The kinds made a PNG, beside PNG itself, which is sent as it is.
    static let kinds: Set<String> = available ? ["image/jpeg", "image/gif", "image/webp"] : []

    #if canImport(ImageIO)
        static let available = true
    #else
        static let available = false
    #endif

    /// The size it is drawn at, upright: its header's, turned when its orientation says it is stored on its side (EXIF 5 to 8, as a
    /// phone's photographs often are). Read from its properties; nothing is decoded.
    static func size(_ data: [UInt8]) -> (width: Int, height: Int)? {
        #if canImport(ImageIO)
            guard let source = CGImageSourceCreateWithData(Data(data) as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            return (5 ... 8).contains(orientation) ? (height, width) : (width, height)
        #else
            return nil
        #endif
    }

    /// `data` as a PNG whose long side is at most `longSide` pixels; nil when it does not decode.
    static func png(_ data: [UInt8], longSide: Int) -> [UInt8]? {
        #if canImport(ImageIO)
            guard let source = CGImageSourceCreateWithData(Data(data) as CFData, nil),
                CGImageSourceGetCount(source) >= 1,
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: Swift.max(1, longSide)
                    ] as CFDictionary
                )
            else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return [UInt8](output as Data)
        #else
            return nil
        #endif
    }
}
