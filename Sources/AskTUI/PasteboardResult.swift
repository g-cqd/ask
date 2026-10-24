/// How the host's pasteboard command ended, which is the one part of a copy the screen can actually observe.
enum PasteboardResult: Sendable, Equatable {
    case copied
    case failed(String)
}
