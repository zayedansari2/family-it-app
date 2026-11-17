import SwiftUI

struct RootView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("largerText") private var largerText = false
    @State private var support: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: assistant.returnHome) {
                    Label("Family IT", systemImage: "waveform")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Family IT home")
                Spacer()
                Menu {
                    Button("Permissions") { support = "Permissions" }
                    Button("Help & privacy") { support = "Help" }
                    SettingsLink { Text("Settings") }
                } label: {
                    Label("Settings & help", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .foregroundStyle(FamilyITColors.brand)
            .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 16)
            Group {
                switch assistant.screen {
                case .home: HomeView()
                case .assistant: AssistantView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FamilyITColors.warmBackground)
        .preferredColorScheme(.light)
        .tint(FamilyITColors.brand)
        .foregroundStyle(FamilyITColors.strongText)
        .environment(\.dynamicTypeSize, largerText ? .accessibility1 : .large)
        .sheet(isPresented: Binding(get: { support != nil }, set: { if !$0 { support = nil } })) {
            SupportView(page: support ?? "Help")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: assistant.screen)
    }
}
