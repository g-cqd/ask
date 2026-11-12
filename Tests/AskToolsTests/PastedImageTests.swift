import AskAI
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AskTools

/// A pasted picture bounded as the read tool bounds one (roadmap 0224), or refused in words.
@Suite("A pasted picture is bounded as a read one, or refused in words")
struct PastedImageTests {
    private func png(_ width: Int, _ height: Int) throws -> [UInt8] {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](output as Data)
    }

    @Test func `a small PNG goes as it is, and bytes that are no picture are refused in words`() throws {
        let png = try png(3, 2)
        #expect(try PastedImage.bounded(png).get() == ImagePart(mediaType: "image/png", data: png))
        guard case .failure(let refusal) = PastedImage.bounded(Array("not a picture".utf8)) else {
            Issue.record("text was taken for a picture")
            return
        }
        #expect(refusal.description.hasPrefix("it is not a picture ask can read"))
    }

    @Test func `a picture past 2000 pixels is made smaller`() throws {
        let large = try png(3_000, 1_000)
        let part = try PastedImage.bounded(large).get()
        let reread = try ImageReader.read(part.data)
        #expect(reread.summary.contains("2000×667") || reread.summary.contains("2000×666"), "\(reread.summary)")
    }
}
