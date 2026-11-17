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

    init(engine: TroubleshootingEngine = CodexTroubleshootingEngine()) { self.engine = engine }
    var isListening: Bool { activity == .listening }
    var isPreparing: Bool { activity == .preparing }
    var hasPendingAction: Bool { pendingAction != nil }

    func begin(problem: String) {
        let cleaned = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        stop()
        engine.reset()
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
        request { [engine] in try await engine.advance(with: nil) }
    }
    func needsMoreHelp(context: String? = nil) {
        pendingAction = nil
        request { [engine] in try await engine.provideMoreHelp(context: context ?? "That didn’t work. Try a different approach.") }
    }
    func explainDifferently() { needsMoreHelp(context: "Explain that differently. I have not completed the step.") }
    func repeatInstruction() { if let turn = currentTurn { speak(turn) } }
    func retry() { if let retryOperation { request(retryOperation) } }
    func cancel() {
        stop()
        pendingAction = nil
        activity = .idle
        canRetry = retryOperation != nil
    }
    func returnHome() {
        stop(); engine.reset()
        pendingAction = nil; currentTurn = nil; typedProblem = ""; typedReply = ""; heardText = ""
        backendLabel = ""; actionLog = []; retryOperation = nil; canRetry = false
        activity = .idle; screen = .home
    }
    func propose(_ action: ComputerAction) {
        guard !isPreparing else { return }
        voice.stop()
        do {
            pendingAction = try action.validated()
            screen = .assistant
            currentTurn = AssistantTurn(text: "Review this request before continuing.", kind: .instruction)
            activity = .idle
        }
        catch { show(error) }
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
                    pendingAction = action
                }
            }
        }
    }
    private func receive(_ text: String) {
        guard !isPreparing, pendingAction == nil else { return }
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
                speak(turn)
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
        guard !isPreparing, pendingAction == nil else { return }
        voice.stop(); activity = .listening; heardText = ""
        listenTask = Task { [weak self] in
            guard let self else { return }
            await recognition.start(onPartialResult: { [weak self] text in
                guard let self, isListening else { return }
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
