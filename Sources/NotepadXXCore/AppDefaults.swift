import Foundation

/// The app's `UserDefaults`, redirected for runs that must not touch the real ones.
///
/// Tests, `--benchmark`, `--screenshot` and `NOTEPADXX_SUPPORT_DIR` runs already
/// get their own support directory (`SessionStore.defaultDirectory()`); the
/// dock layout and window frames live in defaults, so those runs keep them in a
/// plist inside that directory. A domain named by an absolute path is read and
/// written at that path, so nothing lands in `~/Library/Preferences` and the
/// scratch directory takes the file with it when it is deleted.
public enum AppDefaults {
    /// True when the run has its own support directory instead of the user's.
    public static var isIsolated: Bool {
        let environment = ProcessInfo.processInfo.environment["NOTEPADXX_SUPPORT_DIR"] ?? ""
        return !environment.isEmpty
            || SessionStore.directoryOverride != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Fixed on first read, which is after `SessionStore.directoryOverride` is set at launch.
    // UserDefaults is documented as thread-safe; the SDK just does not mark it Sendable.
    nonisolated(unsafe) public static let store: UserDefaults = {
        guard isIsolated, let directory = try? SessionStore.defaultDirectory(),
              let suite = UserDefaults(suiteName: directory.appendingPathComponent("defaults").path)
        else { return .standard }
        return suite
    }()
}
