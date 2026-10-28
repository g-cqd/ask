/// The list of commands offered while the draft's first word is a slash (roadmap 0048), and which of them is chosen.
///
/// The picker is derived from the draft after every key, so it cannot disagree with it; what it keeps is the choice, which survives
/// typing that does not change the query, and the first row of the window it scrolls in.
struct CompletionPicker: Sendable, Equatable {
    /// What the rows are, which names the list and decides what a choice means.
    enum Kind: Sendable, Equatable {
        case commands
        case files
        /// What a command offers after its name; `title` is the command's name.
        case choices(title: String)
        /// The interactive configuration editor: a modal list whose rows are settings.
        case config(scope: String, file: String)

        /// The word that titles the list.
        var title: String {
            switch self {
                case .commands: "commands"
                case .files: "files"
                case .choices(let name): name
                case .config(let scope, _): "config · \(scope)"
            }
        }

        var isConfig: Bool {
            if case .config = self { true } else { false }
        }
    }

    /// What is being listed.
    let kind: Kind
    /// What to say beside the name: that the files are still being listed, how many the sandbox hid, that matches were cut.
    let caption: String
    /// The word the matches are for.
    let trigger: CompletionTrigger
    /// Every command that matches, best first.
    var matches: [PickerRow]
    /// The chosen match.
    private(set) var selected = 0
    /// The first match the window shows.
    private(set) var firstVisible = 0
    /// How many matches the window shows at most.
    let capacity: Int

    /// A picker over `matches`, the first chosen.
    init(kind: Kind, trigger: CompletionTrigger, matches: [PickerRow], capacity: Int, caption: String = "") {
        self.kind = kind
        self.caption = caption
        self.trigger = trigger
        self.matches = matches
        self.capacity = Swift.max(1, capacity)
    }

    /// The matches the window shows.
    var visible: ArraySlice<PickerRow> {
        matches[firstVisible ..< Swift.min(matches.count, firstVisible + capacity)]
    }

    /// The indexes a group heading never holds: the ones a person can choose.
    var choiceIndexes: [Int] { matches.indices.filter { !matches[$0].isHeading } }

    /// How many matches can be chosen; group headings are not matches.
    var countOfChoices: Int { choiceIndexes.count }

    /// Puts the selection on the nearest match, so it never rests on a group heading.
    mutating func snapSelectionToChoice() {
        guard matches.indices.contains(selected), !matches[selected].isHeading else {
            let nearest = choiceIndexes.min {
                abs($0 - selected) < abs($1 - selected) || (abs($0 - selected) == abs($1 - selected) && $0 < $1)
            }
            selected = nearest ?? selected
            settle()
            return
        }
    }

    /// The most matches listed on a screen of `screenRows`: seven, fewer on a short screen, so the transcript keeps its rows.
    static func capacity(screenRows: Int) -> Int { Swift.max(1, Swift.min(7, (screenRows - 6) / 2)) }

    /// Moves the choice by `step` among the matches a heading never holds, wrapping at either end, and
    /// scrolls the window to keep it in view.
    mutating func move(_ step: Int) {
        let choices = choiceIndexes
        guard !choices.isEmpty else { return }
        let current = choices.firstIndex(of: selected) ?? 0
        selected = choices[((current + step) % choices.count + choices.count) % choices.count]
        settle()
    }

    /// Chooses match `index`, as a click on its row does. The row was in view to be clicked, so the window stays where it is. The caller
    /// passes a match that exists.
    mutating func choose(_ index: Int) { selected = index }

    /// Keeps `old`'s choice when this is the same word with the same query, as a keystroke that changed nothing the list depends on.
    mutating func keepChoice(from old: CompletionPicker) {
        guard old.trigger.range.lowerBound == trigger.range.lowerBound, old.trigger.query == trigger.query else {
            return
        }
        selected = Swift.max(0, Swift.min(old.selected, matches.count - 1))
        firstVisible = old.firstVisible
        settle()
        snapSelectionToChoice()
    }

    private mutating func settle() {
        if selected < firstVisible {
            firstVisible = selected
        } else if selected >= firstVisible + capacity {
            firstVisible = selected - capacity + 1
        }
        firstVisible = Swift.max(0, Swift.min(firstVisible, Swift.max(0, matches.count - capacity)))
    }
}
