import Foundation

/// Per-tab presentation state: pinned, locked and colour-tagged, matching the
/// Notepad++ tab context menu.
public struct TabAttributes: Codable, Equatable, Sendable {
    /// Notepad++ offers five tab colours plus "none".
    public enum Colour: Int, Codable, CaseIterable, Sendable {
        case none = -1, yellow = 0, green = 1, blue = 2, orange = 3, purple = 4

        public var displayName: String {
            switch self {
            case .none: return "None"
            case .yellow: return "Yellow"
            case .green: return "Green"
            case .blue: return "Blue"
            case .orange: return "Orange"
            case .purple: return "Purple"
            }
        }
    }

    public var isPinned = false
    public var colour: Colour = .none

    public init(isPinned: Bool = false, colour: Colour = .none) {
        self.isPinned = isPinned
        self.colour = colour
    }
}

public enum TabSorting {
    /// Reorders indices so pinned tabs come first, preserving relative order
    /// within each group. Notepad++ keeps pinned tabs at the left.
    public static func ordering(count: Int, isPinned: (Int) -> Bool) -> [Int] {
        let all = Array(0..<count)
        return all.filter(isPinned) + all.filter { !isPinned($0) }
    }

    /// Moving a tab must not let an unpinned tab jump ahead of a pinned one.
    public static func clampedDestination(
        moving source: Int, to destination: Int, isPinned: (Int) -> Bool, count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        let pinnedCount = (0..<count).filter(isPinned).count
        let target = min(max(0, destination), count - 1)
        if isPinned(source) {
            return min(target, max(0, pinnedCount - 1))
        }
        return max(target, pinnedCount)
    }

    /// Sort order for File > Sort Tabs.
    public enum Order { case name, path, extensionThenName }

    public static func sorted(
        indices: [Int], order: Order, name: (Int) -> String, path: (Int) -> String?
    ) -> [Int] {
        indices.sorted { left, right in
            switch order {
            case .name:
                return name(left).localizedStandardCompare(name(right)) == .orderedAscending
            case .path:
                return (path(left) ?? "").localizedStandardCompare(path(right) ?? "") == .orderedAscending
            case .extensionThenName:
                let leftExt = (name(left) as NSString).pathExtension.lowercased()
                let rightExt = (name(right) as NSString).pathExtension.lowercased()
                if leftExt != rightExt { return leftExt < rightExt }
                return name(left).localizedStandardCompare(name(right)) == .orderedAscending
            }
        }
    }
}
