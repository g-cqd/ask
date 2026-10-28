internal import AskAI
internal import Foundation

/// A conversation as the on-device model reads it: instructions, and one prompt holding as much of the recent conversation as the
/// window has room for. Pure text, so it is tested without the model.
///
/// The window is about four thousand tokens and must also hold the tools and the reply, so the newest turns are kept whole and the oldest are
/// dropped first, never the other way round, and a long tool result is cut in the middle where the ends say most.
enum ApplePrompt {
    /// How many characters a token is taken to be. Low on purpose: code and paths cost more tokens per character than prose.
    static let charactersPerToken = 3
    /// The most of a tool result kept.
    static let resultLimit = 1_400

    /// One text for each turn, oldest first. Reasoning blocks are not replayed; they are another model's.
    static func turns(_ messages: [ModelMessage]) -> [String] {
        var names: [String: String] = [:]
        var turns: [String] = []
        for message in messages {
            var parts: [String] = []
            for block in message.blocks {
                switch block {
                    case .text(let text) where !text.isEmpty:
                        parts.append((message.role == .user ? "User: " : "Assistant: ") + text)
                    case .toolCall(let id, let name, let input):
                        names[id] = name
                        parts.append("Assistant called \(name) with \(String(decoding: input.bytes, as: UTF8.self))")
                    case .toolResult(let id, let content, let isError, let images):
                        let label = (names[id] ?? "tool") + (isError ? " failed" : " returned")
                        let shown = clipped(ImagePart.noting(images, in: content), to: resultLimit)
                        parts.append("The \(label):\n" + shown)
                    case .text, .thinking, .redactedThinking: break
                }
            }
            if !parts.isEmpty { turns.append(parts.joined(separator: "\n")) }
        }
        return turns
    }

    /// The newest turns that fit in `budget` characters, oldest of them first. The newest turn is always kept, cut if it alone is too long.
    static func fit(_ turns: [String], budget: Int) -> String {
        var kept: [String] = []
        var used = 0
        for turn in turns.reversed() {
            let cost = turn.count + 2
            guard kept.isEmpty || used + cost <= budget else {
                break
            }
            kept.append(kept.isEmpty ? clipped(turn, to: budget) : turn)
            used += cost
        }
        return kept.reversed().joined(separator: "\n\n")
    }

    /// The instruction text: ask's own first block whole, then the others while they fit in `budget` characters.
    /// - Returns: the text, and how many blocks were cut or left out, so the person can be told.
    static func instructions(_ blocks: [String], budget: Int) -> (text: String, omitted: Int) {
        var kept: [String] = []
        var used = 0
        var omitted = 0
        for block in blocks where !block.isEmpty {
            if kept.isEmpty {
                kept.append(clipped(block, to: budget))
                used = kept[0].count
                if kept[0].count < block.count { omitted += 1 }
            } else if used + block.count + 2 <= budget {
                kept.append(block)
                used += block.count + 2
            } else {
                omitted += 1
            }
        }
        return (kept.joined(separator: "\n\n"), omitted)
    }

    /// `text` cut to `limit` characters by dropping its middle, with a mark where the cut is.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 40 else { return text.count > limit ? String(text.prefix(limit)) : text }
        let head = limit * 2 / 3
        let tail = limit - head - 16
        return String(text.prefix(head)) + "\n[…cut…]\n" + String(text.suffix(Swift.max(0, tail)))
    }

    /// A token count for `text`, estimated.
    static func estimatedTokens(_ text: String) -> Int { (text.count + charactersPerToken - 1) / charactersPerToken }
}
