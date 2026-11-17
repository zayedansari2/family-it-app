// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "FamilyITCore", platforms: [.macOS(.v14)],
    products: [.library(name: "FamilyITCore", targets: ["FamilyITCore"])],
    targets: [
        .target(name: "FamilyITCore", path: "FamilyIT",
                exclude: ["App", "Views", "Resources", "Services/WiFiStatusService.swift", "Services/MacAppLauncher.swift",
                          "Services/SafeComputerExecutor.swift", "Services/SpeechRecognitionService.swift",
                          "Services/SpeechSynthesizerService.swift", "Services/VoiceAssistantViewModel.swift"],
                sources: ["Models", "Services/CodexTroubleshootingEngine.swift"]),
        .testTarget(name: "FamilyITCoreTests", dependencies: ["FamilyITCore"], path: "Tests")
    ]
)
