/// How a framed file ended when it was read.
enum FramedEnding: Equatable {
    /// Every frame was whole and checked.
    case clean
    /// The last frame was cut short or did not check: what a crash during an append leaves. It is dropped.
    case tornTail
    /// The frame at this index did not check and frames follow it: the file was changed or damaged. The records before it are kept.
    case damaged(frame: Int)
}
