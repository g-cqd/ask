/// What a tool block is drawn with besides its item (roadmap 0078): its timer, its input with heredocs folded, whether it is a
/// command block, its output with the middle folded away (nil for the whole output), and the facts its tool reported.
struct ToolContext {
    var progress: BlockProgress?
    var toolInput: ShownToolInput?
    var command: Bool
    var output: String?
    /// The occurrences an edit reported replacing, counted on the header's right instead of its acknowledgement's line.
    var replacements: Int?
}
