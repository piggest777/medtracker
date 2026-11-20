// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MedTrackerCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MedTrackerCore", targets: ["MedTrackerCore"])],
    targets: [
        .target(name: "MedTrackerCore", path: "Shared", exclude: ["ScreenTime"],
                sources: ["Core", "Notifications"]),
        .testTarget(name: "MedTrackerCoreTests", dependencies: ["MedTrackerCore"], path: "Tests/MedTrackerCoreTests")
    ]
)
