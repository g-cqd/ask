/// `ui.inputBorder` (note n36): the colour of the box around the input. `tint` (the default) is the session's own colour, lighter;
/// `dim` is the grey of secondary text.
public enum InputBorderPreference: String, Sendable, CaseIterable {
    case tint, dim
}
