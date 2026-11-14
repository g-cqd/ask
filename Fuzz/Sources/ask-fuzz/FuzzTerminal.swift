import TerminalKitInput

@testable import AskAgentCore

/// What the terminal sends (`SequenceRouter`: keys, pastes, pointer reports, replies) and what ask writes to it of the model's and
/// the tools' text (`TerminalTextFilter`). Promised: any bytes decode to events without a trap; filtered text holds no escape and no
/// control but tab and line feed, and is the same whether the text came whole or in pieces.
let fuzzTerminal: @Sendable ([UInt8]) -> Void = { bytes in
    var router = SequenceRouter()
    for byte in bytes { _ = router.feed(byte) }

    let text = String(decoding: bytes, as: UTF8.self)
    let whole = TerminalTextFilter.filtered(text)
    for scalar in whole.unicodeScalars {
        let value = scalar.value
        if (value < 0x20 && value != 0x09 && value != 0x0A) || value == 0x7F || (0x80 ... 0x9F).contains(value) {
            broken("terminal: filtered text holds the control U+\(String(value, radix: 16))")
        }
    }
    let scalars = Array(text.unicodeScalars)
    let cut = scalars.count / 2
    var filter = TerminalTextFilter()
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars[..<cut])
    var rest = String.UnicodeScalarView()
    rest.append(contentsOf: scalars[cut...])
    let parts = filter.filter(String(view)) + filter.filter(String(rest))
    if parts != whole { broken("terminal: text filtered in two pieces differs from the same text filtered whole") }
}
