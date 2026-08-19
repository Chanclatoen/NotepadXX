import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXCore

/// Run and Run-a-macro are modeless command panels, and a command that prints
/// something must not look like a command that did nothing.
@MainActor
final class RunPanelTests: XCTestCase {
    private func make() -> MainWindowController {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\n")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1100, height: 720))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    func testRunIsAModelessPanel() throws {
        let controller = make()
        controller.runCommandAction(nil)
        let panel = try XCTUnwrap(controller.installedRunPanel?.window as? NSPanel)
        XCTAssertFalse(panel.isSheet)
        XCTAssertTrue(panel.isFloatingPanel)
    }

    /// The variable menu is built from the same table the expander reads, so it
    /// cannot offer a variable that would not be substituted.
    func testEveryOfferedVariableIsOneTheExpanderKnows() {
        let context = RunContext.forDocument(path: "/tmp/a.txt", line: 1, column: 1)
        for name in RunContext.variableNames {
            let expanded = RunCommandExpander.expand("$(\(name))", with: context)
            XCTAssertFalse(expanded.contains("$(\(name))"),
                           "\(name) is offered but not substituted")
        }
    }

    func testTheRunPanelRemembersItsCommand() throws {
        let controller = make()
        controller.runCommandAction(nil)
        let panel = try XCTUnwrap(controller.installedRunPanel)
        panel.setCommand("echo hello")
        controller.runCommandAction(nil)
        XCTAssertEqual(controller.installedRunPanel?.command, "echo hello",
                       "reopening keeps what was typed")
    }

    /// Output capture is the point of the checkbox: the panel has to fill.
    func testCapturedOutputReachesTheRunPanel() throws {
        let controller = make()
        let output = try XCTUnwrap(controller.runOutputPanel)
        controller.execute(command: "echo captured-output", capturingOutput: true)

        let deadline = Date().addingTimeInterval(5)
        while output.output.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(output.output.contains("captured-output"), "got: \(output.output)")
    }

    func testAFailingCommandReportsItsStatus() throws {
        let controller = make()
        let output = try XCTUnwrap(controller.runOutputPanel)
        controller.execute(command: "exit 3", capturingOutput: true)

        let deadline = Date().addingTimeInterval(5)
        while !output.status.contains("status"), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(output.status.contains("3"), "got: \(output.status)")
    }

    // MARK: Macros

    func testRunMacroPanelOffersBothCountAndToEndOfFile() throws {
        let panel = RunMacroPanelController()
        panel.present(macros: ["Trim & Sort"], stepCount: 6)
        XCTAssertEqual(panel.selectedMacro, "Trim & Sort")
        XCTAssertEqual(panel.repetitions, 10, "a count by default")
    }
}
