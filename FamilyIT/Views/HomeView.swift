import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @AppStorage("largerText") private var largerText = false
    @State private var appQuery = ""

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            VStack(spacing: 24) {
                Text("How can I help?")
                    .font(.system(size: largerText ? 48 : 42, weight: .medium))
                    .tracking(-1.5)
                    .accessibilityAddTraits(.isHeader)
                TalkControl()
                if assistant.activity != .idle {
                    ActivityStatusView(activity: assistant.activity)
                }
                ReplyComposer(text: $assistant.typedProblem, placeholder: "Ask a question or request an action",
                              actionLabel: "Ask", disabled: assistant.typedProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    assistant.begin(problem: assistant.typedProblem)
                }
            }
            .frame(maxWidth: 640)

            HStack(spacing: 16) {
                Rectangle().frame(height: 1)
                Text("or").font(.system(size: 14))
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(FamilyITColors.brand.opacity(0.25))
            .frame(maxWidth: 540)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Find on my Mac", systemImage: "macwindow")
                        .font(.system(size: largerText ? 26 : 22, weight: .medium))
                    Spacer()
                    Menu {
                        Section("Common apps") {
                            ForEach(ComputerAction.applications, id: \.self) { name in
                                Button(name) { assistant.requestOpenApplication(named: name) }
                            }
                        }
                        Section("Settings") {
                            Button("Sound settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Sound")) }
                            Button("Wi-Fi settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Wi-Fi")) }
                        }
                    } label: {
                        Text("Common apps & settings").font(.system(size: 14, weight: .medium))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(assistant.isPreparing)
                }
                ReplyComposer(text: $appQuery, placeholder: "Search by app name", actionLabel: "Open app",
                              disabled: assistant.isPreparing || appQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    assistant.requestOpenApplication(named: appQuery)
                }
            }
            .foregroundStyle(FamilyITColors.brand)
            .padding(24)
            .familyGlass(radius: 26, tint: FamilyITColors.brand.opacity(0.04), interactive: false)
            .frame(maxWidth: 700)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40).padding(.bottom, 24)
    }
}
