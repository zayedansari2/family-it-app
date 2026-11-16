import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 18)

            HStack(spacing: 14) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(FamilyITColors.brand)
                    .accessibilityHidden(true)

                Text("Family IT")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
            }

            VStack(spacing: 12) {
                Text("What can I help you with?")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Tell me what is happening. We’ll work through it together, one step at a time.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 740)
            }

            Button(action: assistant.toggleListening) {
                VStack(spacing: 10) {
                    Image(systemName: assistant.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 46, weight: .bold))
                    Text(assistant.isListening ? "Tap when finished" : "Tap to talk")
                        .font(.title2.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 180, height: 150)
                .background(assistant.isListening ? Color.red : FamilyITColors.brand)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(assistant.isListening ? "Stop listening" : "Tap to talk")

            ActivityStatusView(activity: assistant.activity)
                .frame(minHeight: 44)

            HStack(spacing: 12) {
                TextField("Or type what is happening", text: $assistant.typedProblem)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FamilyITColors.brand, lineWidth: 2)
                    }
                    .focused($textFieldFocused)
                    .onSubmit { assistant.begin(problem: assistant.typedProblem) }

                Button("Get help") {
                    assistant.begin(problem: assistant.typedProblem)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(assistant.typedProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 760)

            VStack(spacing: 10) {
                Text("Or choose an example")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(assistant.exampleProblems, id: \.self) { problem in
                        Button(problem) {
                            assistant.begin(problem: problem)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: 900)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }
}

