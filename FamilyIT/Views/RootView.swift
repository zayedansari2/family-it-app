import SwiftUI

struct RootView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("largerText") private var largerText = false
    @State private var support: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                Text("FAMILY IT").font(.headline).tracking(3).foregroundStyle(FamilyITColors.brand)
                Spacer()
                Menu("Open…") {
                    ForEach(ComputerAction.applications, id: \.self) { name in
                        Button(name) { assistant.propose(ComputerAction(type: .openApplication, application: name)) }
                    }
                    Divider()
                    Button("Sound settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Sound")) }
                    Button("Wi-Fi settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Wi-Fi")) }
                }.disabled(assistant.isPreparing)
                Button("Permissions") { support = "Permissions" }
                Button("Help & privacy") { support = "Help" }
                SettingsLink { Text("Settings") }
            }
            .font(.body)
            .padding(.horizontal, 32).padding(.vertical, 18)
            Divider()
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
            HStack {
                Text(assistant.backendLabel.isEmpty ? "One step at a time." : assistant.backendLabel)
                Spacer()
                Text("Your conversation stays in memory.")
            }
            .font(.callout).foregroundStyle(FamilyITColors.muted)
            .padding(.horizontal, 32).padding(.vertical, 14)
        }
        .background(FamilyITColors.warmBackground)
        .preferredColorScheme(.light)
        .foregroundStyle(FamilyITColors.strongText)
        .environment(\.dynamicTypeSize, largerText ? .accessibility1 : .large)
        .sheet(isPresented: Binding(get: { support != nil }, set: { if !$0 { support = nil } })) {
            SupportView(page: support ?? "Help")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: assistant.screen)
    }
}

