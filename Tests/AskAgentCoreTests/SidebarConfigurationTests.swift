import Testing

@testable import AskAgentCore

@Suite("ui.sidebar says whether the runner sidebar starts open")
struct SidebarConfigurationTests {
    private func parse(_ text: String) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json")
    }

    @Test func `a file reads open and closed and reports them`() throws {
        #expect(try parse("{ui:{sidebar:'open'}}").ui?.sidebarOpen == true)
        let closed = try parse("{ui:{sidebar:'closed'}}")
        #expect(closed.ui?.sidebarOpen == false && closed.ui?.description == "sidebar closed")
    }

    @Test func `another word is refused by name`() {
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "ui.sidebar", reason: "is \"left\": use \"open\" or \"closed\"")
        ) { try parse("{ui:{sidebar:'left'}}") }
    }

    @Test func `a layer replaces it and keeps the other ui keys`() {
        let user = ConfigurationFile(ui: UISection(mouse: false, sidebarOpen: true))
        let project = ConfigurationFile(ui: UISection(sidebarOpen: false))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.ui.value.sidebarOpen == false && combined.ui.value.mouse == false)
    }
}
