// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TallyCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "TallyCore", targets: ["TallyCore"])
    ],
    targets: [
        .target(name: "TallyCore", resources: [.process("Resources")]),
        .testTarget(name: "TallyCoreTests", dependencies: ["TallyCore"])
    ]
)
