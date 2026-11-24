import SwiftUI

struct TelehealthDemoView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @AppStorage("largerText") private var largerText = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 16)
            Image(systemName: assistant.isListening ? "waveform" : "heart.text.clipboard")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(assistant.isListening ? FamilyITColors.accent : FamilyITColors.brand)
            Text(headline)
                .font(.system(size: largerText ? 34 : 29, weight: .semibold))
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)

            if let result = assistant.telehealthDemo.resultTitle {
                VStack(spacing: 9) {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold)).foregroundStyle(FamilyITColors.brand)
                    if let detail = assistant.telehealthDemoResultDetail {
                        Text(detail).font(.body).lineSpacing(5).multilineTextAlignment(.center)
                            .foregroundStyle(FamilyITColors.muted)
                    }
                }
                .padding(18).frame(maxWidth: 390)
                .familyGlass(radius: 20, tint: FamilyITColors.brand.opacity(0.06), interactive: false)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            TalkControl(compact: false)
            if !assistant.heardText.isEmpty {
                Text("I heard: \(assistant.heardText)")
                    .font(.callout.weight(.medium)).foregroundStyle(FamilyITColors.brand)
                    .multilineTextAlignment(.center).frame(maxWidth: 370)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if assistant.isPreparing {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityLabel("Working")
            }
            Spacer(minLength: 18)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.25), value: assistant.telehealthDemo.act)
    }

    private var headline: String {
        if assistant.isListening { return "I’m listening" }
        return assistant.telehealthDemo.resultTitle == nil ? "How can I help?" : "What else can I help with?"
    }
}
