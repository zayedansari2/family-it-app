import Testing
import Foundation
@testable import FamilyITCore

private actor FakeWiFi: WiFiStatusProviding {
    let status: WiFiStatus
    private(set) var calls = 0
    init(_ status: WiFiStatus) { self.status = status }
    func currentStatus() async -> WiFiStatus { calls += 1; return status }
}

@Test func wifiStatusMappingDoesNotMistakeRedactionForDisconnection() {
    #expect(WiFiStatus.map(hasInterface: false, powered: false, associated: nil, ssid: nil).state == .unavailable)
    #expect(WiFiStatus.map(hasInterface: true, powered: false, associated: nil, ssid: nil).state == .disabled)
    #expect(WiFiStatus.map(hasInterface: true, powered: true, associated: false, ssid: nil).state == .disconnected)
    #expect(WiFiStatus.map(hasInterface: true, powered: true, associated: nil, ssid: nil).state == .unavailable)
    #expect(WiFiStatus.map(hasInterface: true, powered: true, associated: true, ssid: "Guest").networkName == "Guest")
}

@Test func wifiIntentHandlesExamplesLocally() {
    for request in ["Connect me to Guest Wi-Fi", "Help me join the guest network", "Open Wi-Fi settings", "I need help connecting to Wi-Fi"] {
        #expect(WiFiIntent.isRequest(request))
    }
    #expect(WiFiIntent.networkName(in: "Help me connect to Guest Wi‑Fi.") == "Guest Wi‑Fi")
    #expect(WiFiIntent.networkName(in: "Help me join the guest network") == "guest")
    #expect(WiFiIntent.networkName(in: "I need help connecting to Wi-Fi") == nil)
    #expect(!WiFiIntent.isRequest("How do I find my photos?"))
}

@Test @MainActor func wifiWaitsForExplicitDoneAndMatchesNormalizedNames() async {
    let flow = WiFiFlow()
    let provider = FakeWiFi(.init(state: .connected, networkName: "  GUEST   Wi-Fi "))
    flow.start("Connect me to Guest Wi-Fi")
    await flow.verify(using: provider)
    #expect(await provider.calls == 0)
    flow.settingsOpened(succeeded: true)
    #expect(flow.state == .waitingForUser)
    #expect(flow.turn.kind == .instruction)
    #expect(await provider.calls == 0)
    await flow.verify(using: provider)
    #expect(await provider.calls == 1)
    #expect(flow.state == .connected)
    #expect(flow.turn.kind == .completion)
    await flow.verify(using: provider)
    #expect(await provider.calls == 1)
}

@Test @MainActor func wifiDifferentPunctuationRequiresUserConfirmation() async {
    let flow = WiFiFlow()
    flow.start("Connect to Guest Wi-Fi")
    flow.settingsOpened(succeeded: true)
    await flow.verify(using: FakeWiFi(.init(state: .connected, networkName: "Guest-WiFi")))
    #expect(flow.state == .differentNetwork)
    #expect(flow.turn.kind == .question)
    #expect(flow.turn.text.contains("Guest-WiFi"))
    flow.confirmObservedNetwork()
    #expect(flow.state == .connected)
    #expect(flow.networkName == "Guest-WiFi")
}

@Test @MainActor func wifiFailureStatesAndRetry() async {
    for status in [WiFiStatus(state: .disconnected), .init(state: .disabled), .init(state: .unavailable), .init(state: .connected)] {
        let flow = WiFiFlow()
        flow.start("Connect to Guest")
        flow.settingsOpened(succeeded: true)
        await flow.verify(using: FakeWiFi(status))
        #expect(flow.state == (status.state == .disabled || status.state == .disconnected ? .notConnected : .unavailable))
        #expect(flow.turn.kind == .question)
        #expect(flow.canRetry)
        flow.retry()
        #expect(flow.state == .openingWiFiSettings)
        flow.settingsOpened(succeeded: true)
        #expect(flow.state == .waitingForUser)
    }
}

@Test @MainActor func wifiMissingNameAndOpeningFailure() {
    let flow = WiFiFlow()
    flow.start("I need help connecting to Wi-Fi")
    #expect(flow.state == .askingForNetworkName)
    #expect(flow.turn.kind == .question)
    flow.acceptName("Guest")
    #expect(flow.networkName == "Guest")
    flow.settingsOpened(succeeded: false)
    #expect(flow.state == .openFailed)
    #expect(flow.canRetry)
    flow.retry()
    flow.settingsOpened(succeeded: true)
    flow.moreHelp()
    #expect(flow.state == .waitingForUser)
    flow.reset()
    #expect(!flow.active)
    #expect(flow.networkName == nil)
    #expect(!flow.canRetry)
}

@Test @MainActor func credentialLikeRequestsStayOutOfRetainedFlowAndActions() throws {
    let secret = "my password is hello123"
    #expect(WiFiIntent.isSensitive(secret))
    #expect(WiFiIntent.networkName(in: "Connect to Guest, \(secret)") == nil)
    let flow = WiFiFlow()
    flow.start("Connect to Guest, \(secret)")
    #expect(flow.networkName == nil)
    #expect(!flow.turn.text.contains("hello123"))
    #expect(flow.turn.text == WiFiIntent.privacyMessage)
    flow.acceptName(secret)
    #expect(flow.networkName == nil)
    #expect(!flow.turn.text.contains("hello123"))
    let action = try WiFiFlow.settingsAction.validated()
    #expect(action.type == .openSettings)
    #expect(action.text == nil)
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .typeText, application: "System Settings", element: "Password", text: "hello123").validated()
    }
    #expect(throws: GuidanceError.self) {
        try ComputerAction(type: .click, application: "System Settings", element: "Connect").validated()
    }
}

private actor DelayedWiFi: WiFiStatusProviding {
    private var continuation: CheckedContinuation<WiFiStatus, Never>?
    func currentStatus() async -> WiFiStatus {
        await withCheckedContinuation { continuation = $0 }
    }
    var waiting: Bool { continuation != nil }
    func finish() { continuation?.resume(returning: .init(state: .connected, networkName: "Guest")); continuation = nil }
}

@Test @MainActor func goingBackDiscardsLateWiFiChecks() async {
    let flow = WiFiFlow()
    let provider = DelayedWiFi()
    flow.start("Connect to Guest"); flow.settingsOpened(succeeded: true)
    let check = Task { await flow.verify(using: provider) }
    while !(await provider.waiting) { await Task.yield() }
    flow.reset()
    await provider.finish()
    await check.value
    #expect(flow.state == .inactive)
    #expect(flow.networkName == nil)
}

@Test func openingDoesNotRequireAnInAppPromptButDeeperActionsDo() {
    #expect(ComputerAction(type: .openApplication, application: "Zoom").opensOnly)
    #expect(ComputerAction(type: .openSettings, element: "Wi-Fi").opensOnly)
    #expect(!ComputerAction(type: .typeText, application: "Finder", element: "Search", text: "photos").opensOnly)
    #expect(!ComputerAction(type: .click, application: "Finder", element: "Back").opensOnly)
}
