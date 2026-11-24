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
                Text(turn.kind == .question ? "FAMILY IT" : "HERE TO HELP")
                    .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(FamilyITColors.accent)
                Text(turn.text)
                    .font(.system(size: largerText ? 38 : 30, weight: .medium))
                    .tracking(-0.5).multilineTextAlignment(.center).lineSpacing(6)
                    .frame(maxWidth: 700, minHeight: 100)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if assistant.acceptsWiFiInput { TalkControl(compact: true) }
                if assistant.isWiFiFlow {
                    Label(assistant.wifi.statusLabel, systemImage: "wifi")
                        .font(.callout.weight(.medium)).foregroundStyle(FamilyITColors.brand)
                    if !assistant.acceptsWiFiInput {
                        Text("Microphone and text entry are off here. Enter passwords only in System Settings.")
                            .font(.callout).foregroundStyle(FamilyITColors.muted).multilineTextAlignment(.center)
                    }
                    if assistant.wifi.canRetry {
                        Button("Try again", action: assistant.retryWiFi).buttonStyle(PrimaryActionButtonStyle())
                    }
                    if assistant.wifiState == .unavailable {
                        Button("Enable connection checks", action: assistant.allowWiFiChecks)
                            .buttonStyle(SecondaryActionButtonStyle())
                        Text("If access is off, enable Family IT in System Settings → Privacy & Security → Location Services. Then choose Try again and I did it. What does Wi-Fi settings show?")
                            .font(.callout).foregroundStyle(FamilyITColors.muted)
                        VStack(spacing: 8) {
                            Button("It says Connected") { assistant.reportWiFi(.connected) }
                            Button("Network is missing") { assistant.reportWiFi(.missingNetwork) }
                            Button("Password was not accepted") { assistant.reportWiFi(.passwordRejected) }
                        }.buttonStyle(SecondaryActionButtonStyle())
                    }
                    if assistant.wifiState == .differentNetwork {
                        Button("Yes, that is my network", action: assistant.confirmWiFiName)
                            .buttonStyle(PrimaryActionButtonStyle())
                    }
                }
                if !assistant.heardText.isEmpty {
                    Text("I heard: \(assistant.heardText)").font(.callout).foregroundStyle(FamilyITColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(assistant.actionChoices) { choice in
                    Button(choice.title) { assistant.selectAction(choice) }.buttonStyle(SecondaryActionButtonStyle())
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
                        Text(action.type == .sendMessage ? "Send this draft?" : action.description)
                            .font(.title3.weight(.medium)).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Continue", action: assistant.confirmAction).buttonStyle(PrimaryActionButtonStyle())
                            Button("Cancel", action: assistant.cancelAction).buttonStyle(SecondaryActionButtonStyle())
                        }
                    }
                    .padding(22).frame(maxWidth: 600)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.8)) }
                    .accessibilityElement(children: .contain)
                } else if turn.kind == .instruction && assistant.isWiFiFlow {
                    Button { assistant.didCompleteInstruction() } label: {
                        Label("I did it", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryActionButtonStyle()).disabled(assistant.isPreparing)
                    Text("We’ll wait here until you are done.").font(.callout).foregroundStyle(FamilyITColors.muted)
                }
                if assistant.acceptsWiFiInput {
                ReplyComposer(text: $assistant.typedReply, placeholder: assistant.isWiFiFlow ? "Network name only — no password" : "Or type your answer",
                              actionLabel: "Send answer",
                              disabled: assistant.typedReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              assistant.isPreparing || assistant.hasPendingAction,
                              submit: assistant.submitReply)
                    .frame(maxWidth: 600).padding(.top, 4)
                }
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
        Button("I need more help") { assistant.needsMoreHelp() }.buttonStyle(SecondaryActionButtonStyle())
        Button("Explain differently", action: assistant.explainDifferently)
            .buttonStyle(SecondaryActionButtonStyle()).accessibilityLabel("Explain that differently")
        Button { assistant.repeatInstruction() } label: { Label("Read again", systemImage: "speaker.wave.2") }
            .buttonStyle(SecondaryActionButtonStyle())
        if assistant.isWiFiFlow {
            Button("Go back", action: assistant.returnHome).buttonStyle(SecondaryActionButtonStyle())
        }
    }
}
