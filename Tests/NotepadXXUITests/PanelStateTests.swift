import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// "Every panel ships empty, loading and populated." A panel with nothing in
/// it should say why and what to do about it, rather than showing an empty
/// list that looks broken.
@MainActor
final class PanelStateTests: XCTestCase {
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func placeholder(in panel: DockablePanel) -> DSEmptyState? {
        descendants(of: panel.contentView).compactMap { $0 as? DSEmptyState }.first
    }

    private func laidOut(_ panel: DockablePanel) -> DockablePanel {
        panel.contentView.frame = NSRect(x: 0, y: 0, width: 260, height: 360)
        panel.contentView.layoutSubtreeIfNeeded()
        return panel
    }

    func testTheClipboardPanelExplainsItselfWhenEmpty() throws {
        let panel = ClipboardHistoryPanel()
        panel.stopPolling()
        _ = laidOut(panel)

        let empty = try XCTUnwrap(placeholder(in: panel))
        XCTAssertFalse(empty.isHidden, "an empty clipboard shows its placeholder")

        panel.record("something copied")
        XCTAssertTrue(empty.isHidden, "and hides it once there is history")
    }

    func testTheWorkspacePanelAsksForAFolder() throws {
        let panel = FolderWorkspacePanel()
        _ = laidOut(panel)

        let empty = try XCTUnwrap(placeholder(in: panel))
        XCTAssertFalse(empty.isHidden)

        panel.addRoot(URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertTrue(empty.isHidden)
    }

    func testTheProjectPanelOffersToCreateOne() throws {
        let panel = ProjectPanel()
        var created = 0
        panel.onCreateProject = { created += 1 }
        _ = laidOut(panel)
        panel.reload()

        let empty = try XCTUnwrap(placeholder(in: panel))
        XCTAssertFalse(empty.isHidden, "with no project open the panel says so")

        // The placeholder's button does something, rather than being decoration.
        let button = try XCTUnwrap(descendants(of: empty).compactMap { $0 as? NSButton }.first)
        _ = button.target?.perform(button.action, with: button)
        XCTAssertEqual(created, 1)
    }

    func testTheFunctionListExplainsAnEmptyDocument() throws {
        let panel = FunctionListPanel()
        panel.symbolProvider = { [] }
        _ = laidOut(panel)
        panel.reload()

        let empty = try XCTUnwrap(placeholder(in: panel))
        XCTAssertFalse(empty.isHidden)

        panel.symbolProvider = { [Symbol(name: "main", kind: "function", line: 0, offset: 0)] }
        panel.reload()
        XCTAssertTrue(empty.isHidden)
    }
}

/// Every docked panel carries the design's header: sentence case, with float
/// and close buttons.
@MainActor
final class PanelHeaderTests: XCTestCase {
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    func testEveryDockedPanelShowsAHeaderWithItsName() throws {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\n")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1440, height: 900))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let host = try XCTUnwrap(controller.dockHost)
        for identifier in ["documentMap", "functionList", "clipboardHistory"] {
            host.show(identifier)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let headers = descendants(of: controller.window!.contentView!)
            .compactMap { $0 as? DSPanelHeader }
        let titles = headers.map(\.title)
        for expected in ["Document Map", "Function List", "Clipboard History"] {
            XCTAssertTrue(titles.contains(expected), "no header for \(expected); saw \(titles)")
        }

        // Sentence case, not the shouted uppercase the design refuses.
        for title in titles {
            XCTAssertNotEqual(title, title.uppercased(), "\(title) is upper-cased")
        }

        // And each header is actually on screen, not collapsed to nothing.
        for header in headers {
            XCTAssertGreaterThan(header.frame.height, 0, "\(header.title)'s header has no height")
            XCTAssertGreaterThan(header.frame.width, 0, "\(header.title)'s header has no width")
        }
    }
}

/// The header test above passed while the Document Map was painting straight
/// over its header, because a frame can be right while nothing is drawn there.
/// This renders the window and looks at the pixels.
@MainActor
final class PanelHeaderRenderingTests: XCTestCase {
    func testAPanelDoesNotPaintOverItsOwnHeader() throws {
        let controller = MainWindowController()
        controller.adopt(documents: [TextDocument(text: "one\ntwo\nthree\n")], activeIndex: 0)
        controller.window?.setContentSize(NSSize(width: 1000, height: 700))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.dockHost?.show("documentMap")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let content = try XCTUnwrap(controller.window?.contentView)
        let header = try XCTUnwrap(
            descendants(of: content).compactMap { $0 as? DSPanelHeader }
                .first { $0.title == "Document Map" })

        let path = NSTemporaryDirectory() + "npxx-panel-header.png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(WindowCapture.writePNG(of: controller.window!, to: path))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

        // Sample the middle of the header band, in the bitmap's top-down space.
        let frame = header.convert(header.bounds, to: content)
        let x = Int(frame.midX)
        let y = Int(content.bounds.height - frame.midY)
        let sampled = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
        let headerColour = try XCTUnwrap(DS.Color.panel.usingColorSpace(.sRGB))
        let editorColour = try XCTUnwrap(DS.Color.content.usingColorSpace(.sRGB))

        func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
            abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                + abs(a.blueComponent - b.blueComponent)
        }
        XCTAssertLessThan(distance(sampled, headerColour), distance(sampled, editorColour),
                          "the header band is painted in the panel's colour, not the map's")
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
