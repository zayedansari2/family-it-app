import SwiftUI

struct RootView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel

    var body: some View {
        ZStack {
            FamilyITColors.warmBackground
                .ignoresSafeArea()

            switch assistant.screen {
            case .home:
                HomeView()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .assistant:
                AssistantView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .foregroundStyle(FamilyITColors.strongText)
        .animation(.easeInOut(duration: 0.25), value: assistant.screen)
    }
}

