#if canImport(ImageIO)
    internal import CoreGraphics
    internal import Foundation
    internal import ImageIO
    internal import TerminalKitIO
    import Testing
    internal import UniformTypeIdentifiers

    @testable import AskTUI

    /// JPEG, GIF and WebP drawn as pixels (roadmap 0208): kitty takes PNG or raw pixels, so they are made a PNG first, at the size
    /// they are shown, off the screen's thread.
    @Suite("A JPEG or a GIF is made a PNG to be drawn")
    struct PictureTranscodeTests {
        /// A `width` by `height` picture of one colour, encoded as `type`.
        static func encoded(_ type: UTType, _ width: Int, _ height: Int, orientation: Int = 1) throws -> [UInt8] {
            let space = CGColorSpaceCreateDeviceRGB()
            let context = try #require(
                CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            return [UInt8](data as Data)
        }

        @Test func `a JPEG and a GIF become a PNG no larger than asked, their shape kept`() throws {
            for type in [UTType.jpeg, .gif] {
                let png = try #require(PictureTranscode.png(try Self.encoded(type, 400, 200), longSide: 100), "\(type)")
                #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "\(type)")
                let size = try #require(ImagePixelSize.read(png))
                #expect(size.width == 100 && size.height == 50, "\(type): \(size)")
            }
        }

        @Test func `a photograph stored on its side is sized and drawn upright`() throws {
            let sideways = try Self.encoded(.jpeg, 400, 200, orientation: 6)
            let size = try #require(PictureTranscode.size(sideways))
            #expect(size.width == 200 && size.height == 400, "\(size)")
            let png = try #require(PictureTranscode.png(sideways, longSide: 100))
            let drawn = try #require(ImagePixelSize.read(png))
            #expect(drawn.width == 50 && drawn.height == 100, "\(drawn)")
        }

        @Test func `a small picture is not made larger, and bytes that are no picture give nothing`() throws {
            let png = try #require(PictureTranscode.png(try Self.encoded(.jpeg, 40, 20), longSide: 500))
            let size = try #require(ImagePixelSize.read(png))
            #expect(size.width == 40 && size.height == 20)
            #expect(PictureTranscode.png(Array("not a picture".utf8), longSide: 100) == nil)
        }

        @Test func `a JPEG a tool returned is placed, and a PNG is what the terminal is sent`() throws {
            let connection = MockTerminalConnection()
            var images = try #require(ScreenImages(connection: connection, mayDraw: true))
            _ = images.take(Array("\u{1B}_Gi=\(TerminalGraphics.queryID);OK\u{1B}\\".utf8))
            var transcript = Transcript()
            transcript.startTool(name: "read", summary: "a.jpg", id: "r1")
            let jpeg = ToolImage(mediaType: "image/jpeg", data: try Self.encoded(.jpeg, 400, 200))
            transcript.finishTool(.succeeded, output: "Read a.jpg", id: "r1", images: [jpeg])
            let size = TerminalSize(columns: 100, rows: 60, pixelWidth: 1000, pixelHeight: 1200)
            #expect(images.place(in: &transcript, size: size, inset: 1))
            #expect(transcript.imagePlacements[0]?.first ?? nil != nil)
            let placement = try #require(transcript.imagePlacements[0]?.first ?? nil)
            // What the detached send writes, built as it builds it: a transmission of PNG bytes, not the JPEG's.
            let commands = try #require(ScreenImages.converted(jpeg.data, longSide: 120, as: placement))
            let written = String(decoding: commands, as: UTF8.self)
            #expect(
                written.contains("a=t") && written.contains("f=100") && written.contains("iVBORw0KGgo"),
                "sent as PNG"
            )
            #expect(!written.contains("/9j/"), "not as the JPEG")
        }
    }
#endif
