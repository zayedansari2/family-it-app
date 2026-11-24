@preconcurrency import AppKit
import ApplicationServices
import Foundation

nonisolated struct ActionChoice: Identifiable, Sendable {
    let title: String
    let action: ComputerAction
    var contact: ContactChoice? = nil
    var id: String { action.id }
}
nonisolated struct ActionSelectionNeeded: Error, Sendable {
    let message: String
    let choices: [ActionChoice]
}
nonisolated enum ExecutionResult: Sendable {
    case completed(String)
    case review(ComputerAction, String)
}

@MainActor protocol ActionExecuting: AnyObject {
    var contacts: ContactDirectory { get }
    var recorder: MeetingRecorder { get }
    var summary: String { get }
    func execute(_ action: ComputerAction) async throws -> ExecutionResult
}

@MainActor final class ActionRuntime: ActionExecuting {
    let contacts = ContactDirectory()
    let recorder = MeetingRecorder()
    let planner: any ActionPlanning
    private let executor = SafeComputerExecutor()
    private let wifi = WiFiStatusService()
    private(set) var summary = ""
    private var summarySaved = false
    init(planner: any ActionPlanning) { self.planner = planner }

    func execute(_ proposed: ComputerAction) async throws -> ExecutionResult {
        let action = try proposed.validated()
        switch action.type {
        case .sendMessage, .draftMessage:
            let recipient: ContactChoice
            do { recipient = try await contacts.resolve(action.application!) }
            catch let choice as ContactSelectionNeeded {
                throw ActionSelectionNeeded(message: "Which \(choice.query) should I use?", choices: choice.choices.map {
                    .init(title: $0.displayLabel, action: .init(type: action.type, application: $0.destination, element: nil, text: action.text), contact: $0)
                })
            }
            if action.type == .draftMessage {
                Self.openConversation(recipient.destination)
                return .review(.init(type: .sendMessage, application: recipient.destination, text: action.text),
                    "Draft for \(recipient.name):\n\(action.text!)")
            }
            do {
                try await NativeScripts.run(NativeScripts.message, arguments: [recipient.destination, action.text!])
            } catch {
                throw AssistantFailure("Messages could not confirm submission to \(recipient.name). Check the conversation before trying again; I won’t resend automatically.")
            }
            Self.openConversation(recipient.destination)
            return .completed("Submitted your message to \(recipient.name) in Messages.")
        case .checkWiFi:
            if let url = PermissionManager.settingURLs["Wi-Fi"].flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
            let status = await wifi.currentStatus()
            switch status.state {
            case .connected: return .completed("Connected to \(status.networkName ?? "Wi-Fi").")
            case .disabled: return .completed("Wi-Fi is turned off. Wi-Fi settings is open.")
            case .disconnected: return .completed("Your Mac isn’t connected to a Wi-Fi network. Wi-Fi settings is open.")
            case .unavailable: return .completed("Wi-Fi settings is open. macOS hasn’t shared the network name, so I can’t confirm the connection.")
            }
        case .findMeeting:
            let urls = try await SafariInvitation.meetingLinks()
            guard !urls.isEmpty else { throw AssistantFailure("I couldn’t read a meeting link from the open Safari invitation. Open the invitation or paste its link here.") }
            if urls.count > 1 {
                throw ActionSelectionNeeded(message: "Which meeting link should I open?", choices: urls.map {
                    .init(title: $0.absoluteString, action: .init(type: .openURL, text: $0.absoluteString))
                })
            }
            guard NSWorkspace.shared.open(urls[0]) else { throw GuidanceError.targetChanged }
            return .completed("Found the meeting link in Safari and opened it.")
        case .startRecording:
            guard !recorder.isRecording else { return .completed("I’m already taking meeting notes.") }
            summary = ""; summarySaved = false
            try await recorder.start()
            return .completed("I’m taking notes from your microphone and Zoom. Choose Stop notes when the visit ends.")
        case .stopRecording:
            await recorder.stop()
            try await prepareSummary()
            try await saveSummary()
            return .completed("Saved your visit summary in Notes.\n\(summary)")
        case .shareSummary:
            // Resolve before summarizing or mutating so a name choice can safely resume this action.
            let recipient: ContactChoice
            do { recipient = try await contacts.resolve(action.application!) }
            catch let choice as ContactSelectionNeeded {
                throw ActionSelectionNeeded(message: "Which \(choice.query) should I use?", choices: choice.choices.map {
                    .init(title: $0.displayLabel, action: .init(type: .shareSummary, application: $0.destination), contact: $0)
                })
            }
            if recorder.isRecording { await recorder.stop() }
            try await prepareSummary()
            if !summarySaved { try await saveSummary() }
            return try await execute(.init(type: .sendMessage, application: recipient.destination, text: summary))
        case .createNote:
            try await NativeScripts.createNote(title: action.element!, text: action.text!)
            return .completed("Created “\(action.element!)” in Notes.")
        default:
            return .completed(try await executor.execute(action))
        }
    }

