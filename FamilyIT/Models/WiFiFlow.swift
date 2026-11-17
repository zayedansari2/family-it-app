import Foundation

nonisolated struct WiFiStatus: Equatable, Sendable {
    enum ConnectionState: Equatable, Sendable { case disabled, disconnected, connected, unavailable }
    let state: ConnectionState
    var networkName: String? = nil

    /// A missing SSID is not evidence of disconnection: macOS may redact it.
    static func map(hasInterface: Bool, powered: Bool, associated: Bool?, ssid: String?) -> Self {
        guard hasInterface else { return .init(state: .unavailable) }
        guard powered else { return .init(state: .disabled) }
        if let ssid, !ssid.isEmpty { return .init(state: .connected, networkName: ssid) }
        if associated == false { return .init(state: .disconnected) }
        return .init(state: .unavailable)
    }
}

nonisolated protocol WiFiStatusProviding: Sendable {
    func currentStatus() async -> WiFiStatus
}

nonisolated enum WiFiIntent {
    static let privacyMessage = "For your privacy, please enter the Wi-Fi password directly in System Settings."
    static func isSensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["password", "passphrase", "passcode", "secret", "pwd", "psk"].contains { lower.contains($0) }
    }
    static func matches(_ text: String) -> Bool {
        let lower = text.lowercased().replacingOccurrences(of: "‑", with: "-")
        return ["wi-fi", "wifi", "wi fi", "wireless", "guest network"].contains { lower.contains($0) }
            || lower.range(of: #"\b(join|connect).*\b(network|guest)\b"#, options: .regularExpression) != nil
    }
    static func isRequest(_ text: String) -> Bool { matches(text) }
    static func networkName(in text: String) -> String? {
        // Extract only a short explicit target; never retain the original request.
        guard !isSensitive(text) else { return nil }
        let pattern = #"(?i)(?:connect(?:\s+me)?\s+to|join|connecting\s+to)\s+(.+?)[.!?]*$"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let target = String(text[range]).replacingOccurrences(of:
            #"(?i)^(?:connect(?:\s+me)?\s+to|join|connecting\s+to)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^the\s+|\s+network[.!?]*$|[.!?]+$"#, with: "", options: .regularExpression)
        return safeName(target)
    }
    static func safeName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        guard !isSensitive(name), !name.isEmpty, name.utf8.count <= 32,
              !["wifi", "wi-fi", "wi fi", "a network"].contains(name.lowercased()),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return name
    }
    static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Local-only state machine. There is deliberately no backend or password action here.
@MainActor final class WiFiFlow {
    enum State: Equatable { case inactive, askingForNetworkName, openingWiFiSettings, waitingForUser,
        verifyingConnection, connected, notConnected, unavailable, openFailed, differentNetwork }
    private(set) var state: State = .inactive
    private(set) var networkName: String?
    private var observedName: String?
    private var detail = ""
    private var generation = UUID()
    static var settingsAction: ComputerAction { ComputerAction(type: .openSettings, element: "Wi-Fi") }
    var active: Bool { state != .inactive }
    var acceptsInput: Bool { state == .askingForNetworkName }
    var canRetry: Bool { [.notConnected, .unavailable, .openFailed, .differentNetwork].contains(state) }
    var statusLabel: String {
        switch state {
        case .openingWiFiSettings: "Opening Wi-Fi settings"
        case .waitingForUser: "Ready to check your connection"
        case .verifyingConnection: "Checking your connection"
        case .connected: "You are connected"
        case .notConnected, .unavailable, .differentNetwork, .openFailed: "We could not confirm the connection"
        default: "Wi-Fi help · stays on your Mac"
        }
    }
    var turn: AssistantTurn {
        let target = networkName ?? "your network"
        switch state {
        case .askingForNetworkName:
            return .init(text: detail.isEmpty ? "What is the name of the Wi-Fi network you want to join? Enter only the network name, not the password." : detail, kind: .question)
        case .openingWiFiSettings: return .init(text: "Opening Wi-Fi settings.", kind: .reassurance)
        case .waitingForUser:
            return .init(text: detail.isEmpty ? "Select “\(target)” in System Settings. Enter the password there, then press Connect. Come back here and choose “I did it”." : detail, kind: .instruction)
        case .verifyingConnection: return .init(text: "Checking your connection.", kind: .reassurance)
        case .connected: return .init(text: "You are connected to “\(target)”.", kind: .completion)
        case .differentNetwork:
            return .init(text: "Your Mac reports “\(observedName ?? "another network")”, not “\(target)”. Is that the network you expected?", kind: .question)
        case .notConnected: return .init(text: detail, kind: .question)
        case .openFailed: return .init(text: "I couldn’t open Wi-Fi settings. Open System Settings, then choose Wi-Fi. Choose Try again to reopen it.", kind: .question)
        default:
            return .init(text: "macOS hasn’t made the Wi-Fi network name available. I can’t confirm this connection. Check the connected network in System Settings. You can optionally enable connection checks below.", kind: .question)
        }
    }
    func start(_ request: String) {
        reset()
        networkName = WiFiIntent.networkName(in: request)
        state = networkName == nil ? .askingForNetworkName : .openingWiFiSettings
        if WiFiIntent.isSensitive(request) { detail = WiFiIntent.privacyMessage }
    }
    func acceptName(_ name: String) {
        guard state == .askingForNetworkName else { return }
        guard let safe = WiFiIntent.safeName(name) else {
            detail = WiFiIntent.isSensitive(name) ? WiFiIntent.privacyMessage : "Please enter only the network name, up to 32 bytes. You can also open Wi-Fi settings below."
            return
        }
        networkName = safe; detail = ""; state = .openingWiFiSettings
    }
    func settingsOpened(succeeded: Bool) {
        guard state == .openingWiFiSettings else { return }
        state = succeeded ? .waitingForUser : .openFailed
    }
    func retry() {
        guard canRetry || state == .waitingForUser else { return }
        generation = UUID(); detail = ""; state = .openingWiFiSettings
    }
    func moreHelp() {
        guard active else { return }
        detail = state == .askingForNetworkName ? WiFiIntent.privacyMessage :
            "In System Settings, choose Wi-Fi on the left. Turn Wi-Fi on if needed, then find “\(networkName ?? "your network")”. If it isn’t listed, move closer to the router or ask its owner for the exact name. Enter any password only in System Settings."
        if state != .askingForNetworkName { state = .waitingForUser }
    }
    func verify(using provider: any WiFiStatusProviding) async {
        guard state == .waitingForUser else { return }
        state = .verifyingConnection
        let token = generation
        let status = await provider.currentStatus()
        guard token == generation, !Task.isCancelled else { return }
        switch status.state {
        case .connected:
            guard let actual = status.networkName, let networkName else { state = .unavailable; return }
            if WiFiIntent.normalized(actual) == WiFiIntent.normalized(networkName) { state = .connected }
            else { observedName = actual; state = .differentNetwork }
        case .disabled, .disconnected:
            state = .notConnected
            detail = status.state == .disabled ? "Wi-Fi is turned off. Turn it on in System Settings, then select “\(networkName ?? "your network")”." : "It looks like you are not connected to “\(networkName ?? "your network")” yet."
        case .unavailable: state = .unavailable
        }
    }
    func confirmObservedNetwork() {
        guard state == .differentNetwork, let observedName else { return }
        networkName = observedName; state = .connected
    }
    func reset() { generation = UUID(); state = .inactive; networkName = nil; observedName = nil; detail = "" }
}
