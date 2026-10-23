/// The list of commands offered while the draft's first word is a slash (roadmap 0048), and which of them is chosen.
///
/// The picker is derived from the draft after every key, so it cannot disagree with it; what it keeps is the choice, which survives
/// typing that does not change the query, and the first row of the window it scrolls in.
struct CompletionPicker: Sendable, Equatable {
    /// The word the matches are for.
    let trigger: CompletionTrigger
    /// Every command that matches, best first.
    private(set) var matches: [SlashCommand]
    /// The chosen match.
    private(set) var selected = 0
    /// The first match the window shows.
    private(set) var firstVisible = 0
    /// How many matches the window shows at most.
    let capacity: Int

    /// A picker over `matches`, the first chosen.
    init(trigger: CompletionTrigger, matches: [SlashCommand], capacity: Int) {
        self.trigger = trigger
        self.matches = matches
        self.capacity = Swift.max(1, capacity)
    }

    /// The matches the window shows.
    var visible: ArraySlice<SlashCommand> {
        matches[firstVisible ..< Swift.min(matches.count, firstVisible + capacity)]
    }

    /// The most matches listed on a screen of `screenRows`: seven, fewer on a short screen, so the transcript keeps its rows.
    static func capacity(screenRows: Int) -> Int { Swift.max(1, Swift.min(7, (screenRows - 6) / 2)) }

    /// Moves the choice by `step`, wrapping at either end, and scrolls the window to keep it in view.
    mutating func move(_ step: Int) {
        guard !matches.isEmpty else { return }
        selected = ((selected + step) % matches.count + matches.count) % matches.count
        settle()
    }

    /// Keeps `old`'s choice when this is the same word with the same query, as a keystroke that changed nothing the list depends on.
    mutating func keepChoice(from old: CompletionPicker) {
        guard old.trigger.range.lowerBound == trigger.range.lowerBound, old.trigger.query == trigger.query else {
            return
        }
        selected = Swift.min(old.selected, matches.count - 1)
        firstVisible = old.firstVisible
        settle()
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
