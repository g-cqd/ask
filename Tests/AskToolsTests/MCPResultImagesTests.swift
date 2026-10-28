import AskAI
import AskMCP
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// A server's picture reaches the model like one `read` gives, and a server is not trusted to say what its bytes are (roadmap 0084).
@Suite("A tool result's pictures are sniffed, bounded and shown, and what cannot be shown is named")
struct MCPResultImagesTests {
    private func png(_ side: Int) -> String {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return (output as Data).base64EncodedString()
    }

    private func result(_ content: [MCPContent]) -> MCPToolResult {
        MCPToolResult(content: content, structuredContent: nil, isError: false)
    }

    @Test func `a picture is decoded whatever the server calls it, and the text says it is shown`() {
        let given = result([.text("chart:"), .image(mimeType: "image/jpeg", base64: png(32))])
        let images = MCPResultImages(given, allowance: .init())
        #expect(images.parts.count == 1 && images.parts[0].mediaType == "image/png")
        let text = MCPResultText.of(given, replacing: images.lines)
        #expect(text.hasPrefix("chart:\n\n[image png, 32×32,") && text.hasSuffix("shown]"))
    }

    @Test func `bytes that are not a picture are named and never sent`() {
        let given = result([.image(mimeType: "image/png", base64: Data("not an image".utf8).base64EncodedString())])
        let images = MCPResultImages(given, allowance: .init())
        #expect(images.parts.isEmpty)
        #expect(images.lines[0]?.contains("not shown, the bytes are not an image") == true)
        #expect(
            MCPResultImages(result([.image(mimeType: "image/png", base64: "!!!")]), allowance: .init()).parts.isEmpty)
    }

    @Test func `a result shows only so many pictures, and names the rest`() {
        let one = png(8)
        let given = result(
            Array(repeating: .image(mimeType: "image/png", base64: one), count: MCPResultImages.maximum + 2))
        let images = MCPResultImages(given, allowance: .init())
        #expect(images.parts.count == MCPResultImages.maximum)
        #expect(images.lines[MCPResultImages.maximum]?.contains("over the") == true)
    }

    @Test func `the allowance of the model's provider bounds a server's picture too`() {
        let given = result([.image(mimeType: "image/png", base64: png(32))])
        let images = MCPResultImages(given, allowance: .init(.init(mediaTypes: ["image/jpeg"])))
        #expect(images.parts.first?.mediaType == "image/jpeg")
    }
}
