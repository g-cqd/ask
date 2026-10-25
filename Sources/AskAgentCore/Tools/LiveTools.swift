internal import AskAI
internal import Synchronization

/// Tools that arrive and leave while a session runs, held in named groups (ADR-0099). A server's tools are one group: they are
/// there once it has connected, and gone when it has not.
///
/// Groups keep the order they first arrived in, and replacing a group keeps its place, so the tool list the model sees does not
/// reorder itself between requests (that would move the prompt-cache prefix). A name offered twice belongs to the first.
public final class LiveTools: Sendable {
    private struct Group {
        var name: String
        var tools: [any Tool]
    }

    private let groups = Mutex<[Group]>([])

    /// Nothing offered yet.
    public init() {}

    /// Makes `tools` the whole of group `name`: what it offered before is gone.
    /// - Parameters:
    ///   - name: the group, such as a server's name.
    ///   - tools: what it offers now; an empty list removes the group's tools and keeps its place.
    public func replace(group name: String, with tools: [any Tool]) {
        groups.withLock { groups in
            if let index = groups.firstIndex(where: { $0.name == name }) {
                groups[index].tools = tools
            } else {
                groups.append(Group(name: name, tools: tools))
            }
        }
    }

    /// Every tool offered now, in order, without a name offered twice and without any of `reserved`.
    func snapshot(excluding reserved: Set<String>) -> [any Tool] {
        var seen = reserved
        return groups.withLock { groups in
            groups.flatMap(\.tools).filter { seen.insert($0.definition.name).inserted }
        }
    }
}
