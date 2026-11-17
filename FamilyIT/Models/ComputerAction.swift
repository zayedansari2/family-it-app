import Foundation

nonisolated enum ActionType: String, Codable, Sendable {
    case none
    case openApplication = "open_application"
    case openSettings = "open_system_settings"
    case focusApplication = "focus_application"
    case inspect = "inspect_accessibility_element"
    case click = "click_accessibility_element"
    case typeText = "type_confirmed_text"
}

nonisolated struct ComputerAction: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(type.rawValue):\(application ?? ""):\(element ?? ""):\(text ?? "")" }
    let type: ActionType
    var application: String? = nil
    var element: String? = nil
    var text: String? = nil
    var requiresConfirmation = true
    static let applications = ["Zoom", "System Settings", "Photos", "Finder", "Safari", "App Store"]
    static let settings = ["General", "Sound", "Wi-Fi", "Accessibility", "Microphone", "Speech Recognition"]

    func validated() throws -> ComputerAction {
        guard requiresConfirmation else { throw GuidanceError.unsafeAction }
        switch type {
        case .none:
            guard application == nil, element == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .openApplication, .focusApplication:
            guard Self.applications.contains(application ?? ""), element == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .openSettings:
            guard Self.settings.contains(element ?? ""), application == nil, text == nil else { throw GuidanceError.unsafeAction }
        case .inspect:
            guard ["Finder", "Photos"].contains(application ?? ""), element == "Focused element", text == nil else { throw GuidanceError.unsafeAction }
        case .click:
            guard ["Finder", "Photos"].contains(application ?? ""), ["Search", "Back"].contains(element ?? ""), text == nil else { throw GuidanceError.unsafeAction }
        case .typeText:
            guard ["Finder", "Photos"].contains(application ?? ""), element == "Search",
                  let text, !text.isEmpty, text.count <= 120,
                  !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw GuidanceError.unsafeAction }
        }
        return self
    }
    var description: String {
        switch type {
        case .none: "No computer action."
        case .openApplication: "Family IT wants to open \(application ?? "")."
        case .focusApplication: "Family IT wants to bring \(application ?? "") to the front."
        case .openSettings: "Family IT wants to open \(element ?? "") settings."
        case .inspect: "Family IT wants to read the focused accessibility label in \(application ?? ""). This stays on your Mac."
        case .click: "Family IT wants to click “\(element ?? "")” in \(application ?? "")."
        case .typeText: "Family IT wants to type in the \(application ?? "") search field: “\(text ?? "")”."
        }
    }
    var safeLogDescription: String {
        switch type {
        case .none: "No computer action."
        case .openApplication: "Requested application opening."
        case .focusApplication: "Brought an application forward."
        case .openSettings: "Opened a confirmed settings page."
        case .inspect: "Read a confirmed accessibility label locally."
        case .click: "Pressed a confirmed navigation control."
        case .typeText: "Entered confirmed search text."
        }
    }
}

nonisolated enum GuidanceError: Error, LocalizedError, Equatable {
    case unavailable, timeout, failed, invalidResponse, unsafeAction, permission, targetChanged
    var errorDescription: String? {
        switch self {
        case .unavailable: "The selected assistant is unavailable. Check its sign-in or choose Demo mode in Settings."
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
