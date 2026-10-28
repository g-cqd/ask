import AskAI
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// `read` fits a picture to what the model's provider accepts, beyond ask's own bounds (roadmap 0084).
@Suite("A provider's byte limit and media types shape the picture read")
struct ImageAllowanceTests {
    /// Noise, which does not compress, so a byte limit bites.
    private func noisy(_ side: Int) -> [UInt8] {
        var state: UInt64 = 42
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for index in pixels.indices where index % 4 != 3 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels[index] = UInt8(truncatingIfNeeded: state >> 56)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](output as Data)
    }

    @Test func `a byte limit makes the picture smaller than the file, within the limit`() throws {
        let bytes = noisy(600)
        #expect(bytes.count > 200_000)
        let limit = 60_000
        let result = try ImageReader.read(bytes, allowance: .init(ImageLimits(maximumBytes: limit)))
        #expect(result.part.data.count <= limit)
        let free = try ImageReader.read(bytes)
        #expect(free.part.data == bytes)
    }

    @Test func `a media type the provider lacks is converted to one it has`() throws {
        let result = try ImageReader.read(noisy(40), allowance: .init(ImageLimits(mediaTypes: ["image/jpeg"])))
        #expect(result.part.mediaType == "image/jpeg")
    }

    @Test func `no limits leave ask's own bounds alone`() {
        let allowance = ImageReader.Allowance()
        #expect(allowance.admits(count: 1_000_000) && allowance.admits(type: "image/webp"))
        #expect(!allowance.admits(count: 4_000_000))
    }
}
