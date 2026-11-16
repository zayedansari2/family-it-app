import Foundation

@MainActor
final class VoiceAssistantViewModel: ObservableObject {
    @Published var screen: AppScreen = .home
    @Published var typedProblem = ""
    @Published private(set) var currentTurn: AssistantTurn?
    @Published private(set) var activity: AssistantActivity = .idle
    @Published private(set) var heardText = ""

    let exampleProblems = [
        "How do I download Zoom?",
        "How do I make the text bigger?",
        "I can’t hear my meeting",
        "Open Safari"
    ]

    private let engine: TroubleshootingEngine
    private let speechRecognition: SpeechRecognitionService
    private let speechSynthesizer: SpeechSynthesizerService
    private let appLauncher: AppLaunching
    private var turnHistory: [AssistantTurn] = []
    private var preparationTask: Task<Void, Never>?
    private var listeningStartTask: Task<Void, Never>?

    init(
        engine: TroubleshootingEngine = CodexTroubleshootingEngine(),
        speechRecognition: SpeechRecognitionService = SpeechRecognitionService(),
        speechSynthesizer: SpeechSynthesizerService = SpeechSynthesizerService(),
        appLauncher: AppLaunching = MacAppLauncher()
    ) {
        self.engine = engine
        self.speechRecognition = speechRecognition
        self.speechSynthesizer = speechSynthesizer
        self.appLauncher = appLauncher
    }

    var isListening: Bool {
        activity == .listening
    }

    var isPreparing: Bool {
        activity == .preparing
    }

