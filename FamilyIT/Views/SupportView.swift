import SwiftUI
import AVFoundation
import Contacts

struct PreferencesView: View {
    @AppStorage("voiceEnabled") private var voiceEnabled = true
    @AppStorage("voiceIdentifier") private var voiceIdentifier = ""
    @AppStorage("voiceSpeed") private var speed = 0.42
    @AppStorage("largerText") private var largerText = false
    @AppStorage("backend") private var backend = Backend.auto.rawValue
    @AppStorage("notesFolder") private var notesFolder = "Family IT"
    @StateObject private var contacts = ContactDirectory()
    @State private var alias = "my son"
    @State private var search = ""
    @State private var detail = ""
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
            Section("AI assistant") {
                Picker("Assistant", selection: $backend) {
                    Text("Automatic (recommended)").tag(Backend.auto.rawValue)
                    Text("Codex").tag(Backend.codex.rawValue)
                    Text("Claude").tag(Backend.claude.rawValue)
                }
                Text("Automatic uses your signed-in Codex or Claude installation. Common actions run locally. Explicit send requests submit immediately; draft requests prepare a preview.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Check AI setup") { Task { detail = await ActionPlanner().diagnostics() } }
            }
            Section("Notes and contacts") {
                TextField("Notes folder", text: $notesFolder)
                TextField("Contact alias (for example, my son)", text: $alias)
                Button("Load contacts") {
                    Task {
                        do { try await contacts.load(); detail = "Choose a person below to remember this alias." }
                        catch { detail = error.localizedDescription }
                    }
                }
                if !contacts.choices.isEmpty {
                    TextField("Search contacts", text: $search)
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(contacts.choices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.prefix(40)) { choice in
                                Button(choice.displayLabel) {
                                    contacts.saveAlias(alias, choice: choice)
                                    detail = "Remembered \(alias) as \(choice.name)."
                                }
                            }
                        }
                    }.frame(height: 100)
                }
            }
            if !detail.isEmpty { Text(detail).font(.callout).textSelection(.enabled) }
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
                        permission("Accessibility", detail: "Reads meeting links in your open Safari invitation and explains Zoom preview controls under your pointer. Page content stays on this Mac.",
                                   enabled: permissions.accessibility)
                        permission("Contacts", detail: "Finds recipients locally by name. Enable access when you want to message a contact.",
                                   enabled: CNContactStore.authorizationStatus(for: .contacts) == .authorized)
                        Text("Meeting notes require Microphone, Speech Recognition, and Screen & System Audio Recording access. Recording starts only when requested; Stop notes ends capture.")
                        Button("Open capture settings") { assistant.propose(.init(type: .openSettings, element: "Screen Recording")) }
                        Text("You can turn any permission off in System Settings → Privacy & Security. Typing always remains available.")
                        Button("Refresh permission status") { permissions.refresh() }
                    } else {
                        Text("Describe what you need. Common requests run immediately on your Mac; Codex or Claude plans unfamiliar wording and complete tasks.")
                        Text("Wi-Fi status and speech transcription are processed locally. Passwords should only be entered in System Settings.")
                        Text("Explicit send requests submit immediately when the recipient is clear. Contact choices appear only when needed. Draft requests prepare a preview without sending.")
                        Text("Meeting audio is transcribed locally in memory. The actual transcript goes to your selected AI for summarization. Notes persist in Apple Notes; raw audio is never saved. ScreenCaptureKit is used for Zoom audio, with no screen images recorded.")
                        ForEach(Array(assistant.timings.suffix(15).enumerated()), id: \.offset) { _, timing in Text(timing).font(.caption) }
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
