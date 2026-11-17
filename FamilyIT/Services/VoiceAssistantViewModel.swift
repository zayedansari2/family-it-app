import Foundation

@MainActor final class VoiceAssistantViewModel: ObservableObject {
    @Published var screen: AppScreen = .home
    @Published var typedProblem = ""
    @Published var typedReply = ""
    @Published private(set) var currentTurn: AssistantTurn?
    @Published private(set) var activity: AssistantActivity = .idle
    @Published private(set) var heardText = ""
    @Published private(set) var backendLabel = ""
    @Published private(set) var pendingAction: ComputerAction?
    @Published private(set) var actionLog: [String] = []
    @Published private(set) var canRetry = false
    let exampleProblems = ["I can’t hear my Zoom meeting", "I can’t find an app", "I can’t find my photos"]
    private let engine: TroubleshootingEngine
    private let recognition = SpeechRecognitionService()
    private let voice = SpeechSynthesizerService()
    private let executor = SafeComputerExecutor()
    private var task: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var retryOperation: (() async throws -> AssistantTurn)?
    private var ticket = UUID()
    let wifi = WiFiFlow()
    private let wifiStatus: any WiFiStatusProviding = WiFiStatusService()
    private let wifiLocation = WiFiLocationPermission()
    @Published private(set) var wifiState: WiFiFlow.State = .inactive
    var isWiFiFlow: Bool { wifiState != .inactive }
    var acceptsWiFiInput: Bool { !isWiFiFlow || wifiState == .askingForNetworkName }

