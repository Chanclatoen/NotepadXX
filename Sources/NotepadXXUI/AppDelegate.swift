import AppKit
import NotepadXXCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var windowController: MainWindowController!
    private var sessionStore: SessionStore?
    private var autosaveTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()

        sessionStore = try? SessionStore(directory: try! SessionStore.defaultDirectory())
        windowController = MainWindowController()

        // Restore the previous session before showing the window, so the user
        // never sees an empty editor flash on launch.
        let restored = sessionStore?.restoreDocuments()
        let documents = restored?.documents ?? []
        if documents.isEmpty {
            windowController.newDocument()
        } else {
            windowController.adopt(documents: documents, activeIndex: restored?.activeIndex ?? 0)
        }

        windowController.showWindow(nil)

        // Periodic snapshot so an abrupt termination loses at most a few seconds.
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.persistSession()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        persistSession()
    }

    /// Never prompt to save. Unsaved buffers are snapshotted and restored — this
    /// is the Notepad++ scratchpad contract.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func persistSession() {
        guard let store = sessionStore, let controller = windowController else { return }
        try? store.save(documents: controller.documents, activeIndex: controller.activeIndex)
    }
}
