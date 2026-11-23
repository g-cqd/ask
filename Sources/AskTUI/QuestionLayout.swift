/// The composed rows of a pending question section and the hit-test maps that go with them (roadmap 0117, note n5):
/// `choices` is the row range of the choices and note, `choiceRows` says which choice each of those rows belongs to
/// (nil for the note, since a wrapped explanation spans more than one row), and `tabs` is the row of the tab bar when shown.
struct QuestionLayout {
    let lines: [ScreenComposer.Line]
    let choices: Range<Int>
    let choiceRows: [Int?]
    let tabs: Int?
}
