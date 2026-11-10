internal import AemiMarkdown
internal import TerminalKitText

/// A selection keeps source coordinates; complete relative prose paths are expanded after its source range is known (0215).
/// Neither displayed text nor transcript records are rewritten, and partial path selections stay literal.
enum ReplyPathCopy {
    static func text(
        _ selection: ContentSelection<Int>,
        in transcript: Transcript,
        display: PathDisplay?
    ) -> String? {
        guard let display else { return selection.text(in: TranscriptContent(transcript)) }
        let a = selection.anchor
        let b = selection.head
        let (start, end) = (a.block, a.line, a.offset) <= (b.block, b.line, b.offset) ? (a, b) : (b, a)
        guard transcript.items.indices.contains(start.block), transcript.items.indices.contains(end.block) else {
            return nil
        }
        var blocks: [String] = []
        for block in start.block ... end.block {
            let lines = TranscriptContent.hardLines(of: transcript.contentText(at: block))
            let text = lines.joined(separator: "\n")
            let first = block == start.block ? start : ContentPosition(block: block, line: 0, offset: 0)
            let last =
                block == end.block
                ? end : ContentPosition(block: block, line: lines.count - 1, offset: lines.last?.count ?? 0)
            let low = byteOffset(first, lines: lines)
            let high = Swift.max(low, byteOffset(last, lines: lines))
            let eligible: Bool =
                switch transcript.items[block] {
                    case .assistant, .thinking, .notice: true
                    default: false
                }
            blocks.append(
                slice(
                    text,
                    bytes: low ..< high,
                    display: eligible && !transcript.summaryBlocks.contains(block) ? display : nil,
                    markdown: transcript.markdown
                )
            )
        }
        return blocks.joined(separator: "\n")
    }

    private static func byteOffset(_ position: ContentPosition<Int>, lines: [String]) -> Int {
        guard !lines.isEmpty else { return 0 }
        let row = Swift.min(Swift.max(0, position.line), lines.count - 1)
        let offset = Swift.min(Swift.max(0, position.offset), lines[row].count)
        return lines.prefix(row).reduce(0) { $0 + $1.utf8.count + 1 } + lines[row].prefix(offset).utf8.count
    }

    private static func slice(_ text: String, bytes selected: Range<Int>, display: PathDisplay?, markdown: Bool)
        -> String
    {
        let bytes = Array(text.utf8)
        guard let display else { return String(decoding: bytes[selected], as: UTF8.self) }
        let excluded = markdown ? exclusions(bytes) : []
        // Only accepted paths are expanded. This calls the same policy-aware lookup used to decide relative links.
        var result = ""
        var cursor = selected.lowerBound
        for word in wordsByLine(bytes) {
            guard word.bytes.lowerBound >= cursor, word.bytes.upperBound <= selected.upperBound,
                !word.path.hasPrefix("/"),
                !excluded.contains(where: { $0.overlaps(word.bytes) }),
                !display.paths(in: String(decoding: bytes[word.bytes], as: UTF8.self)).isEmpty
            else { continue }
            result += String(decoding: bytes[cursor ..< word.bytes.lowerBound], as: UTF8.self)
            let absolute =
                word.path.hasPrefix("~/")
                ? display.home + word.path.dropFirst(1) : display.workspace + "/" + word.path
            result += PathDisplay.normalized(absolute) + word.location
            cursor = word.bytes.upperBound
        }
        result += String(decoding: bytes[cursor ..< selected.upperBound], as: UTF8.self)
        return result
    }

    /// The scanner's input is one prose run; hard newlines start new runs, not word-internal punctuation.
    private static func wordsByLine(_ bytes: [UInt8]) -> [PathDisplay.Word] {
        var result: [PathDisplay.Word] = []
        var start = 0
        for end in 0 ... bytes.count where end == bytes.count || bytes[end] == 0x0A {
            for var word in PathDisplay.words(in: Array(bytes[start ..< end])) {
                word.bytes = word.bytes.lowerBound + start ..< word.bytes.upperBound + start
                result.append(word)
            }
            start = end + 1
        }
        return result
    }

    /// Match the display hook's exclusions: code, math and explicit links/images are not prose path substitutions.
    private static func exclusions(_ bytes: [UInt8]) -> [Range<Int>] {
        let document = MarkdownParser.parse(bytes, extensions: ScreenComposer.markdownExtensions)
        var result: [Range<Int>] = []
        var blocked = 0
        let containers: Set<NodeKind> = [.codeSpan, .codeBlock, .math, .link, .image, .autolink]
        for event in document.events {
            switch event {
                case .enter(let node):
                    if containers.contains(node.kind) { blocked += 1 }
                case .exit(let node):
                    if containers.contains(node.kind) { blocked -= 1 }
                case .leaf(let node):
                    if blocked > 0 || [.codeLine, .infoString, .linkDestination, .linkTitle].contains(node.kind) {
                        result.append(node.range)
                    }
            }
        }
        return result
    }
}
