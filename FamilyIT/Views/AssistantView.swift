import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @AppStorage("largerText") private var largerText = false
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
    private var content: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Take your time.").foregroundStyle(FamilyITColors.muted)
                Spacer()
                Button(action: assistant.returnHome) {
                    Label("New question", systemImage: "plus")
                }.buttonStyle(SecondaryActionButtonStyle())
            }
            .font(.callout)
            Spacer(minLength: 12)
            if let turn = assistant.currentTurn {
                Text(turn.kind == .question ? "TELL ME WHAT YOU SEE" : "ONE STEP AT A TIME")
                    .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(FamilyITColors.accent)
                Text(turn.text)
                    .font(.system(size: largerText ? 38 : 30, weight: .medium))
                    .tracking(-0.5).multilineTextAlignment(.center).lineSpacing(6)
                    .frame(maxWidth: 700, minHeight: 100)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                TalkControl(compact: true)
                if !assistant.heardText.isEmpty {
                    Text("I heard: \(assistant.heardText)").font(.callout).foregroundStyle(FamilyITColors.muted).lineLimit(2)
                }
                ActivityStatusView(activity: assistant.activity)
                if assistant.isPreparing {
                    Button("Cancel response", action: assistant.cancel).buttonStyle(SecondaryActionButtonStyle()).keyboardShortcut(.cancelAction)
                }
                if assistant.canRetry { Button("Try again", action: assistant.retry).buttonStyle(PrimaryActionButtonStyle()) }
                if let action = assistant.pendingAction {
                    VStack(spacing: 16) {
                        Label("YOUR PERMISSION", systemImage: "hand.raised")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(FamilyITColors.accent)
                        Text(action.description).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Continue", action: assistant.confirmAction).buttonStyle(PrimaryActionButtonStyle())
                            Button("Cancel", action: assistant.cancelAction).buttonStyle(SecondaryActionButtonStyle())
                        }
                    }
                    .padding(22).frame(maxWidth: 600)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.8)) }
                    .accessibilityElement(children: .contain)
                } else if turn.kind == .instruction {
                    Button { assistant.didCompleteInstruction() } label: {
                        Label("I did it", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryActionButtonStyle()).disabled(assistant.isPreparing)
                    Text("We’ll wait here until you are done.").font(.callout).foregroundStyle(FamilyITColors.muted)
                }
                ReplyComposer(text: $assistant.typedReply, placeholder: "Or type your answer",
                              actionLabel: "Send answer",
                              disabled: assistant.typedReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              assistant.isPreparing || assistant.hasPendingAction,
                              submit: assistant.submitReply)
                    .frame(maxWidth: 600).padding(.top, 4)
            }
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { assistanceButtons }
                VStack(spacing: 10) { assistanceButtons }
            }
            .disabled(assistant.isPreparing || assistant.hasPendingAction)
        }
        .padding(.horizontal, 36).padding(.vertical, 16)
    }
    @ViewBuilder private var assistanceButtons: some View {
        Button("That didn’t work") { assistant.needsMoreHelp() }.buttonStyle(SecondaryActionButtonStyle())
        Button("Explain differently", action: assistant.explainDifferently)
            .buttonStyle(SecondaryActionButtonStyle()).accessibilityLabel("Explain that differently")
        Button { assistant.repeatInstruction() } label: { Label("Read again", systemImage: "speaker.wave.2") }
            .buttonStyle(SecondaryActionButtonStyle())
    }
}
