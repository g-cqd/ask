/// What opening a framed session found, to append after it: its header, how many frames it holds, and its data key when encrypted.
struct FramedOpening: Sendable, Equatable {
    let header: FramedHeader
    let frameCount: Int
    let fileKey: FileKey?
}
