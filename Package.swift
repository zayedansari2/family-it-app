// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "FamilyITCore", platforms: [.macOS(.v14)],
    products: [.library(name: "FamilyITCore", targets: ["FamilyITCore"])],
    targets: [
        .target(name: "FamilyITCore", path: "FamilyIT",
                exclude: ["App", "Views", "Resources"],
                sources: ["Models", "Services"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "FamilyITCoreTests", dependencies: ["FamilyITCore"], path: "Tests")
    ]
)
