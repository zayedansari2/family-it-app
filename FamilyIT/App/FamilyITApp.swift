import SwiftUI

@main
struct FamilyITApp: App {
    @StateObject private var assistant = VoiceAssistantViewModel()

    var body: some Scene {
        WindowGroup("Family IT") {
            RootView()
                .environmentObject(assistant)
                .frame(minWidth: 760, minHeight: 700)
        }
        .defaultSize(width: 980, height: 820)
        .windowResizability(.contentMinSize)
    }
}

