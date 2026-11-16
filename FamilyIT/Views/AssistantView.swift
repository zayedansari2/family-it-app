import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Family IT", systemImage: "person.2.wave.2.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FamilyITColors.brand)
                Spacer()
                Button("Start over", action: assistant.returnHome)
                    .font(.title3.weight(.semibold))
            }

            Spacer(minLength: 8)

            if let turn = assistant.currentTurn {
                VStack(spacing: 26) {
                    Text(turn.text)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .frame(maxWidth: 820, minHeight: 210)
                        .padding(36)
                        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(FamilyITColors.brand.opacity(0.28), lineWidth: 2)
                        }
                        .accessibilityAddTraits(.isHeader)

                    Button(action: assistant.toggleListening) {
                        Label(
                            assistant.isListening ? "Tap when finished" : "Talk",
                            systemImage: assistant.isListening ? "stop.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel(assistant.isListening ? "Stop listening" : "Talk to Family IT")

                    ActivityStatusView(activity: assistant.activity)
                        .frame(minHeight: 44)

                    if assistant.isListening, !assistant.heardText.isEmpty {
                        Text("I heard: “\(assistant.heardText)”")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    if turn.kind.isInstruction {
                        Button("I did it", action: assistant.didCompleteInstruction)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button("I need more help", action: assistant.needsMoreHelp)
                    .buttonStyle(SecondaryActionButtonStyle())

                Button("Repeat instruction", action: assistant.repeatInstruction)
                    .buttonStyle(SecondaryActionButtonStyle())

                Button("Go back", action: assistant.goBack)
                    .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(32)
    }
}

