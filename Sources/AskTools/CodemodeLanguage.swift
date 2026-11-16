/// The language a codemode script is written in (ADR-0156).
enum CodemodeLanguage: String, Sendable, CaseIterable {
    case javascript
    case python

    /// The languages ask runs, as a sentence lists them.
    static let named = allCases.map(\.rawValue).joined(separator: " and ")
}