    func begin(problem: String) {
        let cleaned = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        stopAllAudio()
        typedProblem = cleaned
        heardText = ""
        turnHistory = []

        if let applicationName = OpenAppRequestParser.applicationName(from: cleaned) {
            openApplication(named: applicationName)
            return
        }

        screen = .assistant
        currentTurn = AssistantTurn(
            text: "I’m preparing your first step…",
            kind: .reassurance
        )
        activity = .preparing

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let firstTurn = try await self.engine.start(problem: cleaned)
                guard !Task.isCancelled else { return }
                self.currentTurn = firstTurn
                self.speak(firstTurn)
            } catch is CancellationError {
                return
            } catch {
                self.showGuidanceError(error)
            }
        }
    }

    func didCompleteInstruction() {
        guard currentTurn?.kind.isInstruction == true else { return }
        prepareNextTurn { [engine] in
            try await engine.advance(with: nil)
        }
    }

    func needsMoreHelp(context: String? = nil) {
        prepareNextTurn { [engine] in
            try await engine.provideMoreHelp(context: context)
        }
    }

    func repeatInstruction() {
        guard let currentTurn else { return }
        speak(currentTurn)
    }

    func goBack() {
        if let previous = turnHistory.popLast() {
            stopAllAudio()
            engine.rewind()
            currentTurn = previous
            speak(previous)
        } else {
            returnHome()
        }
    }

    func returnHome() {
        stopAllAudio()
        engine.reset()
        turnHistory = []
        currentTurn = nil
        heardText = ""
        typedProblem = ""
        screen = .home
        activity = .idle
    }

    func toggleListening() {
        if isListening {
            listeningStartTask?.cancel()
            listeningStartTask = nil
            let transcript = speechRecognition.stopAndReturnTranscript()
            finishListening(with: transcript)
            return
        }

        speechSynthesizer.stop()
        preparationTask?.cancel()
        heardText = ""
        activity = .listening

        listeningStartTask = Task { [weak self] in
            guard let self else { return }
            await speechRecognition.start(
                onPartialResult: { [weak self] transcript in
                    guard let self, self.isListening else { return }
                    self.heardText = transcript
                    if self.screen == .home {
                        self.typedProblem = transcript
                    }
                },
                onAutomaticFinish: { [weak self] transcript in
                    self?.finishListening(with: transcript)
                },
                onError: { [weak self] error in
                    self?.show(error: error)
                }
            )
            if !Task.isCancelled {
                self.listeningStartTask = nil
            }
        }
    }

    private func finishListening(with transcript: String) {
        guard isListening else { return }
        listeningStartTask = nil
        activity = .idle
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if let applicationName = OpenAppRequestParser.applicationName(from: cleaned) {
            openApplication(named: applicationName)
            return
        }

        if screen == .home {
            typedProblem = cleaned
            begin(problem: cleaned)
        } else if currentTurn?.kind.isInstruction == true {
            if Self.isCompletionConfirmation(cleaned) {
                didCompleteInstruction()
            } else {
                needsMoreHelp(context: cleaned)
            }
        } else {
            prepareNextTurn { [engine] in
                try await engine.advance(with: cleaned)
            }
        }
    }

    private func prepareNextTurn(_ makeTurn: @escaping () async throws -> AssistantTurn) {
        speechSynthesizer.stop()
        speechRecognition.stopAndReturnTranscript()
        let previousTurn = currentTurn
        activity = .preparing

        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let nextTurn = try await makeTurn()
                guard !Task.isCancelled else { return }
                if let previousTurn {
                    self.turnHistory.append(previousTurn)
                }
                self.currentTurn = nextTurn
                self.heardText = ""
                self.speak(nextTurn)
            } catch is CancellationError {
                return
            } catch {
                self.showGuidanceError(error)
            }
        }
    }

    private func openApplication(named applicationName: String) {
        stopAllAudio()
        engine.reset()
        turnHistory = []
        heardText = ""
        screen = .assistant

        let introduction = AssistantTurn(
            text: "Okay. I’ll open \(applicationName) for you now.",
            kind: .reassurance
        )
        currentTurn = introduction
        activity = .speaking

        speechSynthesizer.speak(introduction.text) { [weak self] in
            self?.performApplicationLaunch(named: applicationName)
        }
    }

    private func performApplicationLaunch(named applicationName: String) {
        activity = .preparing
        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }

            let result = await self.appLauncher.openApplication(named: applicationName)
            let resultTurn: AssistantTurn
            switch result {
            case let .opened(displayName):
                resultTurn = AssistantTurn(
                    text: "\(displayName) is open. You can use it now.",
                    kind: .completion
                )
            case let .notFound(requestedName):
                resultTurn = AssistantTurn(
                    text: "I couldn’t find an app called \(requestedName). Please tell me its exact name, and we’ll try again.",
                    kind: .question
                )
            case let .failed(displayName, reason):
                resultTurn = AssistantTurn(
                    text: "I found \(displayName), but macOS wouldn’t open it. It said: \(reason) You can try again, or ask me for another app.",
                    kind: .question
                )
            }

            self.currentTurn = resultTurn
            self.speak(resultTurn)
        }
    }

    private func speak(_ turn: AssistantTurn) {
        activity = .speaking
        speechSynthesizer.speak(turn.text) { [weak self] in
            guard let self, self.activity == .speaking else { return }
            self.activity = .idle
        }
    }

    private func show(error: Error) {
        speechRecognition.stopAndReturnTranscript()
        let message = (error as? LocalizedError)?.errorDescription
            ?? "I couldn’t hear that. Please try again or type your problem."
        activity = .error(message)
    }

    private func showGuidanceError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "I couldn’t prepare the next step. Please try again."
        currentTurn = AssistantTurn(text: message, kind: .question)
        activity = .error(message)
    }

    private static func isCompletionConfirmation(_ response: String) -> Bool {
        let answer = response.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let negativePhrases = [
            "not done",
            "not finished",
            "did not",
            "didn't",
            "haven't",
            "have not",
            "can't",
            "cannot"
        ]
        guard !negativePhrases.contains(where: answer.contains) else { return false }

        let confirmations = ["done", "did it", "finished", "that worked", "it worked", "completed"]
        return confirmations.contains(where: answer.contains)
    }

    private func stopAllAudio() {
        listeningStartTask?.cancel()
        listeningStartTask = nil
        preparationTask?.cancel()
        preparationTask = nil
        speechRecognition.stopAndReturnTranscript()
        speechSynthesizer.stop()
    }
}

