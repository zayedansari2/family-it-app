import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @AppStorage("largerText") private var largerText = false
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content } // Small windows / larger text only; never a transcript.
        }
    }
    private var content: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Take your time.").foregroundStyle(FamilyITColors.muted)
                Spacer()
                Button("Start a new question", action: assistant.returnHome)
            }
            Spacer(minLength: 0)
            if let turn = assistant.currentTurn {
                Text(turn.kind == .question ? "TELL ME WHAT YOU SEE" : "ONE STEP AT A TIME")
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(FamilyITColors.accent)
                Text(turn.text)
                    .font(.system(size: largerText ? 38 : 30, weight: .medium))
                    .multilineTextAlignment(.center).lineSpacing(5)
                    .frame(maxWidth: 800, minHeight: 100)
                    .accessibilityAddTraits(.isHeader)
                Button(action: assistant.toggleListening) {
                    Label(assistant.isListening ? "Stop listening" : "Tap to talk",
                          systemImage: assistant.isListening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(assistant.isPreparing || assistant.hasPendingAction)
                .keyboardShortcut(.space, modifiers: [])
                if !assistant.heardText.isEmpty {
                    Text("I heard: \(assistant.heardText)").font(.body).lineLimit(2)
                }
                ActivityStatusView(activity: assistant.activity)
                if assistant.isPreparing {
                    Button("Cancel response", action: assistant.cancel).keyboardShortcut(.cancelAction)
                }
                if assistant.canRetry { Button("Try again", action: assistant.retry).buttonStyle(SecondaryActionButtonStyle()) }
                if let action = assistant.pendingAction {
                    VStack(spacing: 12) {
                        Text(action.description).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                        HStack {
                            Button("Continue", action: assistant.confirmAction).buttonStyle(PrimaryActionButtonStyle())
                            Button("Cancel", action: assistant.cancelAction).buttonStyle(SecondaryActionButtonStyle())
                        }
                    }
                    .padding(16).frame(maxWidth: 760)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .contain)
                } else if turn.kind == .instruction {
                    Button("I did it", action: assistant.didCompleteInstruction)
                        .buttonStyle(PrimaryActionButtonStyle()).disabled(assistant.isPreparing)
                    Text("We’ll wait here until you are done.").font(.callout).foregroundStyle(FamilyITColors.muted)
                }
                HStack {
                    TextField("Or type your answer", text: $assistant.typedReply)
                        .textFieldStyle(.roundedBorder).font(.title3).onSubmit(assistant.submitReply)
                        .accessibilityLabel("Type your answer")
                    Button("Send", action: assistant.submitReply)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(assistant.typedReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  assistant.isPreparing || assistant.hasPendingAction)
                }.frame(maxWidth: 760)
            }
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { assistanceButtons }
                VStack(spacing: 10) { assistanceButtons }
            }
            .disabled(assistant.isPreparing || assistant.hasPendingAction)
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
    }
    @ViewBuilder private var assistanceButtons: some View {
        Button("That didn’t work") { assistant.needsMoreHelp() }.buttonStyle(SecondaryActionButtonStyle())
        Button("Explain that differently", action: assistant.explainDifferently).buttonStyle(SecondaryActionButtonStyle())
        Button("Read again", action: assistant.repeatInstruction).buttonStyle(SecondaryActionButtonStyle())
    }
}
