import XCTest
import AppKit
@testable import NotepadXXUI
@testable import NotepadXXDesign
@testable import NotepadXXCore

/// The window has to hold together at every size and in every state the design
/// names. These drive the real window and assert the geometry that results,
/// because a layout that only looks right in one screenshot is not verified.
@MainActor
final class ResponsiveLayoutTests: XCTestCase {
    /// The sizes the design calls out, smallest first.
    private let sizes = [NSSize(width: 900, height: 600),
                         NSSize(width: 1100, height: 720),
                         NSSize(width: 1440, height: 900)]

    private func make(tabs count: Int, size: NSSize) -> MainWindowController {
        let controller = MainWindowController()
        let documents = (1...max(1, count)).map { index -> TextDocument in
            let document = TextDocument(text: "line one\nline two\n")
            document.untitledName = "document \(index).swift"
            return document
        }
        controller.adopt(documents: documents, activeIndex: 0)
        controller.window?.setContentSize(size)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: The editor keeps the window

    /// "The editing surface is 82% of the window height." The design refuses an
    /// editor below 80%, so chrome that grows without bound is a failure.
    func testTheEditorKeepsMostOfTheWindowAtEverySize() throws {
        for size in sizes {
            for tabCount in [1, 15, 50] {
                let controller = make(tabs: tabCount, size: size)
                let content = try XCTUnwrap(controller.window?.contentView)
                let editor = try XCTUnwrap(controller.currentEditor?.view)
                let height = editor.convert(editor.bounds, to: content).height
                XCTAssertGreaterThan(
                    height, content.bounds.height * 0.75,
                    "at \(Int(size.width))×\(Int(size.height)) with \(tabCount) tabs the editor "
                        + "is only \(Int(height)) of \(Int(content.bounds.height))")
            }
        }
    }

    /// Nothing may hang outside the window at any size.
    func testNoChromeOverflowsTheWindow() throws {
        for size in sizes {
            let controller = make(tabs: 15, size: size)
            let content = try XCTUnwrap(controller.window?.contentView)
            for view in [controller.toolbar as NSView, controller.tabBar as NSView,
                         controller.statusBar as NSView] {
                let frame = view.convert(view.bounds, to: content)
                XCTAssertLessThanOrEqual(frame.maxX, content.bounds.maxX + 0.5,
                                         "\(type(of: view)) overflows at \(Int(size.width))")
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
            }
        }
    }

    // MARK: Tab layouts

    /// Every layout must place every tab somewhere inside the strip.
    func testEveryTabLayoutPlacesEveryTab() throws {
        for layout in [DocumentTabStrip.Layout.horizontal, .wrapped, .vertical] {
            for size in sizes {
                let controller = make(tabs: 15, size: size)
                controller.setTabLayout(layout)
                controller.window?.contentView?.layoutSubtreeIfNeeded()

                let strip: DocumentTabStrip = controller.tabBar
                let tabs = descendants(of: strip).filter { $0 is DSTabView }
                XCTAssertEqual(tabs.count, 15,
                               "\(layout) at \(Int(size.width)) drew \(tabs.count) of 15 tabs")
                XCTAssertTrue(tabs.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 },
                              "\(layout) collapsed a tab to nothing")
            }
        }
    }

    /// The vertical rail sits beside the editor, not above it — the difference
    /// between a real side rail and a relabelled horizontal strip.
    func testTheVerticalRailSitsBesideTheEditor() throws {
        let controller = make(tabs: 6, size: NSSize(width: 1100, height: 720))
        controller.setTabLayout(.vertical)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let content = try XCTUnwrap(controller.window?.contentView)
        let stripView: DocumentTabStrip = controller.tabBar
        let strip = stripView.convert(stripView.bounds, to: content)
        let editorView = try XCTUnwrap(controller.currentEditor?.view)
        let editor = editorView.convert(editorView.bounds, to: content)

        XCTAssertLessThan(strip.width, 260, "the rail is a rail, not a full-width strip")
        XCTAssertGreaterThan(strip.height, editor.height * 0.7, "it runs down the window")
        XCTAssertGreaterThanOrEqual(editor.minX, strip.maxX - 1, "the editor starts after the rail")
    }

    /// Wrapped layout uses real rows: with many tabs the strip is taller than
    /// one row, and every tab is inside it.
    func testWrappedLayoutUsesRealRows() throws {
        let controller = make(tabs: 20, size: NSSize(width: 900, height: 600))
        controller.setTabLayout(.wrapped)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let strip: DocumentTabStrip = controller.tabBar
        let tabs = descendants(of: strip).compactMap { $0 as? DSTabView }
        let rows = Set(tabs.map { Int($0.frame.minY.rounded()) })
        XCTAssertGreaterThan(rows.count, 1, "20 tabs at 900 pt need more than one row")
        XCTAssertTrue(tabs.allSatisfy { $0.frame.maxX <= strip.bounds.width + 1 },
                      "a wrapped tab hangs off the edge instead of wrapping")
    }

