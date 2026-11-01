/// What reading a framed file found.
struct FramedRead {
    let header: FramedHeader
    let records: [[UInt8]]
    let ending: FramedEnding
    /// The bytes up to the end of the last good frame.
    let validLength: Int
    /// The good frames: the index the next frame takes.
    let frameCount: Int
}
