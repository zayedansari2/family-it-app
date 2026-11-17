@preconcurrency import AppKit
import ApplicationServices
import AVFoundation
import Speech

@MainActor final class PermissionManager: ObservableObject {
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var speech = SFSpeechRecognizer.authorizationStatus()
    @Published var accessibility = AXIsProcessTrusted()
    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        speech = SFSpeechRecognizer.authorizationStatus()
        accessibility = AXIsProcessTrusted()
    }
    static let settingURLs: [String: String] = [
        "General": "x-apple.systempreferences:com.apple.systempreferences",
        "Sound": "x-apple.systempreferences:com.apple.Sound-Settings.extension",
        "Wi-Fi": "x-apple.systempreferences:com.apple.wifi-settings-extension",
        "Accessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "Microphone": "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "Speech Recognition": "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    ]
}

@MainActor final class SafeComputerExecutor {
    private let launcher = MacAppLauncher()
    private let bundleIDs = ["Finder": "com.apple.finder", "Photos": "com.apple.Photos",
        "Zoom": "us.zoom.xos", "Safari": "com.apple.Safari",
        "App Store": "com.apple.AppStore", "System Settings": "com.apple.systempreferences"]

    /// Opening apps/settings runs directly; deeper actions use the Continue handler.
    func execute(_ proposal: ComputerAction) async throws -> String {
        let action = try proposal.validated()
        switch action.type {
        case .none: return "No action was needed."
        case .openApplication:
            let result = await launcher.openApplication(named: action.application!)
            switch result {
            case .opened: return "The request to open \(action.application!) succeeded. What do you see?"
            case .notFound, .failed: throw GuidanceError.targetChanged
            }
        case .focusApplication:
            guard let id = bundleIDs[action.application!],
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
                  app.activate() else { throw GuidanceError.targetChanged }
            return "The request to bring \(action.application!) forward succeeded. What do you see?"
        case .openSettings:
            guard let value = PermissionManager.settingURLs[action.element!], let url = URL(string: value),
                  NSWorkspace.shared.open(url) else { throw GuidanceError.targetChanged }
            return "The request to open settings succeeded. What do you see?"
        case .inspect, .click, .typeText:
            guard AXIsProcessTrusted() else { throw GuidanceError.permission }
            guard let id = bundleIDs[action.application!],
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                throw GuidanceError.targetChanged
            }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.5)
            if action.type == .inspect {
                guard let focused = value(root, kAXFocusedUIElementAttribute) else { throw GuidanceError.targetChanged }
                let element = unsafeDowncastAX(focused)
                guard string(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole else { throw GuidanceError.targetChanged }
                let label = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) ?? "Unlabeled control"
                // This result is displayed locally, never appended to the AI transcript.
                return "Focused control: \(label.prefix(160)). Tell me what you see."
            }
            // Resolve again immediately before the mutation; never trust an AX pointer from the model.
            let matches = find(root, title: action.element!, depth: 0)
            guard matches.count == 1, let target = matches.first,
                  (value(target, kAXEnabledAttribute) as? Bool) == true else { throw GuidanceError.targetChanged }
            if action.type == .click {
                guard string(target, kAXRoleAttribute) == kAXButtonRole,
                      AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else { throw GuidanceError.targetChanged }
            } else {
                guard string(target, kAXRoleAttribute) == kAXTextFieldRole,
                      string(target, kAXSubroleAttribute) == kAXSearchFieldSubrole else { throw GuidanceError.targetChanged }
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &settable) == .success,
                      settable.boolValue,
                      AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, action.text! as CFString) == .success else {
                    throw GuidanceError.targetChanged
                }
            }
            return "The confirmed action succeeded. What do you see?"
        }
    }
    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private func unsafeDowncastAX(_ value: CFTypeRef) -> AXUIElement { value as! AXUIElement }
    private func string(_ element: AXUIElement, _ attribute: String) -> String? { value(element, attribute) as? String }
    private func find(_ element: AXUIElement, title: String, depth: Int) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        var matches: [AXUIElement] = []
        if string(element, kAXTitleAttribute) == title || string(element, kAXDescriptionAttribute) == title {
            matches.append(element)
        }
        let children = (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for child in children.prefix(150) { matches += find(child, title: title, depth: depth + 1) }
        return matches
    }
}
