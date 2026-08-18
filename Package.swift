// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotepadXX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotepadXX", targets: ["NotepadXX"]),
        .library(name: "NotepadXXCore", targets: ["NotepadXXCore"]),
    ],
    dependencies: [
        // MIT. Custom NSView text engine: virtualised line views, multi-cursor,
        // rectangular selection. Validated to open a 100MB/927k-line file in ~400ms.
        .package(url: "https://github.com/CodeEditApp/CodeEditTextView.git", from: "0.12.0"),
    ],
    targets: [
        .target(name: "NotepadXXCore"),
        .target(
            name: "NotepadXXEditor",
            dependencies: [
                "NotepadXXCore",
                .product(name: "CodeEditTextView", package: "CodeEditTextView"),
            ]
        ),
        .target(name: "NotepadXXUI", dependencies: ["NotepadXXCore", "NotepadXXEditor"]),
        .executableTarget(name: "NotepadXX", dependencies: ["NotepadXXUI"]),
        .testTarget(name: "NotepadXXCoreTests", dependencies: ["NotepadXXCore"]),
        .testTarget(name: "NotepadXXUITests", dependencies: ["NotepadXXUI", "NotepadXXCore"]),
    ]
)