    private func refreshWiFi() {
        wifiState = wifi.state
        currentTurn = wifi.turn
        backendLabel = "On your Mac"
        pendingAction = nil; retryOperation = nil; canRetry = false
        typedProblem = ""; typedReply = ""; heardText = ""
    }
    private func continueWiFi() {
        refreshWiFi()
        guard wifi.state == .openingWiFiSettings else { speak(wifi.turn); return }
        stop()
        activity = .preparing
        let token = ticket
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await executor.execute(WiFiFlow.settingsAction)
                guard token == ticket, !Task.isCancelled else { return }
                wifi.settingsOpened(succeeded: true)
            } catch {
                guard token == ticket, !Task.isCancelled else { return }
                wifi.settingsOpened(succeeded: false)
            }
            refreshWiFi(); speak(wifi.turn)
        }
    }
    func retryWiFi() { wifi.retry(); continueWiFi() }
    func allowWiFiChecks() { wifiLocation.request() }
    func confirmWiFiName() { wifi.confirmObservedNetwork(); refreshWiFi(); speak(wifi.turn) }
    func reportWiFi(_ observation: WiFiFlow.Observation) { wifi.report(observation); refreshWiFi(); speak(wifi.turn) }

    init(engine: TroubleshootingEngine = CodexTroubleshootingEngine()) { self.engine = engine }
    var isListening: Bool { activity == .listening }
    var isPreparing: Bool { activity == .preparing }
    var hasPendingAction: Bool { pendingAction != nil }

    func begin(problem: String) {
        let cleaned = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        stop()
        engine.reset()
        wifi.reset(); wifiState = .inactive
        if WiFiIntent.isRequest(cleaned) || WiFiIntent.isSensitive(cleaned) {
            screen = .assistant
            wifi.start(cleaned)
            continueWiFi()
            return
        }
        typedProblem = cleaned
        typedReply = ""
        screen = .assistant
        currentTurn = AssistantTurn(text: "Take your time. I’m preparing your first response.", kind: .reassurance)
        request { [engine] in try await engine.start(problem: cleaned) }
    }
    func submitReply() {
        let reply = typedReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return }
        typedReply = ""
        receive(reply)
    }
    func didCompleteInstruction() {
        guard !isPreparing, pendingAction == nil, currentTurn?.kind == .instruction else { return }
        if isWiFiFlow {
            guard wifi.state == .waitingForUser else { return }
            stop(); activity = .preparing
            let token = ticket
            task = Task { [weak self] in
                guard let self else { return }
                // verify changes state before its first suspension.
                wifiState = .verifyingConnection
                currentTurn = AssistantTurn(text: "Checking your connection.", kind: .reassurance)
                await wifi.verify(using: wifiStatus)
                guard token == ticket, !Task.isCancelled else { return }
                refreshWiFi(); speak(wifi.turn)
            }
            return
        }
        request { [engine] in try await engine.advance(with: nil) }
    }
    func needsMoreHelp(context: String? = nil) {
        if isWiFiFlow { stop(); wifi.moreHelp(); refreshWiFi(); speak(wifi.turn); return }
        pendingAction = nil
        request { [engine] in try await engine.provideMoreHelp(context: context ?? "That didn’t work. Try a different approach.") }
    }
    func explainDifferently() { needsMoreHelp(context: "Explain that differently. I have not completed the step.") }
    func repeatInstruction() { if let turn = currentTurn { speak(turn) } }
    func retry() { if let retryOperation { request(retryOperation) } }
    func cancel() {
        stop()
        if isWiFiFlow { wifi.reset(); wifiState = .inactive; returnHome(); return }
        pendingAction = nil
        activity = .idle
        canRetry = retryOperation != nil
    }
    func returnHome() {
        stop(); engine.reset()
        wifi.reset(); wifiState = .inactive
        pendingAction = nil; currentTurn = nil; typedProblem = ""; typedReply = ""; heardText = ""
        backendLabel = ""; actionLog = []; retryOperation = nil; canRetry = false
        activity = .idle; screen = .home
    }
    func propose(_ action: ComputerAction) {
        guard !isPreparing else { return }
        voice.stop()
        do {
            let validated = try action.validated()
            pendingAction = validated
            screen = .assistant
            if validated.opensOnly { confirmAction(); return }
            currentTurn = AssistantTurn(text: "Review this request before continuing.", kind: .instruction)
            activity = .idle
        }
        catch { show(error) }
    }

    func requestOpenApplication(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        propose(ComputerAction(type: .openApplication, application: name))
    }
    func cancelAction() {
        pendingAction = nil
        engine.recordActionOutcome(succeeded: false)
        currentTurn = AssistantTurn(text: "The action was cancelled. Nothing was changed. Tell me what you see.", kind: .question)
        activity = .idle
    }
    func confirmAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil; voice.stop(); activity = .preparing
        let currentTicket = ticket
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await executor.execute(action)
                guard !Task.isCancelled, currentTicket == ticket else { return }
                actionLog.append(action.safeLogDescription)
                engine.recordActionOutcome(succeeded: true)
                // Accessibility content deliberately stays out of the backend conversation.
                currentTurn = AssistantTurn(text: result, kind: .question)
                speak(currentTurn!)
            } catch {
                if currentTicket == ticket {
                    engine.recordActionOutcome(succeeded: false)
                    show(error)
                    pendingAction = action.opensOnly ? nil : action
                }
            }
        }
    }
    private func receive(_ text: String) {
        guard !isPreparing, pendingAction == nil else { return }
        if isWiFiFlow {
            if wifi.state == .askingForNetworkName { wifi.acceptName(text); continueWiFi() }
            return
        }
        if WiFiIntent.isRequest(text) || WiFiIntent.isSensitive(text) { begin(problem: text); return }
        if screen == .home { begin(problem: text); return }
        if currentTurn?.kind == .instruction {
            if ConversationInput.confirmsCompletion(text) { didCompleteInstruction() }
            else { needsMoreHelp(context: text) }
        } else { request { [engine] in try await engine.advance(with: text) } }
    }
    private func request(_ operation: @escaping () async throws -> AssistantTurn) {
        stop()
        let currentTicket = ticket
        pendingAction = nil; heardText = ""; retryOperation = operation
        canRetry = false; activity = .preparing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let turn = try await operation()
                guard !Task.isCancelled, currentTicket == ticket else { return }
                backendLabel = engine.backendLabel
                currentTurn = turn
                pendingAction = turn.action
                if turn.action?.opensOnly == true { confirmAction() }
                else { speak(turn) }
            } catch is CancellationError { }
            catch { if currentTicket == ticket, !Task.isCancelled { show(error); canRetry = true } }
        }
    }
    func toggleListening() {
        if isListening {
            listenTask?.cancel()
            let text = recognition.stopAndReturnTranscript()
            activity = .idle
            receive(text)
            return
        }
        guard !isPreparing, pendingAction == nil, acceptsWiFiInput else { return }
        voice.stop(); activity = .listening; heardText = ""
        listenTask = Task { [weak self] in
            guard let self else { return }
            await recognition.start(onPartialResult: { [weak self] text in
                guard let self, isListening else { return }
                if isWiFiFlow || WiFiIntent.isRequest(text) || WiFiIntent.isSensitive(text) {
                    heardText = ""; typedProblem = ""; return
                }
                heardText = text
                if screen == .home { typedProblem = text }
            }, onAutomaticFinish: { [weak self] text in
                guard let self, isListening else { return }
                activity = .idle; receive(text)
            }, onError: { [weak self] error in self?.show(error) })
        }
    }
    private func speak(_ turn: AssistantTurn) {
        activity = .speaking
        voice.speak(turn.text) { [weak self] in
            if self?.activity == .speaking { self?.activity = .idle }
        }
    }
    private func show(_ error: Error) {
        recognition.stopAndReturnTranscript()
        let message = (error as? GuidanceError)?.errorDescription
            ?? (error as? SpeechRecognitionServiceError)?.errorDescription
            ?? "The response could not be prepared. Please try again."
        activity = .error(message)
    }
    private func stop() {
        ticket = UUID()
        task?.cancel(); task = nil
        listenTask?.cancel(); listenTask = nil
        recognition.stopAndReturnTranscript(); voice.stop()
    }
}
