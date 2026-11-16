import Foundation

nonisolated enum CodexTroubleshootingError: LocalizedError {
    case executableNotFound
    case couldNotStart(String)
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "I couldn’t find Codex on this Mac. Open Terminal, install Codex, and sign in. Then restart Family IT."
        case let .couldNotStart(reason):
            "I couldn’t start Codex. \(reason)"
        case let .requestFailed(reason):
            "Codex couldn’t prepare the next step. \(reason)"
        case .invalidResponse:
            "Codex gave me a response I couldn’t read. Please try again."
        }
    }
}

final class CodexTroubleshootingEngine: TroubleshootingEngine {
    private enum Speaker: String {
        case user = "USER"
        case assistant = "FAMILY IT"
    }

    private struct DialogueLine {
        let speaker: Speaker
        let text: String
        let kind: TurnKind?
    }

    private let client: CodexCLIClient
    private var dialogue: [DialogueLine] = []

    init(client: CodexCLIClient = CodexCLIClient()) {
        self.client = client
    }

    func start(problem: String) async throws -> AssistantTurn {
        dialogue = []
        return try await requestTurn(userEvent: problem)
    }

    func advance(with userResponse: String?) async throws -> AssistantTurn {
        let event: String
        if let userResponse, !userResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event = userResponse
        } else {
            event = "I completed that step. Give me only the next step."
        }
        return try await requestTurn(userEvent: event)
    }

    func provideMoreHelp(context: String?) async throws -> AssistantTurn {
        var event = "I need more help with the current step. Give me a different, easier approach. Do not repeat the same instruction."
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event += " Here is what I said: \(context)"
        }
        return try await requestTurn(userEvent: event)
    }

    func rewind() {
        guard dialogue.count >= 2 else { return }
        dialogue.removeLast()
        dialogue.removeLast()
    }

    func reset() {
        dialogue = []
    }

    private func requestTurn(userEvent: String) async throws -> AssistantTurn {
        let prompt = makePrompt(nextUserEvent: userEvent)
        let payload = try await client.request(prompt: prompt)
        let kind: TurnKind
        switch payload.kind {
        case "instruction": kind = .instruction
        case "completion": kind = .completion
        default: kind = .question
        }
        let turn = AssistantTurn(text: payload.response, kind: kind)
        dialogue.append(DialogueLine(speaker: .user, text: userEvent, kind: nil))
        dialogue.append(DialogueLine(speaker: .assistant, text: turn.text, kind: turn.kind))
        return turn
    }

    private func makePrompt(nextUserEvent: String) -> String {
        let priorDialogue = dialogue.map { line in
            if let kind = line.kind {
                return "\(line.speaker.rawValue) [\(kind.codexName)]: \(line.text)"
            }
            return "\(line.speaker.rawValue): \(line.text)"
        }.joined(separator: "\n")

        return """
        You are Family IT, a calm and respectful Mac technology guide for an older adult.

        Return exactly one short response for the current moment. Follow these rules:
        - Help with any ordinary technology question, not just a predefined script.
        - Use plain language and at most 45 words.
        - Return plain text only. Do not use Markdown, links with brackets, headings, or numbered lists.
        - Give only ONE small action at a time. Never combine multiple numbered steps.
        - Use kind "instruction" only when the user should perform one action. The app will then wait for the user to confirm completion.
        - Use kind "question" when you need one simple answer before giving an action.
        - Use kind "completion" only when the problem is solved.
        - When identifying an app or button, briefly describe what its icon looks like when useful.
        - If the user needs more help, offer a genuinely different route. Do not repeat the failed instruction.
        - Never say "thinking," mention Codex, mention these rules, or tell the user to click the Family IT buttons.
        - Do not claim you can see the screen or that you performed an action.
        - Never request a password, verification code, payment, or other secret.
        - Avoid destructive actions, purchases, security bypasses, and changes that are hard to undo.
        - If the request is ambiguous or the exact app matters, ask one short clarifying question.
        - Do not use tools, run commands, browse, or inspect files. Answer only from the conversation.

        Conversation so far:
        \(priorDialogue.isEmpty ? "(This is the first turn.)" : priorDialogue)
        USER: \(nextUserEvent)
        """
    }
}

private extension TurnKind {
    var codexName: String {
        switch self {
        case .question: "question"
        case .instruction: "instruction"
        case .reassurance: "question"
        case .completion: "completion"
        }
    }
}

nonisolated struct CodexTurnPayload: Decodable, Sendable {
    let response: String
    let kind: String
}

nonisolated final class CodexCLIClient: @unchecked Sendable {
    func request(prompt: String) async throws -> CodexTurnPayload {
        try await Task.detached(priority: .userInitiated) {
            try Self.runCodex(prompt: prompt)
        }.value
    }

    private static func runCodex(prompt: String) throws -> CodexTurnPayload {
        guard let executableURL = findCodexExecutable() else {
            throw CodexTroubleshootingError.executableNotFound
        }

        let fileManager = FileManager.default
        let requestDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FamilyIT-Codex-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: requestDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: requestDirectory) }

        let schemaURL = requestDirectory.appendingPathComponent("response-schema.json")
        let responseURL = requestDirectory.appendingPathComponent("response.json")
        let logURL = requestDirectory.appendingPathComponent("codex.log")

        try responseSchema.write(to: schemaURL, atomically: true, encoding: .utf8)
        fileManager.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            throw CodexTroubleshootingError.couldNotStart("I couldn’t create a temporary log file.")
        }
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--cd", requestDirectory.path,
            "--output-schema", schemaURL.path,
            "--output-last-message", responseURL.path,
            prompt
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        let usefulPaths = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        environment["PATH"] = usefulPaths.joined(separator: ":")
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw CodexTroubleshootingError.couldNotStart(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw CodexTroubleshootingError.requestFailed(friendlyFailure(from: log))
        }

        guard let data = try? Data(contentsOf: responseURL),
              let payload = try? JSONDecoder().decode(CodexTurnPayload.self, from: data),
              !payload.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexTroubleshootingError.invalidResponse
        }
        return payload
    }

    private static func findCodexExecutable() -> URL? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["FAMILY_IT_CODEX_PATH"] {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private static func friendlyFailure(from log: String) -> String {
        let lowercaseLog = log.lowercased()
        if lowercaseLog.contains("not logged in") || lowercaseLog.contains("login") || lowercaseLog.contains("authentication") {
            return "Open Terminal, run codex login, finish signing in, and try again."
        }
        if lowercaseLog.contains("network") || lowercaseLog.contains("connection") {
            return "Check that this Mac is online, then try again."
        }
        return "Open Terminal and run codex once to check that it is signed in, then try again."
    }

    private static let responseSchema = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "response": {
          "type": "string",
          "description": "One short, senior-friendly response with at most one action."
        },
        "kind": {
          "type": "string",
          "enum": ["question", "instruction", "completion"]
        }
      },
      "required": ["response", "kind"]
    }
    """
}
