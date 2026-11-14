import AskAI
import Foundation

@testable import AskAgentCore
@testable import AskTools

/// Text from outside, through the small parsers and the guards of ADR-0150: an issue from GitHub, a web address, git's output, a
/// judge's reply, a typed command, a tool's input. Promised: none traps; untrusted text cannot leave its section; a run's events
/// are always JSON lines.
let fuzzText: @Sendable ([UInt8]) -> Void = { bytes in
    let text = String(decoding: bytes, as: UTF8.self)
    _ = GoalVerdict.parse(text)
    _ = RecurringCommand.parse(text)
    _ = ForgeReferences.numbers(in: text)
    _ = ForgeReferences.repository(fromRemote: text)
    _ = FetchAddress.check(text)
    _ = FetchAddress.host(of: text)
    _ = GitStatus.forms(porcelain: text)
    if let item = ForgeReferences.item(from: bytes) {
        let sent = ForgeReferences.attach("see #\(item.number)", items: [item])
        let markers = sent.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix("--- ") }
        if markers.count != 2 { broken("text: an issue's text left its section (\(markers.count) marker lines)") }
        if SkillInvocation.shown(sent) != "see #\(item.number)" {
            broken("text: an attachment changed what the person typed")
        }
    }
    _ = ForgeReferences.items(fromList: bytes)

    for line in UntrustedText.insideAttachment(text).split(separator: "\n", omittingEmptySubsequences: false)
    where line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("---") {
        broken("text: a line of untrusted text still starts as a marker does")
    }
    let tag = "untrusted-web-content"
    if UntrustedText.insideTags(text, tag: tag).range(of: tag, options: .caseInsensitive) != nil {
        broken("text: untrusted text still holds its section's tag")
    }

    if let input = try? JSONObject(validating: bytes) {
        _ = ToolSummary.header(for: input)
        _ = ToolSummary.fullInput(for: input)
    }
    for line in JSONEventWriter().lines(for: .model(.textDelta(index: 0, text))) {
        if line.contains("\n") { broken("text: an event is more than one line") }
        guard let input = try? JSONObject(validating: Array(line.utf8)) else {
            broken("text: an event's line is not JSON")
        }
        _ = input
    }
}
