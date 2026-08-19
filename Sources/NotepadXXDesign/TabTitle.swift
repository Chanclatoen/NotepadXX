import Foundation

/// How a document's name is shortened for a tab.
public enum TabTitle {
    /// The width beyond which a name is shortened.
    public static let maximumCharacters = 28

    /// Truncates from the middle, so the extension survives.
    ///
    /// `SessionRestorationCoordinator.swift` becomes
    /// `SessionResto…Coordinator.swift` rather than `SessionRestorationCoo…`,
    /// which would hide the one part that says what kind of file it is.
    public static func shortened(_ name: String, limit: Int = maximumCharacters) -> String {
        guard name.count > limit, limit > 4 else { return name }
        // Keep the extension whole where it is a sensible length.
        let extensionPart = (name as NSString).pathExtension
        let keepTail = extensionPart.isEmpty || extensionPart.count > 8
            ? limit / 3
            : extensionPart.count + 12
        let keepHead = max(1, limit - keepTail - 1)

        let head = String(name.prefix(keepHead))
        let tail = String(name.suffix(keepTail))
        return "\(head)…\(tail)"
    }
}
