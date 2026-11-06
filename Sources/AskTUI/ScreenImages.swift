internal import TerminalKitCodecs
internal import TerminalKitIO

/// The pictures the screen draws as pixels (roadmap 0208): asks the terminal once whether it draws kitty graphics, then sends each
/// tool's PNG once, under an id of its own, and records where it is placed, so the composer draws its placeholder rows.
///
/// A picture is sent off the screen's thread (a large one is a megabyte of text to the terminal, which must not hold a key or a
/// frame); the terminal shows its cells empty until it arrives. Other kinds than PNG keep their line only, for now.
struct ScreenImages {
    private let connection: any TerminalConnection
    /// Whether the terminal said it draws them; nil until it answers.
    private(set) var supported: Bool?
    /// The next id, in a range of ask's own within the 24 bits a placeholder's colour carries.
    private var nextID: UInt32 = 0xA5_0001
    private(set) var placed: [UInt32] = []

    /// The pictures for `connection`, when the environment says the terminal may draw them; nil otherwise.
    init?(connection: any TerminalConnection, mayDraw: Bool) {
        guard mayDraw else { return nil }
        self.connection = connection
    }

    /// Sends the query, off the screen's thread; the answer arrives as input.
    func ask() {
        let connection = connection
        Task.detached { try? connection.write(TerminalGraphics.query()) }
    }

    /// Takes the terminal's answer; false for any other input.
    mutating func take(_ bytes: [UInt8]) -> Bool {
        guard let answer = TerminalGraphics.answer(to: bytes) else { return false }
        supported = answer == .supported
        return true
    }

    /// Sends and places every PNG of `transcript` not placed yet, sized to the terminal's cells; true when it placed one.
    mutating func place(in transcript: inout Transcript, size: TerminalSize, inset: Int) -> Bool {
        guard supported == true, size.columns > 0, size.rows > 0, size.pixelWidth > 0, size.pixelHeight > 0 else {
            return false
        }
        let cell = (width: size.pixelWidth / size.columns, height: size.pixelHeight / size.rows)
        var any = false
        for (index, images) in transcript.toolImages where transcript.imagePlacements[index] == nil {
            transcript.imagePlacements[index] = images.map { image in
                guard image.mediaType == "image/png", let pixels = image.pixelSize, nextID < 0xFF_FFFF else {
                    return nil
                }
                let fit = ImagePlacement.fit(
                    pixels: pixels,
                    cell: cell,
                    maxColumns: size.columns - 2 * inset - 4,
                    maxRows: max(1, size.rows / 3)
                )
                let placement = ImagePlacement(id: nextID, columns: fit.columns, rows: fit.rows)
                nextID += 1
                placed.append(placement.id)
                let (connection, bytes) = (
                    connection,
                    ImagePlacement.commands(
                        id: placement.id,
                        png: image.data,
                        columns: fit.columns,
                        rows: fit.rows
                    )
                )
                Task.detached(priority: .utility) { try? connection.write(bytes) }
                return placement
            }
            // A new revision, so the block is laid out again with its placeholder rows: the layout keeps a block's rows until then.
            transcript.revisions[index] = transcript.bump()
            any = true
        }
        return any
    }

    /// Deletes every picture it sent, and only those, when the screen closes.
    func clear() {
        for id in placed {
            try? connection.write(
                GraphicsEncoder.encode(
                    GraphicsCommand(action: .delete, deletion: .image(id: id, freeingData: true), isQuiet: true)
                )
            )
        }
    }
}
