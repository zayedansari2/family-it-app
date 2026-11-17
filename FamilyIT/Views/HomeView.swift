import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @AppStorage("largerText") private var largerText = false
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            Text("TECHNOLOGY, A LITTLE SIMPLER")
                .font(.system(size: 10, weight: .semibold)).tracking(2)
                .foregroundStyle(FamilyITColors.accent)
                .padding(.bottom, 18)
            Text("What can I help you with?")
                .font(.system(size: largerText ? 48 : 42, weight: .medium))
                .tracking(-1.5).multilineTextAlignment(.center)
                .frame(maxWidth: 540)
                .accessibilityAddTraits(.isHeader)
            Text("Tell me what’s happening.\nWe’ll take it one step at a time.")
                .font(.system(size: largerText ? 22 : 18))
                .lineSpacing(5).multilineTextAlignment(.center)
                .foregroundStyle(FamilyITColors.muted)
                .padding(.top, 18).padding(.bottom, 30)
            TalkControl()
            Group {
                if assistant.activity == .idle {
                    Text("I’m ready when you are.").font(.system(size: 13)).foregroundStyle(FamilyITColors.muted)
                } else { ActivityStatusView(activity: assistant.activity) }
            }
            .frame(minHeight: 24).padding(.top, 12).padding(.bottom, 28)
            ReplyComposer(text: $assistant.typedProblem, placeholder: "Or type your question here",
                          actionLabel: "Get help",
                          disabled: assistant.typedProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                assistant.begin(problem: assistant.typedProblem)
            }
            .frame(maxWidth: 600)
            HStack {
                Text("A FEW PLACES TO START").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Spacer()
            }
            .foregroundStyle(FamilyITColors.muted).frame(maxWidth: 600)
            .padding(.top, 32).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(assistant.exampleProblems.enumerated()), id: \.offset) { index, problem in
                    Button { assistant.begin(problem: problem) } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Image(systemName: ["speaker.wave.2", "square.grid.2x2", "photo.on.rectangle"][index])
                                    .font(.system(size: 20, weight: .regular))
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).opacity(0.5)
                            }
                            Text(problem).font(.system(size: largerText ? 18 : 15, weight: .medium))
                                .lineSpacing(3).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                        }
                        .foregroundStyle(FamilyITColors.brand)
                        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(FamilyITColors.brand.opacity(0.08)) }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 600)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 36)
    }
}
