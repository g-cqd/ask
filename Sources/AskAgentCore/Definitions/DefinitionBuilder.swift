/// Builds a ``DefinitionValue`` from a parsed tree with a stack of its own, not by recursion: a head's nesting is bounded by the
/// reader's limits, and a walk over input never trusts the call stack with it.
enum DefinitionBuilder {
    /// What a node of the tree is: a scalar's text, or its children, with their keys for a map.
    enum Shape<Node> {
        case text(String)
        case list([Node])
        case map([(key: String, value: Node)])
    }

    static func build<Node>(_ root: Node, shape: (Node) -> Shape<Node>) -> DefinitionValue {
        // Each open list or map: its keys (nil for a list), its children, and the values built so far. The first frame holds only
        // the root, so the root is built as any child is.
        var stack: [(keys: [String]?, children: [Node], built: [DefinitionValue])] = [(nil, [root], [])]
        while true {
            let top = stack.count - 1
            if stack[top].built.count < stack[top].children.count {
                switch shape(stack[top].children[stack[top].built.count]) {
                    case .text(let text): stack[top].built.append(.text(text))
                    case .list(let children): stack.append((nil, children, []))
                    case .map(let pairs): stack.append((pairs.map(\.key), pairs.map(\.value), []))
                }
                continue
            }
            let done = stack.removeLast()
            guard !stack.isEmpty else { return done.built.first ?? .text("") }
            let value: DefinitionValue =
                if let keys = done.keys {
                    .map(zip(keys, done.built).map { DefinitionEntry(key: $0, value: $1) })
                } else {
                    .list(done.built)
                }
            stack[stack.count - 1].built.append(value)
        }
    }
}
