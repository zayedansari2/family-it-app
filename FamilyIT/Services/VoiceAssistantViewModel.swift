import Foundation

@MainActor
final class VoiceAssistantViewModel: ObservableObject {
    @Published var screen: AppScreen = .home
    @Published var typedProblem = ""
    @Published private(set) var currentTurn: AssistantTurn?
    @Published private(set) var activity: AssistantActivity = .idle
    @Published private(set) var heardText = ""

    let exampleProblems = [
        "I can’t hear my Zoom meeting",
        "I can’t find an app",
        "I can’t find my photos"
    ]

    private let engine: TroubleshootingEngine
    private let speechRecognition: SpeechRecognitionService
    private let speechSynthesizer: SpeechSynthesizerService
    private var turnHistory: [AssistantTurn] = []
    private var preparationTask: Task<Void, Never>?

    init(
        engine: TroubleshootingEngine = ScriptedTroubleshootingEngine(),
        speechRecognition: SpeechRecognitionService = SpeechRecognitionService(),
        speechSynthesizer: SpeechSynthesizerService = SpeechSynthesizerService()
    ) {
        self.engine = engine
        self.speechRecognition = speechRecognition
        self.speechSynthesizer = speechSynthesizer
    }

    var isListening: Bool {
        activity == .listening
    }

    func begin(problem: String) {
        let cleaned = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        stopAllAudio()
        typedProblem = cleaned
        heardText = ""
        turnHistory = []
        let firstTurn = engine.start(problem: cleaned)
        currentTurn = firstTurn
        screen = .assistant
        speak(firstTurn)
    }

    func didCompleteInstruction() {
        prepareNextTurn { [engine] in
            engine.advance(with: nil)
        }
    }

    func needsMoreHelp() {
        prepareNextTurn { [engine] in
            engine.provideMoreHelp()
        }
    }

    func repeatInstruction() {
        guard let currentTurn else { return }
        speak(currentTurn)
    }

    func goBack() {
        if let previous = turnHistory.popLast() {
            stopAllAudio()
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
            let transcript = speechRecognition.stopAndReturnTranscript()
            finishListening(with: transcript)
            return
        }

        speechSynthesizer.stop()
        preparationTask?.cancel()
        heardText = ""
        activity = .listening

        Task {
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
        }
    }

    private func finishListening(with transcript: String) {
        guard isListening else { return }
        activity = .idle
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if screen == .home {
            typedProblem = cleaned
            begin(problem: cleaned)
        } else {
            prepareNextTurn { [engine] in
                engine.advance(with: cleaned)
            }
        }
    }

    private func prepareNextTurn(_ makeTurn: @escaping () -> AssistantTurn) {
        speechSynthesizer.stop()
        speechRecognition.stopAndReturnTranscript()
        if let currentTurn {
            turnHistory.append(currentTurn)
        }
        activity = .preparing

        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            let nextTurn = makeTurn()
            self.currentTurn = nextTurn
            self.heardText = ""
            self.speak(nextTurn)
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

    private func stopAllAudio() {
        preparationTask?.cancel()
        preparationTask = nil
        speechRecognition.stopAndReturnTranscript()
        speechSynthesizer.stop()
    }
}

