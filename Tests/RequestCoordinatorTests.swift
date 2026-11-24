import Foundation
import Testing
@testable import FamilyITCore

@MainActor private final class FakePlanner: ActionPlanning {
    let backendLabel = "Test AI"
    var requests: [String] = []
    var response = ActionPlan(reply: "", actions: [])
    func plan(_ request: String, context: String) async throws -> ActionPlan {
        requests.append(request); return response
    }
    func summarize(_ transcript: String) async throws -> String { "Actual test summary" }
}

@MainActor private final class FakeRuntime: ActionExecuting {
    let contacts = ContactDirectory()
    let recorder = MeetingRecorder()
    let summary = ""
    var executed: [ComputerAction] = []
    var chooseRecipient = false
    var failMessage = false
    func execute(_ action: ComputerAction) async throws -> ExecutionResult {
        if chooseRecipient, action.type == .sendMessage, action.application == "John" {
            throw ActionSelectionNeeded(message: "Which John?", choices: [
                .init(title: "John Smith", action: .init(type: .sendMessage, application: "+12065550100", text: action.text))
            ])
        }
        executed.append(action)
        if failMessage, action.type == .sendMessage { throw AssistantFailure("Submission uncertain") }
        if action.type == .draftMessage {
            return .review(.init(type: .sendMessage, application: action.application, text: action.text), "Draft")
        }
        return .completed("Requested action completed")
    }
}

@MainActor private func settle(_ assistant: VoiceAssistantViewModel) async throws {
    for _ in 0..<100 {
        if !assistant.isPreparing { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Coordinator did not settle")
}

@Test @MainActor func followupRequestsUseLocalRouterWithoutAI() async throws {
    let planner = FakePlanner(), runtime = FakeRuntime()
    let assistant = VoiceAssistantViewModel(planner: planner, runtime: runtime, speaksResponses: false, enableHoverGuide: false)
    assistant.begin(problem: "Open Safari")
    try await settle(assistant)
    assistant.typedReply = "Text John that I am joining my appointment"
    assistant.submitReply()
    try await settle(assistant)
    #expect(planner.requests.isEmpty)
    #expect(runtime.executed.map(\.type) == [.openApplication, .sendMessage])
    #expect(runtime.executed.last?.text == "I am joining my appointment")
}

@Test @MainActor func completePlanExecutesOnceWithoutStepPrompts() async throws {
    let planner = FakePlanner(), runtime = FakeRuntime()
    planner.response = .init(reply: "", actions: [
        .init(type: .openApplication, application: "Safari"),
        .init(type: .sendMessage, application: "John", text: "I will be there"),
        .init(type: .openApplication, application: "Notes")
    ])
    let assistant = VoiceAssistantViewModel(planner: planner, runtime: runtime, speaksResponses: false, enableHoverGuide: false)
    assistant.begin(problem: "Let John know I will be there and bring up the apps I need; send that message")
    try await settle(assistant)
    #expect(planner.requests.count == 1)
    #expect(runtime.executed.count == 3)
    #expect(assistant.pendingAction == nil)
}

@Test @MainActor func contactSelectionResumesWithoutRepeatingEarlierActions() async throws {
    let planner = FakePlanner(), runtime = FakeRuntime()
    runtime.chooseRecipient = true
    planner.response = .init(reply: "", actions: [
        .init(type: .openApplication, application: "Safari"),
        .init(type: .sendMessage, application: "John", text: "Hello")
    ])
    let assistant = VoiceAssistantViewModel(planner: planner, runtime: runtime, speaksResponses: false, enableHoverGuide: false)
    assistant.begin(problem: "Send hello to John after bringing up my browser")
    try await settle(assistant)
    let choice = try #require(assistant.actionChoices.first)
    assistant.selectAction(choice)
    try await settle(assistant)
    #expect(runtime.executed.map(\.type) == [.openApplication, .sendMessage])
    #expect(runtime.executed.last?.application == "+12065550100")
}

@Test @MainActor func uncertainSendStopsPlanAndDoesNotOfferAutomaticRetry() async throws {
    let planner = FakePlanner(), runtime = FakeRuntime()
    runtime.failMessage = true
    planner.response = .init(reply: "", actions: [.init(type: .sendMessage, application: "John", text: "Hello"), .init(type: .openApplication, application: "Notes")])
    let assistant = VoiceAssistantViewModel(planner: planner, runtime: runtime, speaksResponses: false, enableHoverGuide: false)
    assistant.begin(problem: "Send John hello and show my notes afterwards")
    try await settle(assistant)
    #expect(runtime.executed.count == 1)
    #expect(!assistant.canRetry)
    assistant.retry()
    #expect(runtime.executed.count == 1)
}

@Test @MainActor func draftRemainsUnsentUntilExplicitConfirmation() async throws {
    let planner = FakePlanner(), runtime = FakeRuntime()
    let assistant = VoiceAssistantViewModel(planner: planner, runtime: runtime, speaksResponses: false, enableHoverGuide: false)
    assistant.begin(problem: "Draft a message to John saying hello")
    try await settle(assistant)
    #expect(runtime.executed.map(\.type) == [.draftMessage])
    #expect(assistant.pendingAction?.type == .sendMessage)
    assistant.confirmAction()
    try await settle(assistant)
    #expect(runtime.executed.map(\.type) == [.draftMessage, .sendMessage])
}
