import Foundation

nonisolated enum ActionType: String, Codable, Sendable {
    case none
    case openApplication = "open_application"
    case openSettings = "open_system_settings"
    case openURL = "open_url"
    case focusApplication = "focus_application"
    case inspect = "inspect_accessibility_element"
    case click = "click_accessibility_element"
    case typeText = "type_confirmed_text"
    case sendMessage = "send_message"
    case createNote = "create_note"
    case draftMessage = "draft_message"
    case checkWiFi = "check_wifi"
    case findMeeting = "find_meeting"
    case startRecording = "start_recording"
    case stopRecording = "stop_recording"
    case shareSummary = "share_summary"
}

nonisolated struct ComputerAction: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(type.rawValue):\(application ?? ""):\(element ?? ""):\(text ?? "")" }
    let type: ActionType
    var application: String? = nil
    var element: String? = nil
    var text: String? = nil
    var requiresConfirmation = true
    static let applications = ["Zoom", "System Settings", "Photos", "Finder", "Safari", "App Store"]
    static let settings = ["General", "Sound", "Wi-Fi", "Accessibility", "Microphone", "Speech Recognition", "Contacts", "Screen Recording"]
    var opensOnly: Bool {
        type == .openApplication || type == .openSettings || type == .openURL || type == .focusApplication
    }

    func validated() throws -> ComputerAction {
        guard requiresConfirmation else { throw GuidanceError.unsafeAction }
        switch type {
        case .none:
            guard application == nil, element == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .openApplication, .focusApplication:
            guard Self.isSafeApplicationName(application), element == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .openSettings:
            guard Self.settings.contains(element ?? ""), application == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .openURL:
            guard application == nil, element == nil, let text, Self.safeWebURL(text) != nil else {
                throw GuidanceError.unsafeAction
            }
        case .inspect:
            guard ["Finder", "Photos"].contains(application ?? ""), element == "Focused element", text == nil else { throw GuidanceError.unsafeAction }
        case .click:
            guard ["Finder", "Photos"].contains(application ?? ""), ["Search", "Back"].contains(element ?? ""), text == nil else { throw GuidanceError.unsafeAction }
        case .typeText:
            guard ["Finder", "Photos"].contains(application ?? ""), element == "Search",
                  let text, !text.isEmpty, text.count <= 120,
                  !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw GuidanceError.unsafeAction }
        case .sendMessage, .draftMessage:
            guard let application, Self.isSafeRecipient(application), element == nil,
                  let text, Self.isSafeText(text, maximum: 1200) else { throw GuidanceError.unsafeAction }
        case .createNote:
            guard application == nil, let element, Self.isSafeText(element, maximum: 120),
                  let text, Self.isSafeText(text, maximum: 5000) else { throw GuidanceError.unsafeAction }
        case .checkWiFi, .findMeeting, .startRecording, .stopRecording:
            guard application == nil, element == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .shareSummary:
            guard let application, Self.isSafeRecipient(application), element == nil, text == nil else { throw GuidanceError.unsafeAction }
        }
        return self
    }

    private static func isSafeApplicationName(_ name: String?) -> Bool {
        guard let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80,
              !name.contains("/"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        return true
    }
    private static func safeWebURL(_ value: String) -> URL? {
        guard value.count <= 2048, let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private static func isSafeRecipient(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "+-().@_ '’").union(.alphanumerics)
        return isSafeText(value, maximum: 120) && value.unicodeScalars.allSatisfy(allowed.contains)
    }
    private static func isSafeText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum &&
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.subtracting(.newlines).contains)
    }
    var description: String {
        switch type {
        case .none: "No computer action."
        case .openApplication: "Family IT wants to open \(application ?? "")."
        case .focusApplication: "Family IT wants to bring \(application ?? "") to the front."
        case .openSettings: "Family IT wants to open \(element ?? "") settings."
        case .openURL: "Family IT wants to open this link: \(text ?? "")"
        case .inspect: "Family IT wants to read the focused accessibility label in \(application ?? ""). This stays on your Mac."
        case .click: "Family IT wants to click “\(element ?? "")” in \(application ?? "")."
        case .typeText: "Family IT wants to type in the \(application ?? "") search field: “\(text ?? "")”."
        case .sendMessage: "Family IT wants to send this message to \(application ?? ""): “\(text ?? "")”."
        case .createNote: "Family IT wants to create a note named “\(element ?? "")” with the text shown here: “\(text ?? "")”."
        case .draftMessage: "Prepare a message to \(application ?? "")."
        case .checkWiFi: "Check the current Wi-Fi connection."
        case .findMeeting: "Open the meeting invitation visible in Safari."
        case .startRecording: "Start meeting notes."
        case .stopRecording: "Stop and summarize meeting notes."
        case .shareSummary: "Share the visit summary with \(application ?? "")."
        }
    }
    var safeLogDescription: String {
        switch type {
        case .none: "No computer action."
        case .openApplication: "Requested application opening."
        case .focusApplication: "Brought an application forward."
        case .openSettings: "Opened a confirmed settings page."
        case .openURL: "Opened a confirmed web link."
        case .inspect: "Read a confirmed accessibility label locally."
        case .click: "Pressed a confirmed navigation control."
        case .typeText: "Entered confirmed search text."
        case .sendMessage: "Sent a confirmed message."
        case .createNote: "Created a confirmed note."
        case .draftMessage: "Prepared a message draft."
        case .checkWiFi: "Checked Wi-Fi locally."
        case .findMeeting: "Opened a meeting link from Safari."
        case .startRecording: "Started meeting notes."
        case .stopRecording: "Stopped meeting notes."
        case .shareSummary: "Submitted the requested summary."
        }
    }
}

nonisolated enum GuidanceError: Error, LocalizedError, Equatable {
    case unavailable, timeout, failed, invalidResponse, unsafeAction, permission, targetChanged
    var errorDescription: String? {
        switch self {
        case .unavailable: "No signed-in AI assistant is available. Sign in to Codex or Claude, then try again."
        case .timeout: "The response took too long. Please try again."
        case .failed: "The assistant couldn’t respond. Check your connection and sign-in, then try again."
        case .invalidResponse: "The response could not be read safely. Please try again."
        case .unsafeAction: "That computer action is not supported. Tell me what you see so we can try a manual step."
        case .permission: "Accessibility access is off. Open Permissions to enable Family IT manually."
        case .targetChanged: "I couldn’t safely find that control. Nothing was changed. Tell me what you see."
        }
    }
}

nonisolated struct GuidanceResponse: Decodable, Sendable {
    let reply: String
    let kind: TurnKind
    let action: ComputerAction
    static func decode(_ data: Data) throws -> GuidanceResponse {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == Set(["reply", "kind", "action"]),
                  let action = object["action"] as? [String: Any],
                  Set(action.keys).isSubset(of: Set(["type", "application", "element", "text", "requiresConfirmation"])) else {
                throw GuidanceError.invalidResponse
            }
            let response = try JSONDecoder().decode(Self.self, from: data)
            guard !response.reply.isEmpty, response.reply.count <= 700,
                  response.kind != .reassurance else { throw GuidanceError.invalidResponse }
            _ = try response.action.validated()
            guard response.action.type == .none || response.kind == .instruction else { throw GuidanceError.unsafeAction }
            return response
        } catch let error as GuidanceError { throw error }
        catch { throw GuidanceError.invalidResponse }
    }
}

nonisolated enum ConversationInput {
    static func confirmsCompletion(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return ["done", "i did it", "yes i did it", "finished", "i finished", "that worked", "it worked", "completed"].contains(words)
    }
}
