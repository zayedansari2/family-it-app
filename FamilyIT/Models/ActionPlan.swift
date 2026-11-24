import Foundation

nonisolated enum MeetingLink {
    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return ((host == "zoom.us" || host.hasSuffix(".zoom.us")) && (url.path.hasPrefix("/j/") || url.path.hasPrefix("/my/"))) ||
            (host == "meet.google.com" && url.path.count > 2) || (host == "teams.microsoft.com" && url.path.contains("meetup-join"))
    }
}

nonisolated struct ActionPlan: Codable, Equatable, Sendable {
    var reply: String
    var actions: [ComputerAction]

    func validated() throws -> Self {
        guard reply.count <= 2000, actions.count <= 8 else { throw GuidanceError.invalidResponse }
        for action in actions { _ = try action.validated() }
        return self
    }

    static func decode(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["reply", "actions"],
              let actions = object["actions"] as? [[String: Any]],
              actions.allSatisfy({ Set($0.keys).isSubset(of: ["type", "application", "element", "text", "requiresConfirmation"]) }) else {
            throw GuidanceError.invalidResponse
        }
        do { return try JSONDecoder().decode(Self.self, from: data).validated() }
        catch { throw GuidanceError.invalidResponse }
    }
}

/// Conservative grammar: complete commands run locally; unfamiliar wording goes to the planner.
nonisolated enum ActionRouter {
    static func route(_ request: String) -> ActionPlan? {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        func plan(_ actions: [ComputerAction]) -> ActionPlan { .init(reply: "", actions: actions) }
        if lower.hasPrefix("don't ") || lower.hasPrefix("do not ") {
            return .init(reply: "Okay, I won’t take that action.", actions: [])
        }
        // Message content is opaque. Never split it into additional commands or open links from it.
        if let match = captures(#"^(?:(?:can|could|would) you (?:please )?|please )?(?:(?:open messages and )?)(text|message|tell|send a message to|draft (?:a message|a text) to|write (?:a message|a text) to)\s+(.+?)(?:\s+(?:that|saying|say)\s+|\s*:\s*)(.+)$"#, text), match.count == 3 {
            let draft = match[0].lowercased().hasPrefix("draft") || match[0].lowercased().hasPrefix("write")
            return plan([.init(type: draft ? .draftMessage : .sendMessage, application: match[1], text: match[2])])
        }
        if let match = captures(#"^(?:(?:can|could) you (?:please )?|please )?(?:send|text|share) (?:the |my )?(?:meeting |visit )?(?:notes|summary) to (.+?)[.!?]*$"#, text) {
            return plan([.init(type: .shareSummary, application: match[0])])
        }
        if lower.range(of: #"\b(stop|finish|end)\b.*\b(recording|taking notes|meeting notes)\b"#, options: .regularExpression) != nil ||
            ["stop recording", "stop taking notes", "finish my notes", "the meeting is over"].contains(lower) {
            return plan([.init(type: .stopRecording)])
        }
        if lower.range(of: #"\b(record|start|take)\b.*\b(meeting|notes|call)\b"#, options: .regularExpression) != nil {
            return plan([.init(type: .startRecording)])
        }
        if let note = captures(#"^(?:(?:can|could) you |please )?(?:create|make|write|save) (?:a )?note (?:called|named|titled) (.+?) (?:saying|with|:)\s*(.+)$"#, text) {
            return plan([.init(type: .createNote, element: note[0], text: note[1])])
        }
        // Only split explicit sequencing outside message/note content.
        if let range = lower.range(of: " and then ") ?? lower.range(of: " then ") {
            let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let end = lower.distance(from: lower.startIndex, to: range.upperBound)
            if let first = route(String(text.prefix(offset))), let second = route(String(text.dropFirst(end))),
               first.actions.count + second.actions.count <= 8 {
                return plan(first.actions + second.actions)
            }
            return nil
        }
        if lower.range(of: #"\b(join|open|find)\b.*\b(meeting|appointment|invite|invitation)\b"#, options: .regularExpression) != nil,
           !lower.contains("http") { return plan([.init(type: .findMeeting)]) }
        if WiFiIntent.matches(text), lower.range(of: #"\b(check|connected|ready|status)\b"#, options: .regularExpression) != nil {
            return plan([.init(type: .checkWiFi)])
        }
        for setting in ComputerAction.settings where lower.contains(setting.lowercased()) && lower.contains("settings") {
            return plan([.init(type: .openSettings, element: setting)])
        }
        if let match = captures(#"^(?:(?:can|could|would) you (?:please )?|please )?(?:open|launch|start|open up)\s+(.+?)(?: for me| please)?[.!?]*$"#, text) {
            let target = match[0]
            if target.hasPrefix("https://") || target.hasPrefix("http://") {
                let action = ComputerAction(type: .openURL, text: target)
                return (try? action.validated()) == nil ? nil : plan([action])
            }
            guard !target.lowercased().contains(" and "), target.count <= 80 else { return nil }
            return plan([.init(type: .openApplication, application: target)])
        }
        if let url = URL(string: text), ["https", "http"].contains(url.scheme ?? "") {
            return plan([.init(type: .openURL, text: text)])
        }
        return nil
    }

    static func authorizesSending(_ request: String) -> Bool {
        let lower = request.lowercased().replacingOccurrences(of: "’", with: "'")
        if let plan = route(request), plan.actions.contains(where: { $0.type == .sendMessage || $0.type == .shareSummary }) {
            return true
        }
        guard !lower.contains("don't"), !lower.contains("do not"), !lower.contains("draft"), !lower.contains("write a message"),
              !["how ", "what ", "why ", "when ", "should "].contains(where: lower.hasPrefix) else { return false }
        return lower.range(of: #"\b(send|text|message|tell|share)\b"#, options: .regularExpression) != nil
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } }
    }
}