    /// Horizontal layout scrolls rather than shrinking tabs to nothing.
    func testHorizontalLayoutScrollsInsteadOfShrinking() throws {
        let controller = make(tabs: 50, size: NSSize(width: 900, height: 600))
        controller.setTabLayout(.horizontal)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let stripView: DocumentTabStrip = controller.tabBar
        let tabs = descendants(of: stripView).compactMap { $0 as? DSTabView }
        XCTAssertEqual(tabs.count, 50)
        XCTAssertTrue(tabs.allSatisfy { $0.frame.width >= 60 },
                      "tabs keep a readable width and the strip scrolls instead")
    }

    // MARK: Toolbar and status bar

    /// "Toolbar sheds groups right to left into an overflow menu." Whole
    /// groups move, and a wider window never hides more than a narrow one.
    func testTheToolbarShedsGroupsWhenItRunsOutOfRoom() {
        var hiddenByWidth: [CGFloat: Int] = [:]
        for width in [560, 700, 900, 1100, 1440] as [CGFloat] {
            let controller = make(tabs: 1, size: NSSize(width: width, height: 600))
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            hiddenByWidth[width] = controller.toolbar.overflowedItems.count
        }
        XCTAssertGreaterThan(hiddenByWidth[560] ?? 0, 0,
                             "a 560 pt bar cannot hold every group and must overflow")
        XCTAssertEqual(hiddenByWidth[1440], 0, "at 1440 pt everything fits")

        let widths = hiddenByWidth.keys.sorted()
        for (narrower, wider) in zip(widths, widths.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                hiddenByWidth[narrower] ?? 0, hiddenByWidth[wider] ?? 0,
                "\(Int(wider)) pt hides more than \(Int(narrower)) pt")
        }
    }

    /// Cut, copy, paste and find never leave the bar.
    func testTheEssentialToolbarCommandsNeverOverflow() {
        let controller = make(tabs: 1, size: NSSize(width: 560, height: 600))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let hidden = Set(controller.toolbar.overflowedItems.map(\.label))
        for essential in ["Cut", "Copy", "Paste", "Find"] where hidden.contains(essential) {
            XCTFail("\(essential) was pushed into the overflow menu")
        }
    }

    /// The status bar collapses in stages rather than truncating.
    func testTheStatusBarChangesDensityWithWidth() {
        let wide = make(tabs: 1, size: NSSize(width: 1440, height: 900))
        let narrow = make(tabs: 1, size: NSSize(width: 900, height: 600))
        wide.window?.contentView?.layoutSubtreeIfNeeded()
        narrow.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(wide.statusBar.density, .full, "1440 pt shows the full labels")
        XCTAssertEqual(narrow.statusBar.density, .medium,
                       "900 pt shows the shorter forms, as the design specifies")

        let tiny = make(tabs: 1, size: NSSize(width: 700, height: 600))
        tiny.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(tiny.statusBar.density, .compact, "below 760 pt two groups hide entirely")
    }

    // MARK: Panels and split

    func testPanelsAndSplitStillLeaveTheEditorUsable() throws {
        for size in sizes {
            let controller = make(tabs: 3, size: size)
            controller.toggleFunctionListAction(nil)
            controller.toggleDocumentMapAction(nil)
            controller.toggleSplitViewAction(nil)
            // The dock sizes its panes on the next pass of the run loop, so
            // measuring immediately would measure a layout that has not run.
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            controller.window?.contentView?.layoutSubtreeIfNeeded()

            // Measure the editor area itself: with a split open, the active
            // document's own view may belong to the pane being rebuilt.
            let area = try XCTUnwrap(controller.dockHost?.editorContainer)
            XCTAssertGreaterThan(area.frame.width, size.width * 0.5,
                                 "with both side panels open at \(Int(size.width)) the editor area "
                                     + "is only \(Int(area.frame.width))")
            XCTAssertGreaterThan(area.frame.height, 100)

            // Both panes of the split get a real share of that area.
            let panes = controller.editorSplit.arrangedSubviews.map(\.frame.width)
            XCTAssertEqual(panes.count, 2, "the split shows two panes")
            for pane in panes {
                XCTAssertGreaterThan(pane, area.frame.width * 0.3,
                                     "a pane collapsed to \(Int(pane)) at \(Int(size.width))")
            }
        }
    }
}
