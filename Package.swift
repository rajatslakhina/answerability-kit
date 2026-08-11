// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AnswerabilityKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "AnswerabilityKit", targets: ["AnswerabilityKit"]),
        .executable(name: "AnswerabilityDemo", targets: ["AnswerabilityDemo"])
    ],
    targets: [
        .target(
            name: "AnswerabilityKit",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "AnswerabilityDemo",
            dependencies: ["AnswerabilityKit"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AnswerabilityKitTests",
            dependencies: ["AnswerabilityKit"]
        )
    ]
)
