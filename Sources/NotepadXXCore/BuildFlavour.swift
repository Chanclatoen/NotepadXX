/// Which build this is. `swift build -Xswiftc -DMAS` makes the Mac App Store
/// flavour: sandboxed, so no shell commands, no plug-in downloads, and files
/// outside the user's grants are reached through security-scoped bookmarks.
public enum BuildFlavour {
    #if MAS
    public static let isAppStore = true
    #else
    public static let isAppStore = false
    #endif
}
