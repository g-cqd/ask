/// Who an agent or a client is (ACP v1, Initialization): a name for programs, a title for people, a version.
package struct ACPImplementation: Sendable, Equatable, Decodable {
    package let name: String
    package let title: String?
    package let version: String

    package init(name: String, title: String? = nil, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}
