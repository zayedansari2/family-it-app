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
        "Speech Recognition": "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "Contacts": "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts",
        "Screen Recording": "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
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
        case .checkWiFi, .findMeeting, .startRecording, .stopRecording, .shareSummary, .draftMessage:
            throw GuidanceError.unsafeAction // These capabilities are owned by ActionRuntime.
        case .none: return "No action was needed."
        case .openApplication:
            let result = await launcher.openApplication(named: action.application!)
            switch result {
            case .opened: return "Opened \(action.application!)."
            case .notFound, .failed: throw GuidanceError.targetChanged
            }
        case .focusApplication:
            let result = await launcher.openApplication(named: action.application!)
            switch result {
            case .opened: return "Brought \(action.application!) forward."
            case .notFound, .failed: throw GuidanceError.targetChanged
            }
        case .openSettings:
            guard let value = PermissionManager.settingURLs[action.element!], let url = URL(string: value),
                  NSWorkspace.shared.open(url) else { throw GuidanceError.targetChanged }
            return "Opened \(action.element!) settings."
        case .openURL:
            guard let value = action.text, let url = URL(string: value), NSWorkspace.shared.open(url) else {
                throw GuidanceError.targetChanged
            }
            return "Opened the link."
        case .sendMessage:
            guard await runAppleScript(Self.messagesScript, arguments: [action.application!, action.text!]) else {
                throw GuidanceError.targetChanged
            }
            return "The message was sent."
        case .createNote:
            guard await runAppleScript(Self.notesScript, arguments: [action.element!, action.text!]) else {
                throw GuidanceError.targetChanged
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first?.activate()
            return "The note was created and opened in Notes."
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
    private func runAppleScript(_ source: String, arguments: [String]) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source, "--"] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch { return false }
        }.value
    }
    private static let messagesScript = """
    on run argv
        set recipientAddress to item 1 of argv
        set messageText to item 2 of argv
        tell application "Messages"
            activate
            set targetService to first service whose service type = iMessage
            set targetBuddy to buddy recipientAddress of targetService
            send messageText to targetBuddy
        end tell
    end run
    """
    private static let notesScript = """
    on run argv
        set noteTitle to item 1 of argv
        set noteText to item 2 of argv
        tell application "Notes"
            set targetAccount to default account
            set targetFolder to first folder of targetAccount whose name is "Notes"
            set createdNote to make new note at targetFolder with properties {name:noteTitle, body:noteText}
            show createdNote
            activate
        end tell
    end run
    """
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