    private func prepareSummary() async throws {
        if summary.isEmpty { summary = try await planner.summarize(recorder.transcript) }
    }
    private func saveSummary() async throws {
        guard !summarySaved else { return }
        try await NativeScripts.createNote(title: "Visit Summary", text: summary)
        summarySaved = true
    }
    private static func openConversation(_ address: String) {
        var url = URLComponents(); url.scheme = "sms"; url.path = address
        if let value = url.url { NSWorkspace.shared.open(value) }
    }
}

@MainActor enum NativeScripts {
    static func run(_ source: String, arguments: [String]) async throws {
        _ = try await CLIProcess().run(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", source, "--"] + arguments, directory: FileManager.default.temporaryDirectory, timeout: 20)
    }
    static func createNote(title: String, text: String) async throws {
        let folder = UserDefaults.standard.string(forKey: "notesFolder") ?? "Family IT"
        func html(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        let body = "<h1>\(html(title))</h1><div>\(html(text))</div>"
        do { try await run(note, arguments: [title, body, folder.isEmpty ? "Family IT" : folder]) }
        catch { throw AssistantFailure("Notes could not confirm creation. Check Notes and Automation permission before trying again.") }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first?.activate()
    }
    static let message = """
    on run argv
        tell application "Messages"
            activate
            set targetService to first service whose service type = iMessage
            set targetBuddy to buddy (item 1 of argv) of targetService
            send (item 2 of argv) to targetBuddy
        end tell
    end run
    """
    static let note = """
    on run argv
        tell application "Notes"
            set targetAccount to default account
            set folderName to item 3 of argv
            if not (exists folder folderName of targetAccount) then
                make new folder at targetAccount with properties {name:folderName}
            end if
            set targetFolder to folder folderName of targetAccount
            set createdNote to make new note at targetFolder with properties {name:(item 1 of argv), body:(item 2 of argv)}
            show createdNote
            activate
        end tell
    end run
    """
}

@MainActor private enum SafariInvitation {
    static func meetingLinks() async throws -> [URL] {
        guard AXIsProcessTrusted() else { throw AssistantFailure("Allow Accessibility access to read the invitation link in Safari, or paste the link here.") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            throw AssistantFailure("Open the invitation in Safari first.")
        }
        app.activate()
        let pid = app.processIdentifier
        return try await Task.detached { try readLinks(pid: pid) }.value
    }
    nonisolated private static func readLinks(pid: pid_t) throws -> [URL] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        func value(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(item, key as CFString, &value)
            return value
        }
        guard let window = (value(root, kAXWindowsAttribute) as? [AXUIElement])?.first else { throw GuidanceError.targetChanged }
        var urls = Set<String>(), budget = 1500
        let deadline = Date().addingTimeInterval(2)
        func visit(_ item: AXUIElement, depth: Int) {
            guard depth < 30, budget > 0, Date() < deadline else { return }; budget -= 1
            if let url = value(item, kAXURLAttribute) as? URL, MeetingLink.isMeeting(url) { urls.insert(url.absoluteString) }
            if let text = value(item, kAXURLAttribute) as? String, let url = URL(string: text), MeetingLink.isMeeting(url) { urls.insert(text) }
            if let children = value(item, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children { visit(child, depth: depth + 1) }
            }
        }
        visit(window, depth: 0)
        return urls.sorted().compactMap(URL.init(string:))
    }
}
