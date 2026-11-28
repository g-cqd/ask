/// A Semantic Version 2.0.0 (`major.minor.patch[-prerelease][+build]`), used to enforce `policy.minimumVersion` (roadmap 0130,
/// ADR-0168). Leading `v` is accepted so `"0.2.0"` and `"v0.2.0"` parse identically.
public struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public enum PrereleasePart: Sendable, Equatable, Comparable {
        case numeric(UInt64)
        case textual(String)

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
                case (.numeric(let a), .numeric(let b)): a < b
                case (.textual(let a), .textual(let b)): a < b
                // SemVer 2.0 section 11.4.1: numeric identifiers always have lower precedence than non-numeric ones.
                case (.numeric, .textual): true
                case (.textual, .numeric): false
            }
        }
    }

    public let major: UInt64
    public let minor: UInt64
    public let patch: UInt64
    public let prerelease: [PrereleasePart]

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prerelease.isEmpty else { return core }
        let suffix =
            prerelease.map { part in
                switch part {
                    case .numeric(let n): String(n)
                    case .textual(let s): s
                }
            }
            .joined(separator: ".")
        return "\(core)-\(suffix)"
    }

    public init?(_ raw: String) {
        var slice = Substring(raw)
        if slice.first == "v" || slice.first == "V" { slice = slice.dropFirst() }
        if let plus = slice.firstIndex(of: "+") {
            let build = slice[slice.index(after: plus)...]
            guard !build.isEmpty,
                build.split(separator: ".", omittingEmptySubsequences: false).allSatisfy(Self.validIdentifier)
            else { return nil }
            slice = slice[..<plus]
        }
        let preSlice: Substring?
        if let dash = slice.firstIndex(of: "-") {
            preSlice = slice[slice.index(after: dash)...]
            slice = slice[..<dash]
        } else {
            preSlice = nil
        }
        let coreParts = slice.split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
            let maj = Self.nonLeadingZeroNumber(coreParts[0]),
            let min = Self.nonLeadingZeroNumber(coreParts[1]),
            let pat = Self.nonLeadingZeroNumber(coreParts[2]),
            let parsedPre = Self.parsePrerelease(preSlice)
        else { return nil }
        major = maj
        minor = min
        patch = pat
        prerelease = parsedPre
    }

    private static func parsePrerelease(_ preSlice: Substring?) -> [PrereleasePart]? {
        guard let preSlice else { return [] }
        let parts = preSlice.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [PrereleasePart] = []
        for item in parts {
            guard validIdentifier(item) else { return nil }
            if item.allSatisfy(\.isNumber) {
                guard let n = nonLeadingZeroNumber(item) else { return nil }
                parsed.append(.numeric(n))
            } else {
                parsed.append(.textual(String(item)))
            }
        }
        return parsed
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        // SemVer 2.0 section 11.3: a pre-release version has lower precedence than the normal version.
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func nonLeadingZeroNumber(_ text: Substring) -> UInt64? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if text.count > 1, text.first == "0" { return nil }
        return UInt64(text)
    }

    private static func validIdentifier(_ text: Substring) -> Bool {
        !text.isEmpty
            && text.allSatisfy { ch in
                ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-")
            }
    }
}
