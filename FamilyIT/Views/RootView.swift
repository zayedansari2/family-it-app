import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("largerText") private var largerText = false
    @State private var support: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Family IT", systemImage: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(action: assistant.returnHome) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Start over")
                .help("Start over")
                Menu {
                    Button("Permissions") { support = "Permissions" }
                    Button("Help & privacy") { support = "Help" }
                    SettingsLink { Text("Settings") }
                } label: {
                    Label("Settings & help", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .foregroundStyle(FamilyITColors.brand)
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 12)
            if assistant.isRecordingMeeting {
                HStack {
                    Label("Taking meeting notes", systemImage: "record.circle.fill").foregroundStyle(.red)
                    Spacer()
                    Button("Stop notes", action: assistant.stopMeetingNotes)
                }.font(.body.weight(.semibold)).padding(.horizontal, 22).padding(.bottom, 8)
                Text(assistant.meetingStatus).font(.caption).padding(.horizontal, 22)
            }
            Group {
                switch assistant.screen {
                case .home: HomeView()
                case .assistant: AssistantView()
                case .telehealthDemo: TelehealthDemoView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FamilyITColors.warmBackground)
        .preferredColorScheme(.light)
        .tint(FamilyITColors.brand)
        .foregroundStyle(FamilyITColors.strongText)
        .environment(\.dynamicTypeSize, largerText ? .accessibility1 : .large)
        .sheet(isPresented: Binding(get: { support != nil }, set: { if !$0 { support = nil } })) {
            SupportView(page: support ?? "Help")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: assistant.screen)
        .background(FloatingWindowConfigurator())
    }
}

private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        window.level = .floating
        window.collectionBehavior.insert(.canJoinAllSpaces)
        let visible = screen.visibleFrame
        let size = NSSize(width: min(460, visible.width - 32), height: min(720, visible.height - 32))
        let origin = NSPoint(x: visible.maxX - size.width - 18,
                             y: visible.midY - size.height / 2)
        if abs(window.frame.width - size.width) > 1 || abs(window.frame.height - size.height) > 1 {
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }
}
