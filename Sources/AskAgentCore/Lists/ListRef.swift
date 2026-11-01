/// An id as the list tools write it (ADR-0141): `t3`, a range `t5-t9`, or `@2`, the second entry added earlier in the same call. A
/// number alone is not one: there is one way to write an id.
public enum ListRef: Hashable, Sendable {
    case id(Int)
    case range(ClosedRange<Int>)
    /// The n-th add of the call, from 1.
    case added(Int)

    /// `text` read with `prefix` (`t` for tasks, `i` for ideas); nil when it is none of the three forms.
    public init?(_ text: String, prefix: Character) {
        if text.first == "@" {
            guard let number = Int(text.dropFirst()), number > 0, number <= ListLimits.changesPerCall else {
                return nil
            }
            self = .added(number)
            return
        }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.map { part -> Int? in
            guard part.first == prefix, part.count > 1, part.count <= 8 else { return nil }
            return Int(part.dropFirst())
        }
        switch (numbers.count, numbers.first ?? nil, numbers.last ?? nil) {
            case (1, let id?, _) where id > 0: self = .id(id)
            case (2, let low?, let high?) where low > 0 && low <= high && high - low < ListLimits.idsPerCall:
                self = .range(low ... high)
            default: return nil
        }
    }

    /// The refs of a field written as one string, `t3 t5-t9 @1`; nil when one of them is none.
    public static func list(_ text: String, prefix: Character) -> [ListRef]? {
        var refs: [ListRef] = []
        for word in text.split(separator: " ") {
            guard let ref = ListRef(String(word), prefix: prefix) else { return nil }
            refs.append(ref)
        }
        return refs
    }

    /// The ids `refs` stand for, ranges expanded, in order and once each; `adds` are the call's adds for `@n`, nil where `@n` means
    /// nothing (a read, an idea). Says why in `refuse`'s words when one cannot be.
    public static func expand<Failure: Error>(
        _ refs: [ListRef],
        adds: [Int]?,
        refuse: (String) -> Failure
    ) throws(Failure) -> [Int] {
        var ids: [Int] = []
        for ref in refs {
            switch ref {
                case .id(let id): ids.append(id)
                case .range(let range): ids += range
                case .added(let number):
                    guard let adds else { throw refuse("@\(number) names an add, and only a call's changes add.") }
                    guard number <= adds.count else {
                        throw refuse("@\(number) names an add this call has not made yet.")
                    }
                    ids.append(adds[number - 1])
            }
        }
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// What an answer says of `ids`: `done t5–t9 (5)`, the count once there is more than one.
    public static func counted(_ word: String, _ ids: [Int], prefix: Character) -> String {
        let unique = Array(Set(ids))
        return "\(word) \(runs(unique, prefix: prefix))" + (unique.count > 1 ? " (\(unique.count))" : "")
    }

    /// `ids` as runs: `t3 t5–t9`, consecutive ids joined into a range.
    public static func runs(_ ids: [Int], prefix: Character) -> String {
        var runs: [String] = []
        var index = 0
        let sorted = ids.sorted()
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 { end += 1 }
            runs.append(
                end == index ? "\(prefix)\(sorted[index])" : "\(prefix)\(sorted[index])–\(prefix)\(sorted[end])"
            )
            index = end + 1
        }
        return runs.joined(separator: " ")
    }
}
