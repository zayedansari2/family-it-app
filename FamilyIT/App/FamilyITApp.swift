import SwiftUI

@main
struct FamilyITApp: App {
    @StateObject private var assistant = VoiceAssistantViewModel()

    var body: some Scene {
        WindowGroup("Family IT") {
            RootView()
                .environmentObject(assistant)
                .frame(minWidth: 400, minHeight: 580)
        }
        .defaultSize(width: 460, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        Settings {
            PreferencesView().frame(width: 600, height: 650)
        }
    }
}

