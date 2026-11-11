// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MedTrackerCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MedTrackerCore", targets: ["MedTrackerCore"])],
    targets: [
        .target(name: "MedTrackerCore", path: "Shared/Core"),
        .testTarget(name: "MedTrackerCoreTests", dependencies: ["MedTrackerCore"], path: "Tests/MedTrackerCoreTests")
    ]
)
