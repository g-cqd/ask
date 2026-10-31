/// What a tool block is drawn with besides its item (roadmap 0078): its timer, its input with heredocs folded, whether it is a
/// command block, and its output with the middle folded away, nil for the whole output.
struct ToolContext {
    var progress: BlockProgress?
    var toolInput: ShownToolInput?
    var command: Bool
    var output: String?
}
