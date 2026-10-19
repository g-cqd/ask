internal import Foundation

extension DocumentationLayout {
    /// What is wrong with a set of architecture records, one sentence each; empty when they are sound.
    ///
    /// A record is sound when its name starts with a unique four-digit number, its front matter says
    /// `status: accepted` or `status: superseded`, and a superseded record names an existing successor that
    /// names it back in `supersedes:`, so the chain can be walked in both directions.
    /// - Parameter records: each record's file name and text.
    /// - Returns: the problems found, in no particular order.
    static func adrProblems(in records: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        var byNumber: [String: [String: String]] = [:]
        for record in records {
            guard let number = adrNumber(of: record.name) else {
                problems.append("\(record.name): the name does not start with a four-digit number and a dash")
                continue
            }
            if byNumber[number] != nil { problems.append("\(record.name): number \(number) is used by two records") }
            byNumber[number] = frontMatter(of: record.text)
        }
        for record in records {
            guard let number = adrNumber(of: record.name), let fields = byNumber[number] else { continue }
            switch fields["status"] {
                case "accepted": continue
                case "superseded": problems += successorProblems(of: record.name, number: number, fields, in: byNumber)
                case let other:
                    problems.append("\(record.name): status is \(other ?? "missing"), not accepted or superseded")
            }
        }
        return problems
    }

    private static func successorProblems(
        of name: String, number: String, _ fields: [String: String], in byNumber: [String: [String: String]]
    ) -> [String] {
        guard let successor = fields["superseded-by"] else { return ["\(name): superseded, but names no successor"] }
        let successorNumber = String(successor.drop(while: { !$0.isNumber }))
        guard let successorFields = byNumber[successorNumber] else {
            return ["\(name): superseded by \(successor), which does not exist"]
        }
        guard successorFields["supersedes", default: ""].contains("ADR-\(number)") else {
            return ["\(name): superseded by \(successor), which does not name it in `supersedes:`"]
        }
        return []
    }

    private static func adrNumber(of name: String) -> String? {
        let digits = name.prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber), name.dropFirst(4).first == "-" else { return nil }
        return String(digits)
    }

    /// The `key: value` lines between the opening and closing `---`.
    private static func frontMatter(of text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "---" {
                if inside { break }
                inside = true
            } else if inside, let colon = line.firstIndex(of: ":") {
                fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }
}
