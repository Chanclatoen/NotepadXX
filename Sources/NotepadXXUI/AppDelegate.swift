import AppKit
import NotepadXXCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var windowController: MainWindowController!
    private var sessionStore: SessionStore?
    private var autosaveTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()

        let options = CommandLineOptions.parse(CommandLine.arguments)
        sessionStore = try? SessionStore(directory: try! SessionStore.defaultDirectory())
        windowController = MainWindowController()

        // Restore the previous session before showing the window, so the user
        // never sees an empty editor flash on launch.
        let restored = options.noSession ? nil : sessionStore?.restoreDocuments()
        let documents = restored?.documents ?? []
        if !documents.isEmpty {
            windowController.adopt(documents: documents, activeIndex: restored?.activeIndex ?? 0)
        }

        // Files named on the command line open after the restored session, so a
        // requested file is what ends up focused.
        var openedFromCommandLine = false
        for request in options.files {
            let url = URL(fileURLWithPath: (request.path as NSString).expandingTildeInPath)
            guard windowController.openOrFocus(url: url) else { continue }
            if options.readOnly, windowController.documents.indices.contains(windowController.activeIndex) {
                windowController.documents[windowController.activeIndex].isReadOnly = true
            }
            if let line = request.line {
                windowController.currentEditor?.goToLine(line)
                if let column = request.column {
                    windowController.currentEditor?.moveToColumn(column, onLine: line)
                }
            }
            openedFromCommandLine = true
        }

        if documents.isEmpty && !openedFromCommandLine {
            windowController.newDocument()
        }

        // Demo mode drives the new display options for screenshot verification.
        // Plugins load before anything can invoke a plugin command.
        windowController.reloadPlugins()

        if let spec = ProcessInfo.processInfo.environment["NOTEPADXX_RUN_PLUGIN"] {
            let parts = spec.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2, let error = windowController.pluginHost?.invoke(
                pluginIdentifier: parts[0], commandID: parts[1]
            ) {
                FileHandle.standardError.write(Data("plugin error: \(error)\n".utf8))
            }
        }
        if ProcessInfo.processInfo.environment["NOTEPADXX_DEMO"] == "prefs" {
            windowController.showPreferencesAction(nil)
        }
        if ProcessInfo.processInfo.environment["NOTEPADXX_DEMO"] == "shortcuts" {
            windowController.showShortcutMapperAction(nil)
        }

        // The Shortcut Mapper's command list is discovered from the menu bar,
        // so it cannot drift out of step with the menus.
        if let mainMenu = NSApp.mainMenu, let support = try? SessionStore.defaultDirectory() {
            let discovered = MainWindowController.discoverCommands(in: mainMenu)
            windowController.shortcutMap = ShortcutMap(commands: discovered, directory: support)
            windowController.applyShortcuts()
        }
        if let preferences = windowController.preferencesStore?.preferences {
            windowController.applyPreferences(preferences)
        }

        // Demo overrides go after preferences, which would otherwise reset them.
        if ProcessInfo.processInfo.environment["NOTEPADXX_DEMO"] == "1" {
            windowController.showSpaces = true
            windowController.showTabs = true
            windowController.showLineEndings = true
            windowController.applyInvisibles()
            windowController.dockHost?.show("documentMap")
            windowController.dockHost?.show("functionList")
            windowController.toggleBookmarkAction(nil)
            windowController.setTabLayout(.vertical)
            for editor in windowController.allEditors { editor.edgeColumn = 40 }
        }

        windowController.loadUserLanguages()
        // The Float Panel submenu is built from the registered panels.
        if let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" }),
           let floatItem = viewMenu.submenu?.items.first(where: { $0.title == "Float Panel" }) {
            floatItem.submenu = windowController.buildFloatPanelMenu()
        }
        windowController.rebuildRecentMenu()
        windowController.rebuildSessionMenu()
        windowController.rebuildProjectMenu()

        windowController.showWindow(nil)

        // --screenshot <path> renders the window and exits, for CI and for
        // verifying the UI where screen capture is unavailable.
        if let path = options.screenshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let title = ProcessInfo.processInfo.environment["NOTEPADXX_CAPTURE_WINDOW"]
                if let title, WindowCapture.writePNG(ofWindowTitled: title, to: path) {
                    // captured the named auxiliary window
                } else if let window = self.windowController.window {
                    WindowCapture.writePNG(of: window, to: path)
                }
                NSApp.terminate(nil)
            }
            return
        }

        // Periodic snapshot so an abrupt termination loses at most a few seconds.
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.persistSession()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        persistSession()
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            windowController.openOrFocus(url: url)
        }
    }

    /// Files changed by other programs are noticed when the user comes back to
    /// the app, which is when they would look for the change.
    public func applicationDidBecomeActive(_ notification: Notification) {
        windowController?.checkForExternalChanges()
    }

    /// Never prompt to save. Unsaved buffers are snapshotted and restored — this
    /// is the Notepad++ scratchpad contract.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func persistSession() {
        guard let store = sessionStore, let controller = windowController else { return }
        try? store.save(documents: controller.documents, activeIndex: controller.activeIndex)
    }
}
