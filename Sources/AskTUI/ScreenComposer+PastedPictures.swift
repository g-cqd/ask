internal import TerminalKitStyle
internal import TerminalKitText

/// The pictures the person pasted (roadmap 0224; the owner, 2026-11-12): their captions above the input while the draft names them,
/// and in their message's block, under its text, as a tool's pictures are under its header (roadmap 0208).
extension ScreenComposer {
    /// A caption row for each picture the draft names, `[image 1] PNG · 1280×800 · 245 KB`, in the rows the picker takes when open.
    static func pastedPictureLines(for state: ScreenState, columns: Int, rows: Int) -> [Line] {
        guard columns > 0, rows > 0 else { return [] }
        let attached = state.pictures.attached(in: state.editor.text)
        return attached.suffix(rows)
            .map { picture in
                let text = PastedPictures.token(picture.number) + " " + caption(picture.image)
                return Line(text: String(text.prefix(columns)), style: Style(dim: true))
            }
    }

    /// `lines`, a message's rows, with its pictures' captions and cells after them.
    static func withPictures(_ lines: [Line], _ context: ToolContext, block: Int, inset: Int) -> [Line] {
        guard !context.images.isEmpty, let last = lines.last else { return lines }
        // The image rows go after a header; here the message's last row stands for it, and is put back in place.
        let rows = withImageRows(
            [last],
            images: context.images,
            placements: context.placements,
            block: block,
            inset: inset
        )
        return lines.dropLast() + rows
    }
}
