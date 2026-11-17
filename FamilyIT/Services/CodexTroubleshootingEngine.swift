import Foundation
import Darwin

nonisolated enum Backend: String, CaseIterable, Sendable {
    case auto, codex, claude, mock
    var label: String {
        switch self {
        case .auto: "Automatic"
        case .codex: "Codex"
        case .claude: "Claude"
        case .mock: "Demo mode"
        }
    }
}

/// One invocation per runner. Cancellation covers both launch and running states.
/// stdout is drained on a separate queue; no shell or untrusted arguments.
nonisolated final class CLIProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { stop(process) }
    }
    private func stop(_ process: Process) {
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
    func run(executable: URL, arguments: [String], input: String = "", directory: URL,
             timeout: TimeInterval = 60) async throws -> Data {
        try await withTaskCancellationHandler {
            try await Task.detached { [self] in
                try runBlocking(executable: executable, arguments: arguments, input: input, directory: directory, timeout: timeout)
            }.value
        } onCancel: { self.cancel() }
    }
    private func runBlocking(executable: URL, arguments: [String], input: String,
                             directory: URL, timeout: TimeInterval) throws -> Data {
        let child = Process(), stdin = Pipe(), output = Pipe()
        let collector = OutputCollector()
        let drained = DispatchSemaphore(value: 0)
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = directory
        child.standardInput = stdin
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for key in Array(env.keys) where key.hasSuffix("API_KEY") || key.hasSuffix("TOKEN") { env.removeValue(forKey: key) }
        child.environment = env
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = child
        do { try child.run() } catch { lock.unlock(); throw GuidanceError.unavailable }
        lock.unlock()
        DispatchQueue.global().async {
            while true {
                let bytes = output.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                collector.append(bytes)
            }
            drained.signal()
        }
        // Keep input writing off the supervision thread so deadlines still work.
        DispatchQueue.global().async {
            try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while child.isRunning {
            lock.lock(); let wasCancelled = cancelled; lock.unlock()
            if wasCancelled || Date() >= deadline {
                if child.isRunning { stop(child) }
                child.waitUntilExit()
                if wasCancelled { throw CancellationError() }
                throw GuidanceError.timeout
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        child.waitUntilExit()
        _ = drained.wait(timeout: .now() + 2)
        lock.lock(); let wasCancelled = cancelled; process = nil; lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard child.terminationStatus == 0 else { throw GuidanceError.failed }
        return collector.data
    }
}
private nonisolated final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if bytes.count + data.count <= 2_000_000 { bytes.append(data) }
    }
}

nonisolated enum BackendDiscovery {
    static func executable(_ backend: Backend) -> URL? {
        guard backend == .codex || backend == .claude else { return nil }
        let fm = FileManager.default
        let paths = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(backend.rawValue)").path,
                     "/opt/homebrew/bin/\(backend.rawValue)", "/usr/local/bin/\(backend.rawValue)"]
        return paths.first(where: fm.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
    static func authenticated(_ backend: Backend) async -> Bool {
        guard let url = executable(backend) else { return false }
        do {
            let data = try await CLIProcess().run(executable: url,
                arguments: backend == .codex ? ["login", "status"] : ["auth", "status", "--json"],
                directory: FileManager.default.temporaryDirectory, timeout: 8)
            if backend == .claude {
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return object?["loggedIn"] as? Bool == true
            }
            return true
        } catch { return false }
    }
    static func select(_ requested: Backend, codex: Bool, claude: Bool) -> Backend {
        if requested != .auto { return requested }
        return codex ? .codex : claude ? .claude : .mock
    }
}

@MainActor final class CodexTroubleshootingEngine: TroubleshootingEngine {
    private(set) var backendLabel = "Connecting…"
    private var selected: Backend?
    private var history: [String] = []
    private let demo = MockTroubleshootingEngine()
    private var generation = UUID()
    func start(problem: String) async throws -> AssistantTurn {
        reset()
        let requested = Backend(rawValue: ProcessInfo.processInfo.environment["FAMILY_IT_BACKEND"]
            ?? UserDefaults.standard.string(forKey: "backend") ?? "auto") ?? .auto
        if requested == .auto {
            let codex = await BackendDiscovery.authenticated(.codex)
            try Task.checkCancellation()
            let claude = codex ? false : await BackendDiscovery.authenticated(.claude)
            selected = BackendDiscovery.select(requested, codex: codex, claude: claude)
        } else { selected = requested }
        backendLabel = selected?.label ?? "Demo mode"
        if selected == .mock { return try await demo.start(problem: problem) }
        return try await request(problem)
    }
    func advance(with userResponse: String?) async throws -> AssistantTurn {
        if selected == nil { return try await start(problem: userResponse ?? "I need help with my Mac.") }
        if selected == .mock { return try await demo.advance(with: userResponse) }
        return try await request(userResponse ?? "I completed the current step. Give only the next step.")
    }
    func provideMoreHelp(context: String?) async throws -> AssistantTurn {
        if selected == nil { return try await start(problem: context ?? "I need help with my Mac.") }
        if selected == .mock { return try await demo.provideMoreHelp(context: context) }
        return try await request("The current step is NOT completed. \(context ?? "Explain it using a different approach.")")
    }
    func rewind() {
        if selected == .mock { demo.rewind() }
        else if history.count >= 2 { history.removeLast(2) }
    }
    func recordActionOutcome(succeeded: Bool) {
        if selected == .mock { demo.recordActionOutcome(succeeded: succeeded) }
        else { history.append("LOCAL ACTION: \(succeeded ? "The confirmed request succeeded." : "The action was cancelled or failed.") Ask what the user sees. Do not assume the original problem is solved.") }
    }
    func reset() { generation = UUID(); history = []; selected = nil; demo.reset() }
    private func request(_ event: String) async throws -> AssistantTurn {
        guard let selected, let executable = BackendDiscovery.executable(selected) else { throw GuidanceError.unavailable }
        let ticket = generation
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyIT-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = Self.instructions + "\nConversation:\n" + history.joined(separator: "\n") + "\nUSER: " + event
        let data: Data
        if selected == .codex {
            let schema = directory.appendingPathComponent("schema.json"), reply = directory.appendingPathComponent("reply.json")
            try Self.schema.write(to: schema, atomically: true, encoding: .utf8)
            _ = try await CLIProcess().run(executable: executable, arguments: Self.codexArguments(schema: schema, reply: reply),
                                          input: prompt, directory: directory)
            data = try Data(contentsOf: reply)
        } else {
            let output = try await CLIProcess().run(executable: executable, arguments: [
                "-p", "--safe-mode", "--tools", "", "--permission-mode", "plan", "--no-session-persistence",
                "--disable-slash-commands", "--no-chrome", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                "--output-format", "json", "--json-schema", Self.schema
            ], input: prompt, directory: directory)
            let envelope = try JSONSerialization.jsonObject(with: output) as? [String: Any]
            guard let object = envelope?["structured_output"] else { throw GuidanceError.invalidResponse }
            data = try JSONSerialization.data(withJSONObject: object)
        }
        try Task.checkCancellation()
        guard ticket == generation else { throw CancellationError() }
        let response = try GuidanceResponse.decode(data)
        history.append("USER: \(event)")
        history.append("ASSISTANT: \(String(decoding: data, as: UTF8.self))")
        return AssistantTurn(text: response.reply, kind: response.kind, action: response.action.type == .none ? nil : response.action)
    }
    nonisolated static func codexArguments(schema: URL, reply: URL) -> [String] {
        ["exec", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
         "--sandbox", "read-only", "--output-schema", schema.path, "--output-last-message", reply.path,
         "-c", "web_search=\"disabled\"", "-c", "features.view_image=false",
         "-c", "features.shell_tool=false", "-c", "features.unified_exec=false",
         "-c", "features.apply_patch_freeform=false", "-c", "features.plugins=false",
         "-c", "features.apps=false", "-c", "features.computer_use=false",
         "-c", "features.image_generation=false", "-c", "features.code_mode=false",
         "-c", "features.browser_use=false", "-c", "features.in_app_browser=false",
         "-c", "features.hooks=false", "-c", "features.codex_hooks=false",
         "-c", "features.js_repl=false", "-c", "agents.enabled=false",
         "-c", "features.multi_agent=false", "-c", "features.multi_agent_v2=false",
         "-c", "analytics.enabled=false", "-c", "history.persistence=\"none\"", "-"]
    }
    nonisolated static let schema = """
    {"type":"object","additionalProperties":false,"required":["reply","kind","action"],
    "properties":{"reply":{"type":"string"},"kind":{"type":"string","enum":["instruction","question","completion"]},
    "action":{"type":"object","additionalProperties":false,"required":["type","application","element","text","requiresConfirmation"],
    "properties":{"type":{"type":"string","enum":["none","open_application","open_system_settings","focus_application","inspect_accessibility_element","click_accessibility_element","type_confirmed_text"]},
    "application":{"type":["string","null"]},"element":{"type":["string","null"]},"text":{"type":["string","null"]},"requiresConfirmation":{"type":"boolean"}}}}}
    """
    nonisolated static let instructions = """
    You are Family IT, a respectful technology guide for older adults. Return structured JSON only.
    Use at most 45 words and ONE small action OR one clarifying question. Ask which device and app
    the user uses before device-specific instructions, unless already clear. Remember tried approaches.
    Wait for explicit completion before advancing. Failure means try a different route.
    Confirm the ORIGINAL problem is solved before completion. No praise like "Good job".
    Never claim screen visibility. Never request passwords, verification codes, recovery keys or secrets.
    Never propose purchases, installation by automation, deletion, messages, email, security bypasses
    or terminal commands. Never use tools. Plain text, no Markdown. Describe icons when useful.
    Optional actions require confirmation. No shell, code or AppleScript.
    Applications: Zoom, System Settings, Photos, Finder, Safari, App Store.
    Settings in element: General, Sound, Wi-Fi, Accessibility, Microphone, Speech Recognition.
    Inspect only "Focused element" in Finder or Photos. Click only Search or Back in those apps.
    Type only nonsecret exact text in the Search field of Finder or Photos, maximum 120 characters.
    Use none for manual guidance; irrelevant fields must be null, requiresConfirmation always true.
    Action results do not prove the problem is solved. Ask what the user sees after an action.
    """
}

@MainActor final class MockTroubleshootingEngine: TroubleshootingEngine {
    let backendLabel = "Demo mode"
    private var step = 0
    private var checkpoints: [Int] = []
    private var openingSucceeded = false
    func recordActionOutcome(succeeded: Bool) { openingSucceeded = succeeded }
    func start(problem: String) async throws -> AssistantTurn {
        reset()
        return AssistantTurn(text: "Let’s try the Zoom sound demonstration. Which device are you using: a Mac, an iPhone, or something else?", kind: .question)
    }
    func advance(with userResponse: String?) async throws -> AssistantTurn {
        checkpoints.append(step)
        if step == 0 {
            guard (userResponse ?? "").lowercased().contains("mac") else {
                return AssistantTurn(text: "This demonstration covers a Mac. Are you using a Mac?", kind: .question)
            }
            step = 1
            return AssistantTurn(text: "Is the Zoom meeting window already open?", kind: .question)
        }
        if step == 1 {
            if (userResponse ?? "").lowercased().contains("yes") { step = 3 }
            else {
                step = 2
                return AssistantTurn(text: "We can open Zoom together. Review the request below.", kind: .instruction,
                                     action: ComputerAction(type: .openApplication, application: "Zoom"))
            }
        } else if step == 2 {
            guard openingSucceeded || ["yes", "zoom is open", "it is open"].contains((userResponse ?? "").lowercased()) else {
                return AssistantTurn(text: "Is the Zoom meeting window open now?", kind: .question)
            }
            step = 3
        }
        else if step == 3 {
            step = 4
            return AssistantTurn(text: "Under “Select a Speaker,” choose your Mac’s built-in speakers.", kind: .instruction)
        } else if step == 4 {
            step = 5
            return AssistantTurn(text: "Can you hear the meeting now?", kind: .question)
        } else if step == 5 {
            if ["yes", "yes i can", "it works", "i can hear it", "that worked"].contains((userResponse ?? "").lowercased()) {
                step = 6
                return AssistantTurn(text: "The meeting sound is working. You can return here whenever you need help.", kind: .completion)
            }
            return try await provideMoreHelp(context: "failed")
        }
        return AssistantTurn(text: "In Zoom, click the small upward arrow beside the microphone at the bottom left.", kind: .instruction)
    }
    func provideMoreHelp(context: String?) async throws -> AssistantTurn {
        checkpoints.append(step)
        if context?.contains("action") == true { return AssistantTurn(text: "What do you see in the window now?", kind: .question) }
        if context?.contains("differently") == true {
            if step <= 1 {
                return AssistantTurn(text: step == 0 ? "Are you using a Mac computer, a phone, or a tablet?" : "Can you see a Zoom meeting window on your screen?", kind: .question)
            }
            return AssistantTurn(text: "Look at the bottom-left corner of Zoom. Beside the microphone picture is a tiny upward arrow. Click that arrow.", kind: .instruction)
        }
        if step <= 2 {
            return AssistantTurn(text: "That’s okay. Tell me what you see on your screen right now.", kind: .question)
        }
        step = 4
        return AssistantTurn(text: "Let’s try another way. Press the volume-up key on your keyboard three times. Its picture is a speaker with sound waves.", kind: .instruction)
    }
    func rewind() { if let previous = checkpoints.popLast() { step = previous } }
    func reset() { step = 0; checkpoints = []; openingSucceeded = false }
}
