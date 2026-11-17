import SwiftUI
import AVFoundation

struct PreferencesView: View {
    @AppStorage("voiceEnabled") private var voiceEnabled = true
    @AppStorage("voiceIdentifier") private var voiceIdentifier = ""
    @AppStorage("voiceSpeed") private var speed = 0.42
    @AppStorage("largerText") private var largerText = false
    @AppStorage("backend") private var backend = "auto"
    var body: some View {
        Form {
            Section("Reading and speech") {
                Toggle("Read responses aloud", isOn: $voiceEnabled)
                Picker("System voice", selection: $voiceIdentifier) {
                    Text("Best installed English voice").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                    }
                }
                HStack { Text("Speaking speed"); Slider(value: $speed, in: 0.25...0.55); Text(speed < 0.4 ? "Slower" : "Normal") }
                Toggle("Larger text", isOn: $largerText)
            }
            Section("Assistant") {
                Picker("Response provider", selection: $backend) {
                    ForEach(Backend.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Text("Applies to your next question. Automatic checks Codex, then Claude, then Demo mode. A FAMILY_IT_BACKEND environment setting takes precedence.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }
}

struct SupportView: View {
    let page: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @StateObject private var permissions = PermissionManager()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(page == "Permissions" ? "Your permissions" : "How Family IT works").font(.largeTitle.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if page == "Permissions" {
                        permission("Microphone", detail: "Used only while you choose to talk. Audio recordings are never saved.",
                                   enabled: permissions.microphone == .authorized)
                        permission("Speech Recognition", detail: "Turns your spoken words into text. Apple may process speech according to your Mac’s settings.",
                                   enabled: permissions.speech == .authorized)
                        permission("Accessibility", detail: "Needed only to read a focused control or perform a confirmed click or search entry in Finder or Photos. Enable Family IT manually; it cannot grant access itself.",
                                   enabled: permissions.accessibility)
                        Text("You can turn any permission off in System Settings → Privacy & Security. Typing always remains available.")
                        Button("Refresh permission status") { permissions.refresh() }
                    } else {
                        Text("Ask a question by speaking or typing. Family IT gives one small step and waits for you to say “I did it.”")
                        Text("If a step fails, choose “That didn’t work.” Choose “Explain that differently” for another explanation.")
                        Text("Computer actions always show what will happen. Choose Continue to approve that action, or Cancel to leave your Mac unchanged.")
                        Text("Family IT cannot see your screen. This version has no screenshots, camera, or screen-sharing feature.")
                        Text("Codex or Claude receives your typed or transcribed conversation to prepare replies over the internet. Your existing CLI account and its usage limits apply. Demo mode works offline.")
                        Text("Conversation history lives in memory. Temporary response files are removed after each request. No audio recordings, analytics, database, or action text are saved by Family IT. CLI providers may retain account-level operational data.")
                        Text("The demonstration covers Zoom sound on a Mac. It will not solve other questions. Select Demo mode in Settings to try it.")
                        if !assistant.actionLog.isEmpty {
                            Text("Actions this session").font(.headline)
                            ForEach(Array(assistant.actionLog.enumerated()), id: \.offset) { _, description in
                                Text(description)
                            }
                        }
                    }
                }.font(.title3).lineSpacing(4)
            }
        }
        .padding(30).frame(width: 680, height: 620)
        .background(FamilyITColors.warmBackground)
        .onAppear { permissions.refresh() }
        .onChange(of: phase) { _, value in if value == .active { permissions.refresh() } }
    }
    private func permission(_ name: String, detail: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(name) — \(enabled ? "Allowed" : "Not allowed yet")").font(.title2.weight(.semibold))
            Text(detail)
            Button("Open \(name) settings…") {
                dismiss()
                assistant.propose(ComputerAction(type: .openSettings, element: name))
            }
        }
    }
}
