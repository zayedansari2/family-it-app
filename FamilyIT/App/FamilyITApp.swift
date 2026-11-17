import SwiftUI

@main
struct FamilyITApp: App {
    @StateObject private var assistant = VoiceAssistantViewModel()

    var body: some Scene {
        WindowGroup("Family IT") {
            RootView()
                .environmentObject(assistant)
                .frame(minWidth: 800, minHeight: 720)
        }
        .defaultSize(width: 980, height: 820)
        .windowResizability(.contentMinSize)
        Settings {
            PreferencesView().frame(width: 550, height: 430)
        }
    }
}

