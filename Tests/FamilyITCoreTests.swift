import Testing
import Foundation
@testable import FamilyITCore

@Test func completionRequiresExplicitConfirmation() {
    for answer in ["I did it", "Done!", "yes I did it", "finished"] {
        #expect(ConversationInput.confirmsCompletion(answer))
    }
    for answer in ["I'm not done", "I haven't finished", "I did it but it failed", "undone", "yes", "I cannot do it"] {
        #expect(!ConversationInput.confirmsCompletion(answer))
    }
}
@Test func rejectsUnknownAndArbitraryActions() {
    for action in ["run_shell", "delete_file", "send_email", "install_software", "applescript", "open_url"] {
        let json = """
        {"reply":"Do it","kind":"instruction","action":{"type":"\(action)","requiresConfirmation":true}}
        """
        #expect(throws: GuidanceError.self) { try GuidanceResponse.decode(Data(json.utf8)) }
    }
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .openApplication, application: "/bin/sh -c whoami").validated()
    }
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .openSettings, element: "Disable Firewall").validated()
    }
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .click, application: "Finder", element: "Delete").validated()
    }
}
@Test func actionsAlwaysNeedConfirmation() throws {
    let action = ComputerAction(type: .openApplication, application: "Zoom")
    #expect(try action.validated() == action)
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .openApplication, application: "Zoom", requiresConfirmation: false).validated()
    }
    #expect(throws: GuidanceError.self) { try ComputerAction(type: .none, text: "hidden command").validated() }
}
@Test func typingIsLimitedAndPrivate() throws {
    let action = ComputerAction(type: .typeText, application: "Finder", element: "Search", text: "holiday photos")
    _ = try action.validated()
    #expect(!action.safeLogDescription.contains("holiday"))
    #expect(action.description.contains("holiday photos"))
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .typeText, application: "Safari", element: "Password", text: "secret").validated()
    }
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .typeText, application: "Finder", element: "Search", text: "hello\nworld").validated()
    }
}
@Test func responseValidationRejectsBrokenPayloads() throws {
    let valid = """
    {"reply":"Open Zoom.","kind":"instruction","action":{"type":"open_application","application":"Zoom","requiresConfirmation":true}}
    """
    #expect(try GuidanceResponse.decode(Data(valid.utf8)).action.application == "Zoom")
    #expect(throws: GuidanceError.self) { try GuidanceResponse.decode(Data(valid.replacingOccurrences(of: "instruction", with: "completion").utf8)) }
    #expect(throws: GuidanceError.self) { try GuidanceResponse.decode(Data("not JSON".utf8)) }
}
@Test func fallbackOrder() {
    #expect(BackendDiscovery.select(.auto, codex: true, claude: true) == .codex)
    #expect(BackendDiscovery.select(.auto, codex: false, claude: true) == .claude)
    #expect(BackendDiscovery.select(.auto, codex: false, claude: false) == .mock)
    #expect(BackendDiscovery.select(.mock, codex: true, claude: true) == .mock)
}
@Test func hiddenActionFieldsAreRejected() {
    let payload = """
    {"reply":"Open Zoom","kind":"instruction","action":{"type":"open_application","application":"Zoom","requiresConfirmation":true,"shell":"do something"}}
    """
    #expect(throws: GuidanceError.self) { try GuidanceResponse.decode(Data(payload.utf8)) }
}
@Test @MainActor func mockDoesNotAssumeCancelledAppOpened() async throws {
    let demo = MockTroubleshootingEngine()
    _ = try await demo.start(problem: "sound")
    _ = try await demo.advance(with: "Mac")
    _ = try await demo.advance(with: "no")
    demo.recordActionOutcome(succeeded: false)
    let turn = try await demo.advance(with: "I cannot open it")
    #expect(turn.kind == .question)
    #expect(turn.text.contains("open now"))
}
@Test @MainActor func mockFlowWaitsForSoundConfirmation() async throws {
    let demo = MockTroubleshootingEngine()
    #expect(try await demo.start(problem: "Zoom sound").kind == .question)
    #expect(try await demo.advance(with: "Mac").text.contains("already open"))
    let open = try await demo.advance(with: "no")
    #expect(open.action?.type == .openApplication)
    #expect(open.action?.requiresConfirmation == true)
    #expect(try await demo.advance(with: "Zoom is open").kind == .instruction)
    #expect(try await demo.advance(with: nil).kind == .instruction)
    #expect(try await demo.advance(with: nil).kind == .question)
    #expect(try await demo.advance(with: "no").kind != .completion)
    _ = try await demo.advance(with: nil)
    #expect(try await demo.advance(with: "yes").kind == .completion)
}
@Test @MainActor func mockOffersAnotherWayAndResets() async throws {
    let demo = MockTroubleshootingEngine()
    _ = try await demo.start(problem: "sound")
    _ = try await demo.advance(with: "Mac")
    _ = try await demo.advance(with: "yes")
    let failed = try await demo.provideMoreHelp(context: "That didn’t work")
    let explained = try await demo.provideMoreHelp(context: "Explain differently")
    #expect(failed.text != explained.text)
    #expect(try await demo.start(problem: "new question").text.contains("Which device"))
}
@Test func cliTimeoutTerminatesChild() async throws {
    let started = Date()
    await #expect(throws: GuidanceError.timeout) {
        _ = try await CLIProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"],
                                      directory: FileManager.default.temporaryDirectory, timeout: 0.15)
    }
    #expect(Date().timeIntervalSince(started) < 3)
}
@Test func cliCancellationTerminatesChild() async throws {
    let runner = CLIProcess()
    let task = Task {
        try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"],
                             directory: FileManager.default.temporaryDirectory)
    }
    try await Task.sleep(for: .milliseconds(120))
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
}
@Test func cancellationBeforeLaunch() async {
    let runner = CLIProcess()
    runner.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"],
                                directory: FileManager.default.temporaryDirectory)
    }
}
@Test func cliStdinPreservesLiteralInput() async throws {
    let input = "hello; $(whoami) \n literal text"
    let output = try await CLIProcess().run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
        input: input, directory: FileManager.default.temporaryDirectory)
    #expect(String(decoding: output, as: UTF8.self) == input)
}
@Test func codexHasRestrictedFixedArguments() {
    let arguments = CodexTroubleshootingEngine.codexArguments(schema: URL(fileURLWithPath: "/tmp/schema"),
                                                             reply: URL(fileURLWithPath: "/tmp/reply"))
    #expect(arguments.contains("--ephemeral"))
    #expect(arguments.contains("features.shell_tool=false"))
    #expect(arguments.contains("features.plugins=false"))
    #expect(arguments.last == "-")
    #expect(!arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
}
/// Opt-in network verification; never required by the offline suite.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FAMILY_IT_LIVE_CODEX"] == "1"))
@MainActor func liveCodexResponse() async throws {
    let engine = CodexTroubleshootingEngine()
    let turn = try await engine.start(problem: "I cannot hear a Zoom meeting. Ask which device I use first.")
    #expect(turn.kind == .question)
    #expect(engine.backendLabel == "Codex")
}
