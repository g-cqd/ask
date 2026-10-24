internal import Testing

@testable import AskTUI

/// A host copy ends later than it starts, so its result must not overwrite what happened since.
@Suite("A late copy result applies only to the copy it belongs to")
struct CopyGenerationTests {
    private func controller(notice: String = "Host copy pending") -> (ScreenController, Int) {
        var controller = ScreenController(label: "m")
        let generation = controller.beginCopy()
        controller.state.clipboardNotice = notice
        return (controller, generation)
    }

    @Test func `the final notice replaces the pending one`() {
        var (controller, generation) = controller()
        controller.finishCopy("Copied to host clipboard", failed: false, generation: generation)
        #expect(controller.state.clipboardNotice == "Copied to host clipboard")
    }

    @Test func `a result for an earlier copy is dropped once a newer one began`() {
        var (controller, first) = controller()
        let second = controller.beginCopy()
        controller.state.clipboardNotice = "Host copy pending"
        controller.finishCopy("Host copy failed: old", failed: true, generation: first)
        #expect(controller.state.clipboardNotice == "Host copy pending")
        controller.finishCopy("Copied to host clipboard", failed: false, generation: second)
        #expect(controller.state.clipboardNotice == "Copied to host clipboard")
    }

    @Test func `a notice the user cleared stays cleared when the copy worked`() {
        var (controller, generation) = controller()
        controller.clearSelection()
        controller.finishCopy("Copied to host clipboard", failed: false, generation: generation)
        #expect(controller.state.clipboardNotice.isEmpty)
    }

    @Test func `a failure is shown even after the notice was cleared`() {
        var (controller, generation) = controller()
        controller.clearSelection()
        controller.finishCopy("Host copy failed: pbcopy exited with status 1", failed: true, generation: generation)
        #expect(controller.state.clipboardNotice == "Host copy failed: pbcopy exited with status 1")
    }
}
