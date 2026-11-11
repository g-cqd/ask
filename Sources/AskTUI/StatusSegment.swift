/// One piece of the status line: what it says, in the longest form first and then shorter ones, how long it is worth keeping, and whether a
/// click on it does something.
struct StatusSegment: Equatable {
    /// What a click on the segment means, so the composer can say which columns it covers.
    enum Target: Equatable {
        /// `mark` is the leading mark, which keeps its colour wherever it is and only while it is shown.
        case none, runners, below, mark
    }

    /// The forms it can take, longest first; never empty.
    var forms: [String]
    /// Higher is kept longer. A line that does not fit gives up the lowest first.
    var priority: Int
    var target = Target.none
    /// Whether it may be dropped whole when nothing shorter is left. A question and the model's name may not.
    var droppable = true
    /// How far down ``forms`` the fit has gone.
    var form = 0
    /// Whether it goes with the piece that ``carries`` it: never shortened or dropped alone (the leading mark, with the model's name).
    var attached = false
    /// Whether dropping it drops the attached pieces too (the model's name, with the mark).
    var carries = false

    init(_ forms: [String], priority: Int, target: Target = .none, droppable: Bool = true) {
        self.forms = forms
        self.priority = priority
        self.target = target
        self.droppable = droppable
    }

    init(_ text: String, priority: Int, target: Target = .none, droppable: Bool = true) {
        self.init([text], priority: priority, target: target, droppable: droppable)
    }

    var text: String { forms[form] }
    var hasShorterForm: Bool { form + 1 < forms.count }
}
