import SwiftUI

enum FamilyITColors {
    static let brand = Color(red: 0.04, green: 0.29, blue: 0.46)
    static let brandPressed = Color(red: 0.02, green: 0.20, blue: 0.32)
    static let softBlue = Color(red: 0.89, green: 0.95, blue: 0.98)
    static let warmBackground = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let strongText = Color(red: 0.08, green: 0.12, blue: 0.15)
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(minHeight: 58)
            .background(configuration.isPressed ? FamilyITColors.brandPressed : FamilyITColors.brand)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(FamilyITColors.brand)
            .padding(.horizontal, 24)
            .frame(minHeight: 54)
            .background(configuration.isPressed ? FamilyITColors.softBlue.opacity(0.65) : .white)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FamilyITColors.brand, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ActivityStatusView: View {
    let activity: AssistantActivity

    var body: some View {
        if let label = activity.label {
            Label(label, systemImage: activity.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(activity.isError ? Color.red : FamilyITColors.brand)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(0.95), in: Capsule())
                .accessibilityLabel(label)
        }
    }
}

private extension AssistantActivity {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

