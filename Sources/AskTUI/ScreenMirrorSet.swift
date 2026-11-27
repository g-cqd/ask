/// A screen's mirrors (ADR-0170): the viewers' terminals shown now, the tasks reading their input, and where they attach.
struct ScreenMirrorSet {
    var shown: [Int: ScreenMirror] = [:]
    var inputs: [Int: Task<Void, Never>] = [:]
    /// The process's place, or a test's own.
    let registry: ScreenMirrors
}
