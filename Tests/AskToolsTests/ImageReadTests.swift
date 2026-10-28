import AskAI
import AskAgentCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// `read` on an image (roadmap 0084): sniffed by its bytes, bounded, returned as a part.
@Suite("read returns an image as an image, bounded, and refuses what it cannot make safe")
struct ImageReadTests {
    private let root: URL
    private let context: ToolContext

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ask-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: root.path)
    }

    /// A solid-colour image of this size, encoded as `type`.
    private func encoded(_ width: Int, _ height: Int, as type: UTType) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let pixels = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixels.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        pixels.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pixels.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func read(_ name: String, _ data: Data) async throws -> ToolOutput {
        try data.write(to: root.appending(path: name))
        let input = try JSONObject(validating: Array(#"{"path":"\#(name)"}"#.utf8))
        return await ReadTool().run(input, in: context)
    }

    @Test func `a small PNG is passed through unchanged, named by its bytes and not its extension`() async throws {
        let png = try encoded(40, 30, as: .png)
        let output = try await read("picture.txt", png)
        #expect(!output.isError)
        #expect(output.images == [ImagePart(mediaType: "image/png", data: [UInt8](png))])
        #expect(output.content.contains("40×30"))
    }

    @Test func `a JPEG is recognised`() async throws {
        let output = try await read("a.jpg", try encoded(50, 50, as: .jpeg))
        #expect(output.images.first?.mediaType == "image/jpeg")
    }

    @Test func `an image longer than 2000 pixels is scaled down, not sent whole`() async throws {
        let output = try await read("big.png", try encoded(3000, 1000, as: .png))
        #expect(!output.isError)
        let part = try #require(output.images.first)
        let source = try #require(CGImageSourceCreateWithData(Data(part.data) as CFData, nil))
        let size = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((size[kCGImagePropertyPixelWidth] as? Int) == 2000)
        #expect(part.data.count <= ImageReader.maximumEncodedBytes)
    }

    @Test func `an image that will not compress is shrunk until its base64 form fits`() throws {
        // Noise defeats PNG and JPEG alike, so the first sizes cannot fit and the loop has to shrink it (pi's strategy).
        let side = 2400
        var generator = SystemRandomNumberGenerator()
        let noise = (0 ..< side * side * 4).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
        let provider = CGDataProvider(data: Data(noise) as CFData)!
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let result = try ImageReader.read([UInt8](output as Data))
        #expect(ImageReader.encodedSize(result.part.data.count) < ImageReader.maximumEncodedBytes)
        #expect(result.summary.contains("sent as"))
    }

    @Test func `a large JPEG stays a JPEG instead of becoming a far larger PNG`() async throws {
        let output = try await read("big.jpg", try encoded(3000, 2000, as: .jpeg))
        #expect(output.images.first?.mediaType == "image/jpeg")
    }

    @Test func `bytes that start like an image but are not one are refused with a reason`() async throws {
        let output = try await read("fake.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0]))
        #expect(output.isError && output.images.isEmpty)
        #expect(output.content.contains("could not be decoded"))
    }

    @Test func `text is still text`() async throws {
        let output = try await read("a.txt", Data("hello".utf8))
        #expect(output == ToolOutput("hello"))
    }

    @Test func `the sniffed type ignores the name and knows GIF and WebP headers`() {
        #expect(ImageReader.mediaType(of: Array("GIF89a....".utf8)) == "image/gif")
        #expect(ImageReader.mediaType(of: Array("RIFF\0\0\0\0WEBPVP8 ".utf8)) == "image/webp")
        #expect(ImageReader.mediaType(of: Array("plain text".utf8)) == nil)
    }
}
