/// `sessionPassword` (roadmap 0182): whether the key the password opens is kept in the keychain, or the password asked at every start.
public enum SessionPasswordMode: String, Sendable, CaseIterable {
    case remember
    case everyStart

    static let choices = #""remember" or "everyStart""#
}
