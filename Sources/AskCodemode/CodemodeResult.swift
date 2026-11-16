/// What a script came to: what it said, in order, and how it ended. A script that failed keeps what it had said.
package struct CodemodeResult: Sendable, Equatable {
    /// What the script said, its `return` last.
    package var items: [CodemodeItem] = []
    /// Why it failed, in the script's own terms (`TypeError: … (codemode.js:3)`); nil when it completed.
    package var failure: String?
    /// How many of its calls were still running when it ended: the keeper cancels them.
    package var unsettled = 0

    package init(items: [CodemodeItem] = [], failure: String? = nil, unsettled: Int = 0) {
        self.items = items
        self.failure = failure
        self.unsettled = unsettled
    }
}
