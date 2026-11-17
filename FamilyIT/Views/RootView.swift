import SwiftUI

struct RootView: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("largerText") private var largerText = false
    @State private var support: String?
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                HStack {
                    Label(assistant.screen == .home ? "A little help, whenever you need it." : "We’ll work through it together.",
                          systemImage: "lifepreserver")
                        .font(.callout).foregroundStyle(FamilyITColors.muted)
                    Spacer()
                    if !assistant.backendLabel.isEmpty {
                        Text(assistant.backendLabel).font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(FamilyITColors.brand.opacity(0.06), in: Capsule())
                    }
                }
                .padding(.horizontal, 36).padding(.top, 36).padding(.bottom, 12)
                Group {
                    switch assistant.screen {
                    case .home: HomeView()
                    case .assistant: AssistantView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield")
                    Text("Private by design.")
                    Text("Your conversation stays in memory.").foregroundStyle(FamilyITColors.muted)
                }
                .font(.system(size: 12))
                .foregroundStyle(FamilyITColors.brand)
                .padding(.bottom, 22).padding(.top, 12)
            }
            .background(FamilyITColors.warmBackground)
        }
        .background(.ultraThinMaterial)
        .preferredColorScheme(.light)
        .tint(FamilyITColors.brand)
        .foregroundStyle(FamilyITColors.strongText)
        .environment(\.dynamicTypeSize, largerText ? .accessibility1 : .large)
        .sheet(isPresented: Binding(get: { support != nil }, set: { if !$0 { support = nil } })) {
            SupportView(page: support ?? "Help")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: assistant.screen)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .familyGlass(radius: 12, tint: FamilyITColors.brand.opacity(0.1), interactive: false)
                Text("Family IT").font(.system(size: 22, weight: .semibold)).tracking(-0.5)
            }
            .foregroundStyle(FamilyITColors.brand)
            .padding(.bottom, 44)

            Text("YOUR COMPANION").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(FamilyITColors.muted).padding(.leading, 12).padding(.bottom, 12)
            Button(action: assistant.returnHome) {
                sidebarLabel("Get help", icon: "bubble.left")
            }
            .buttonStyle(.plain)
            .familyGlass(radius: 12, tint: FamilyITColors.brand.opacity(0.09))
            .padding(.bottom, 8)
            Menu {
                ForEach(ComputerAction.applications, id: \.self) { name in
                    Button(name) { assistant.propose(ComputerAction(type: .openApplication, application: name)) }
                }
                Divider()
                Button("Sound settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Sound")) }
                Button("Wi-Fi settings") { assistant.propose(ComputerAction(type: .openSettings, element: "Wi-Fi")) }
            } label: { sidebarLabel("Open on my Mac", icon: "macwindow") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .disabled(assistant.isPreparing)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text("One step at a time.").font(.system(size: 17, weight: .medium))
                Text("At your pace. Always.").font(.system(size: 13)).foregroundStyle(FamilyITColors.muted)
            }.padding(.horizontal, 12).padding(.bottom, 24)
            Divider().padding(.horizontal, 10).padding(.bottom, 14)
            Button { support = "Permissions" } label: { sidebarLabel("Permissions", icon: "hand.raised") }.buttonStyle(.plain)
            Button { support = "Help" } label: { sidebarLabel("Help & privacy", icon: "questionmark.circle") }.buttonStyle(.plain)
            SettingsLink { sidebarLabel("Settings", icon: "slider.horizontal.3") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 48).padding(.bottom, 22)
        .frame(width: 230)
        .background {
            if reduceTransparency { Color(red: 0.92, green: 0.94, blue: 0.92) }
            else { Rectangle().fill(.ultraThinMaterial) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(FamilyITColors.brand.opacity(0.07)).frame(width: 1) }
    }
    private func sidebarLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 14, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(FamilyITColors.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
