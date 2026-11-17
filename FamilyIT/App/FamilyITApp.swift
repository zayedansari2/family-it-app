import SwiftUI

@main
struct FamilyITApp: App {
    @StateObject private var assistant = VoiceAssistantViewModel()

    var body: some Scene {
        WindowGroup("Family IT") {
            RootView()
                .environmentObject(assistant)
                .frame(minWidth: 900, minHeight: 760)
        }
        .defaultSize(width: 1120, height: 880)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        Settings {
            PreferencesView().frame(width: 550, height: 430)
        }
    }
}

