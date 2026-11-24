import Foundation
import Testing
@testable import FamilyITCore

@Test func messagesPreserveBodyAndTakePrecedenceOverOpeningApps() throws {
    let request = "Open Messages and text John that I'm joining my appointment and then open https://example.com"
    let plan = try #require(ActionRouter.route(request))
    #expect(plan.actions.count == 1)
    #expect(plan.actions[0].type == .sendMessage)
    #expect(plan.actions[0].application == "John")
    #expect(plan.actions[0].text == "I'm joining my appointment and then open https://example.com")
    #expect(ActionRouter.authorizesSending(request))
    #expect(ActionRouter.route("Text John: hello")?.actions.first?.text == "hello")
    #expect(ActionRouter.authorizesSending("Text John that do not send the old draft"))
}

@Test func draftRequestsNeverAuthorizeImmediateSending() throws {
    let plan = try #require(ActionRouter.route("Draft a message to John saying see you tomorrow"))
    #expect(plan.actions.first?.type == .draftMessage)
    for request in ["Draft a text to John", "Don't text John", "Do not send a message", "How do I text John?"] {
        #expect(!ActionRouter.authorizesSending(request))
    }
}

@Test func localTasksCanRunInFlexibleOrderAndSequence() throws {
    let plan = try #require(ActionRouter.route("Open Safari then open Notes"))
    #expect(plan.actions.map(\.application) == ["Safari", "Notes"])
    for request in ["Check if I am connected to Wi-Fi", "Am I connected to a wifi network and ready for my meeting?"] {
        #expect(ActionRouter.route(request)?.actions.first?.type == .checkWiFi)
    }
    #expect(ActionRouter.route("Can you help me join my doctor's meeting?")?.actions.first?.type == .findMeeting)
    #expect(ActionRouter.route("Can you take meeting notes?")?.actions.first?.type == .startRecording)
    #expect(ActionRouter.route("Stop recording")?.actions.first?.type == .stopRecording)
    #expect(ActionRouter.route("Send the notes to my son")?.actions.first?.application == "my son")
    #expect(ActionRouter.route("Please do something unfamiliar") == nil)
}

@Test func plansRejectUnknownCodeAndUnboundedOperations() throws {
    let action = ComputerAction(type: .openApplication, application: "Notes")
    #expect(throws: GuidanceError.self) { try ActionPlan(reply: "", actions: Array(repeating: action, count: 9)).validated() }
    let unknown = #"{"reply":"","actions":[{"type":"run_shell","application":null,"element":null,"text":"ls","requiresConfirmation":true}]}"#
    #expect(throws: GuidanceError.self) { try ActionPlan.decode(Data(unknown.utf8)) }
    let hidden = #"{"reply":"","actions":[{"type":"open_application","application":"Notes","shell":"ls","requiresConfirmation":true}]}"#
    #expect(throws: GuidanceError.self) { try ActionPlan.decode(Data(hidden.utf8)) }
}

@Test func meetingURLsRequireActualMeetingHostsAndPaths() {
    for url in ["https://washington.zoom.us/j/4402768151", "https://meet.google.com/abc-defg-hij"] {
        #expect(MeetingLink.isMeeting(URL(string: url)!))
    }
    for url in ["https://zoom.us.evil.example/j/123", "file:///tmp/meeting", "https://zoom.us/download", "https://user:password@zoom.us/j/123"] {
        #expect(!MeetingLink.isMeeting(URL(string: url)!))
    }
}

@Test func contactMatchingDoesNotGuessAcrossPeopleOrDestinations() {
    let john = ContactChoice(contactID: "1", name: "John Smith", nickname: "Dad", destination: "+12065550100", label: "mobile")
    let johnEmail = ContactChoice(contactID: "1", name: "John Smith", nickname: "Dad", destination: "john@example.com", label: "email")
    let other = ContactChoice(contactID: "2", name: "John Jones", nickname: "", destination: "+12065550101", label: "mobile")
    let choices = [john, johnEmail, other]
    #expect(ContactDirectory.matches(query: "John", choices: choices).count == 3)
    #expect(ContactDirectory.matches(query: "john smith", choices: choices).count == 2)
    #expect(ContactDirectory.matches(query: "Dad", choices: choices).count == 2)
    #expect(ContactDirectory.matches(query: "Jane", choices: choices).isEmpty)
    #expect(ContactDirectory.matches(query: "", choices: choices).isEmpty)
}

@Test @MainActor func emptyTranscriptCannotProduceInventedSummary() async {
    await #expect(throws: AssistantFailure.self) { _ = try await ActionPlanner().summarize("  \n ") }
}

@Test func scriptArgumentsAreDataRatherThanExecutableSource() async throws {
    let literal = "hello \"quoted\"; do shell script \"invalid\"\n$()"
    let source = "on run argv\nreturn item 1 of argv\nend run"
    let output = try await CLIProcess().run(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
        arguments: ["-e", source, "--", literal], directory: FileManager.default.temporaryDirectory, timeout: 5)
    #expect(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .newlines) == literal)
}

@Test func localRouterBenchmark() throws {
    let samples = ["Open Safari", "Check my Wi-Fi", "Text John that I am joining my appointment", "Send the notes to my son"]
    var durations: [Double] = []
    for _ in 0..<250 {
        let start = Date()
        for request in samples { _ = try #require(ActionRouter.route(request)) }
        durations.append(Date().timeIntervalSince(start) / Double(samples.count))
    }
    let p95 = durations.sorted()[Int(Double(durations.count) * 0.95)]
    print("Local router p95: \(String(format: "%.3f", p95 * 1000)) ms per request")
    #expect(p95 < 0.05)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FAMILY_IT_LIVE_PLANNER"] == "1"))
@MainActor func livePlannerReturnsCompleteMessageTask() async throws {
    let planner = ActionPlanner()
    let start = Date()
    let plan = try await planner.plan("Open Messages and text John that I am joining my appointment.", context: "")
    print("\(planner.backendLabel) planner: \(Date().timeIntervalSince(start)) seconds")
    let action = try #require(plan.actions.first(where: { $0.type == .sendMessage }))
    #expect(action.application?.lowercased() == "john")
    #expect(action.text?.contains("appointment") == true)
}
