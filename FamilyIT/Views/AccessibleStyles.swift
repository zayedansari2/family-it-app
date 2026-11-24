import SwiftUI

enum FamilyITColors {
    static let brand = Color(red: 0.12, green: 0.30, blue: 0.27)
    static let muted = Color(red: 0.36, green: 0.42, blue: 0.39)
    static let accent = Color(red: 0.64, green: 0.30, blue: 0.22)
    static let warmBackground = Color(red: 0.97, green: 0.975, blue: 0.96)
    static let strongText = Color(red: 0.13, green: 0.19, blue: 0.17)
}

/// Native Liquid Glass on macOS 26; system material on older supported Macs.
/// An opaque surface preserves contrast with Reduce Transparency enabled.
private struct FamilyGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    let tint: Color
    let interactive: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.white, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(FamilyITColors.brand.opacity(0.18)) }
        } else if #available(macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: RoundedRectangle(cornerRadius: radius))
            } else {
                content.glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: radius))
            }
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.75)) }
        }
    }
}

extension View {
    func familyGlass(radius: CGFloat = 18, tint: Color = .clear, interactive: Bool = true) -> some View {
        modifier(FamilyGlass(radius: radius, tint: tint, interactive: interactive))
    }
}

struct PrimaryActionButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            Button(action: configuration.trigger) {
                configuration.label.font(.title3.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
            .tint(FamilyITColors.brand).controlSize(.large)
        } else {
            Button(action: configuration.trigger) {
                configuration.label.font(.title3.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(FamilyITColors.brand).controlSize(.large)
        }
    }
}

struct SecondaryActionButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            Button(action: configuration.trigger) {
                configuration.label.font(.body.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 8)
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            Button(action: configuration.trigger) {
                configuration.label.font(.body.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }
}

struct TalkControl: View {
    @EnvironmentObject private var assistant: VoiceAssistantViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    var body: some View {
        Button(action: assistant.toggleListening) {
            VStack(spacing: compact ? 12 : 16) {
                Image(systemName: assistant.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: compact ? 26 : 36, weight: .medium))
                    .foregroundStyle(assistant.isListening ? FamilyITColors.accent : FamilyITColors.brand)
                    .frame(width: compact ? 74 : 112, height: compact ? 74 : 112)
                    .familyGlass(radius: 60, tint: FamilyITColors.brand.opacity(0.10))
                    .shadow(color: FamilyITColors.brand.opacity(0.10), radius: 22, x: 0, y: 10)
                    .padding(8)
                    .overlay { Circle().strokeBorder(FamilyITColors.brand.opacity(0.08), lineWidth: 1) }
                Text(assistant.isListening ? "Tap to finish" : "Tap to talk")
                    .font(.system(size: compact ? 19 : 22, weight: .semibold))
                    .foregroundStyle(FamilyITColors.brand)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .accessibilityLabel(assistant.isListening ? "Stop listening" : "Tap to talk")
        .disabled(assistant.isPreparing || assistant.hasPendingAction)
        .opacity(assistant.isPreparing || assistant.hasPendingAction ? 0.4 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: assistant.isListening)
    }
}

struct ReplyComposer: View {
    @Binding var text: String
    let placeholder: String
    let actionLabel: String
    let disabled: Bool
    let submit: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 14) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.system(size: 18))
                .focused($focused).onSubmit { if !disabled { submit() } }
                .accessibilityLabel(placeholder)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(FamilyITColors.brand)
                    .familyGlass(radius: 21, tint: FamilyITColors.brand.opacity(0.12))
            }
            .buttonStyle(.plain).disabled(disabled)
            .opacity(disabled ? 0.35 : 1)
            .accessibilityLabel(actionLabel).help(actionLabel)
        }
        .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 8)
        .familyGlass(radius: 30, interactive: false)
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(FamilyITColors.brand.opacity(focused ? 0.45 : 0.12), lineWidth: focused ? 2 : 1) }
    }
}

struct ActivityStatusView: View {
    let activity: AssistantActivity
    var body: some View {
        if let label = activity.label {
            HStack(spacing: 9) {
                if activity == .preparing { ProgressView().controlSize(.small) }
                else { Image(systemName: activity.symbolName) }
                if activity != .preparing { Text(label).fixedSize(horizontal: false, vertical: true) }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(isError ? FamilyITColors.accent : FamilyITColors.muted)
            .multilineTextAlignment(.center).accessibilityLabel(label)
        }
    }
    private var isError: Bool { if case .error = activity { true } else { false } }
}
