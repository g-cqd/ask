internal import TerminalKitCodecs
internal import TerminalKitIO

/// The pictures the screen draws as pixels (roadmap 0208): asks the terminal once whether it draws kitty graphics, then sends each
/// tool's PNG once, under an id of its own, and records where it is placed, so the composer draws its placeholder rows.
///
/// A picture is sent off the screen's thread (a large one is a megabyte of text to the terminal, which must not hold a key or a
/// frame); the terminal shows its cells empty until it arrives. A JPEG, GIF or WebP is made a PNG first, there too
/// (``PictureTranscode``); other kinds keep their line only.
struct ScreenImages {
    private let connection: any TerminalConnection
    /// Whether the terminal said it draws them; nil until it answers.
    private(set) var supported: Bool?
    /// The next id, in a range of ask's own within the 24 bits a placeholder's colour carries.
    private var nextID: UInt32 = 0xA5_0001
    private(set) var placed: [UInt32] = []
    /// The pictures the terminal holds now: those near the view (roadmap 0208).
    private(set) var sent: Set<UInt32> = []
    /// How many blocks either side of the view a picture is sent within, and kept within once sent: apart, so scrolling to and fro
    /// sends nothing twice.
    static let sendsWithin = 10
    static let keepsWithin = 40
    /// Each placed picture's size, read once: a JPEG's is read by ImageIO, which must not run again at every event.
    private var sizes: [UInt32: (width: Int, height: Int)] = [:]

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

    /// Places every picture of `transcript` not placed yet, sized to the terminal's cells and to `transcriptColumns` (the
    /// terminal's width when nil; less when the sidebar is open), and places again one whose fit changed, smaller or larger; sends
    /// to the terminal those near `view`, the blocks shown, and deletes there those far from it. True when a placement changed.
    mutating func place(
        in transcript: inout Transcript,
        size: TerminalSize,
        inset: Int,
        transcriptColumns: Int? = nil,
        near view: ClosedRange<Int>? = nil
    ) -> Bool {
        guard supported == true, size.columns > 0, size.rows > 0, size.pixelWidth > 0, size.pixelHeight > 0 else {
            return false
        }
        let cell = (width: size.pixelWidth / size.columns, height: size.pixelHeight / size.rows)
        let limits = (columns: (transcriptColumns ?? size.columns) - 2 * inset - 4, rows: max(1, size.rows / 3))
        var any = false
        for (index, images) in transcript.toolImages {
            let held = transcript.imagePlacements[index]
            let placements = images.enumerated()
                .map { position, image in
                    placement(
                        image,
                        held: held.flatMap { $0.indices.contains(position) ? $0[position] : nil },
                        cell,
                        limits
                    )
                }
            guard placements != held else { continue }
            transcript.imagePlacements[index] = placements
            // A new revision, so the block is laid out again with its placeholder rows: the layout keeps a block's rows until then.
            transcript.revisions[index] = transcript.bump()
            any = true
        }
        transmit(transcript, cell: cell, near: view)
        return any
    }

    /// Sends the placed pictures within ``sendsWithin`` blocks of `view` that the terminal lacks, and deletes there, freeing their data,
    /// those past ``keepsWithin``; with no view, sends them all. Their rows stay: a picture sent again fills the same cells.
    private mutating func transmit(
        _ transcript: Transcript,
        cell: (width: Int, height: Int),
        near view: ClosedRange<Int>?
    ) {
        for (index, placements) in transcript.imagePlacements {
            let distance =
                view.map { index < $0.lowerBound ? $0.lowerBound - index : Swift.max(0, index - $0.upperBound) } ?? 0
            let images = transcript.toolImages[index] ?? []
            for (position, placement) in placements.enumerated() {
                guard let placement else { continue }
                if distance > Self.keepsWithin, sent.remove(placement.id) != nil {
                    send(ImagePlacement.deletion(id: placement.id))
                } else if distance <= Self.sendsWithin, images.indices.contains(position), !sent.contains(placement.id)
                {
                    sent.insert(placement.id)
                    transmit(images[position], as: placement, cell: cell)
                }
            }
        }
    }

    /// Sends `image` to the terminal and places it as `placement`: a PNG as it is, another kind made one first, off the screen's thread.
    private func transmit(_ image: ToolImage, as placement: ImagePlacement, cell: (width: Int, height: Int)) {
        guard PictureTranscode.kinds.contains(image.mediaType) else {
            send(
                ImagePlacement.commands(
                    id: placement.id,
                    png: image.data,
                    columns: placement.columns,
                    rows: placement.rows
                )
            )
            return
        }
        // Made a PNG at the size it takes: decoding a photograph must not hold a key or a frame.
        let longSide = Swift.max(placement.columns * cell.width, placement.rows * cell.height)
        let (connection, data) = (connection, image.data)
        Task.detached(priority: .utility) {
            guard let commands = Self.converted(data, longSide: longSide, as: placement) else { return }
            try? connection.write(commands)
        }
    }

    /// `image` placed within `limits`: given an id when `held` is nil, placed again under its id when its fit changed; nil for
    /// one this does not draw (not a kind it sends, no size in its header, or ids used up).
    private mutating func placement(
        _ image: ToolImage,
        held: ImagePlacement?,
        _ cell: (width: Int, height: Int),
        _ limits: (columns: Int, rows: Int)
    ) -> ImagePlacement? {
        let converted = PictureTranscode.kinds.contains(image.mediaType)
        guard image.mediaType == "image/png" || converted,
            let pixels = held.flatMap({ sizes[$0.id] })
                ?? (converted ? PictureTranscode.size(image.data) : image.pixelSize)
        else { return nil }
        let fit = ImagePlacement.fit(pixels: pixels, cell: cell, maxColumns: limits.columns, maxRows: limits.rows)
        if let held {
            // Placed again whenever its fit changed: smaller when the transcript narrows, back to its size when it widens.
            guard held.columns != fit.columns || held.rows != fit.rows else { return held }
            // Only a picture the terminal holds is placed again there; one not sent is sent at its new size when it is.
            if sent.contains(held.id) {
                send(ImagePlacement.placement(id: held.id, columns: fit.columns, rows: fit.rows))
            }
            return ImagePlacement(id: held.id, columns: fit.columns, rows: fit.rows)
        }
        guard nextID < 0xFF_FFFF else { return nil }
        let placement = ImagePlacement(id: nextID, columns: fit.columns, rows: fit.rows)
        nextID += 1
        placed.append(placement.id)
        sizes[placement.id] = pixels
        return placement
    }

    /// The commands that send `data`, made a PNG whose long side is `longSide`, as `placement`; nil when it does not decode.
    static func converted(_ data: [UInt8], longSide: Int, as placement: ImagePlacement) -> [UInt8]? {
        guard let png = PictureTranscode.png(data, longSide: longSide) else { return nil }
        return ImagePlacement.commands(id: placement.id, png: png, columns: placement.columns, rows: placement.rows)
    }

    /// Writes `bytes` off the screen's thread: a picture is a megabyte of text to the terminal, which must not hold a key or a frame.
    private func send(_ bytes: [UInt8]) {
        let connection = connection
        Task.detached(priority: .utility) { try? connection.write(bytes) }
    }

    /// Deletes every picture it sent, and only those, when the screen closes.
    func clear() {
        for id in placed { try? connection.write(ImagePlacement.deletion(id: id)) }
    }
}
