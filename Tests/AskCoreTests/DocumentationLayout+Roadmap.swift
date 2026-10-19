internal import Foundation

extension DocumentationLayout {
    private static let statuses: Set<String> = ["not-started", "in-progress", "done"]

    /// What is wrong with a set of roadmap entries, one sentence each; empty when they are sound.
    ///
    /// An entry is sound when its name starts with a unique four-digit number and a dash, its `status:` is
    /// `not-started`, `in-progress` or `done`, every number in `blocked-by:` names an entry that exists, and,
    /// unless the entry is itself done, none of those blockers is done: a blocker that has landed is no blocker.
    /// - Parameter entries: each entry's file name and text.
    /// - Returns: the problems found.
    static func roadmapProblems(in entries: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        var statusByNumber: [String: String] = [:]
        var fieldsByName: [String: [String: String]] = [:]
        for entry in entries {
            guard let number = entryNumber(of: entry.name) else {
                problems.append("\(entry.name): the name does not start with a four-digit number and a dash")
                continue
            }
            let fields = frontMatter(of: entry.text)
            fieldsByName[entry.name] = fields
            if statusByNumber[number] != nil {
                problems.append("\(entry.name): number \(number) is used by two entries")
            }
            statusByNumber[number] = fields["status"] ?? ""
        }
        for entry in entries {
            guard let fields = fieldsByName[entry.name] else { continue }
            guard let status = fields["status"], statuses.contains(status) else {
                problems.append(
                    "\(entry.name): status is \(fields["status"] ?? "missing"), not not-started, in-progress or done")
                continue
            }
            for blocker in numbers(in: fields["blocked-by", default: ""]) {
                guard let blockerStatus = statusByNumber[blocker] else {
                    problems.append("\(entry.name): blocked by \(blocker), which does not exist")
                    continue
                }
                if status != "done", blockerStatus == "done" {
                    problems.append("\(entry.name): still blocked by \(blocker), which is done")
                }
            }
        }
        return problems
    }

    private static func entryNumber(of name: String) -> String? {
        let digits = name.prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber), name.dropFirst(4).first == "-" else { return nil }
        return String(digits)
    }

    /// The four-digit numbers in a `blocked-by:` value such as `["0001", "0002"]`.
    private static func numbers(in value: String) -> [String] {
        value.split(whereSeparator: { !$0.isNumber }).filter { $0.count == 4 }.map(String.init)
    }
}
