/// The head of a definition file read as the subset of YAML real harness files use, and as much more as can be read without being strict.
///
/// It never fails. What it cannot understand it skips and says so; what it can it keeps, whatever its shape.
struct YAMLHead {
    private(set) var entries: [DefinitionEntry]
    private(set) var hints: [DefinitionEntry]
    private(set) var diagnostics: [String]

    init(lines: [String]) {
        var parser = YAMLParser(lines: lines)
        parser.run()
        (entries, hints, diagnostics) = (parser.entries, parser.hints, parser.diagnostics)
    }
}
