internal import Foundation

/// The pictures pasted into the input (roadmap 0224; the owner, 2026-11-12), each named in the draft by an `[image N]` token where
/// it was pasted. The draft stays text: queued, taken back, recalled from history, a message names its pictures by the tokens it
/// still holds, and those are what is sent with it. Numbers are never reused while the screen is open.
struct PastedPictures: Sendable, Equatable {
    /// A picture a draft names, and its number.
    struct Attached: Sendable, Equatable {
        let number: Int
        let image: ToolImage
    }

    private var byNumber: [Int: ToolImage] = [:]
    private var last = 0

    /// Keeps `image`; returns the number its token names.
    mutating func add(_ image: ToolImage) -> Int {
        last += 1
        byNumber[last] = image
        return last
    }

    /// `[image N]`.
    static func token(_ number: Int) -> String { "[image \(number)]" }

    /// The pictures `text` names by their tokens, in the order it names them.
    func images(in text: String) -> [ToolImage] { attached(in: text).map(\.image) }

    /// The pictures `text` names, with their numbers, in order; a token for no picture kept here is text like any other.
    func attached(in text: String) -> [Attached] {
        guard !byNumber.isEmpty, text.contains("[image ") else { return [] }
        return Self.numbers(in: text)
            .compactMap { number in byNumber[number].map { Attached(number: number, image: $0) } }
    }

    /// The numbers of the `[image N]` tokens in `text`, in order.
    static func numbers(in text: String) -> [Int] {
        var found: [Int] = []
        var rest = text[...]
        while let open = rest.range(of: "[image ") {
            let digits = rest[open.upperBound...].prefix { $0.isASCII && $0.isNumber }
            let after = rest.index(open.upperBound, offsetBy: digits.count)
            if !digits.isEmpty, after < rest.endIndex, rest[after] == "]", let number = Int(digits) {
                found.append(number)
            }
            rest = rest[open.upperBound...]
        }
        return found
    }

    /// How many characters before the end of `text` an `[image N]` token takes, when it ends there; nil otherwise.
    static func tokenLength(endingAt text: Substring) -> Int? {
        guard text.hasSuffix("]"), let open = text.range(of: "[image ", options: .backwards) else { return nil }
        let digits = text[open.upperBound...].dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return text.distance(from: open.lowerBound, to: text.endIndex)
    }
}
