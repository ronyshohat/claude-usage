// swift-tools-version: 5.9
//
// Test-only package. The app and the widget are built from
// ClaudeUsage.xcodeproj (see project.yml / Tools/generate-project.sh); this
// file exists so `swift test` can exercise Sources/ClaudeUsageCore without
// Xcode and without a second copy of the sources.
//
// XcodeGen reads project.yml and xcodebuild reads the generated project, so
// neither of them looks at this file.

import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeUsageCore", path: "Sources/ClaudeUsageCore"),
        .testTarget(
            name: "CoreTests",
            dependencies: ["ClaudeUsageCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
