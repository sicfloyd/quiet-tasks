// swift-tools-version: 5.9
import PackageDescription

// Tests compile the actual application logic without its @main entry point.
let package = Package(
    name: "QuietTasksSecurityTests",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(name: "QuietTasksLogic", path: "Sources", exclude: ["QuietTasksWidget"],
                swiftSettings: [.define("QUIET_TASKS_TESTING")]),
        .testTarget(name: "QuietTasksTests", dependencies: ["QuietTasksLogic"], path: "Tests/QuietTasksTests")
    ]
)
