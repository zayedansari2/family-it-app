@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

enum SpeechRecognitionServiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case couldNotStartAudio

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone."
        case .speechRecognitionDenied:
            "Speech recognition access is off. Turn it on in System Settings → Privacy & Security → Speech Recognition."
        case .recognizerUnavailable:
            "Speech recognition is not available right now. You can type your problem instead."
        case .couldNotStartAudio:
            "I couldn’t start the microphone. You can type your problem instead."
        }
    }
}

@MainActor
final class SpeechRecognitionService {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledAudioTap = false
    private(set) var latestTranscript = ""

    func start(
        onPartialResult: @escaping (String) -> Void,
        onAutomaticFinish: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        stopAndReturnTranscript()

        guard await hasMicrophonePermission() else {
            onError(SpeechRecognitionServiceError.microphoneDenied)
            return
        }
        guard await hasSpeechRecognitionPermission() else {
            onError(SpeechRecognitionServiceError.speechRecognitionDenied)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            onError(SpeechRecognitionServiceError.recognizerUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        latestTranscript = ""

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledAudioTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
            recognitionRequest = nil
            onError(SpeechRecognitionServiceError.couldNotStartAudio)
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.latestTranscript = transcript
                    onPartialResult(transcript)
                    if result.isFinal {
                        self.cleanup()
                        onAutomaticFinish(transcript)
                    }
                } else if let error {
                    self.cleanup()
                    onError(error)
                }
            }
        }
    }

    @discardableResult
    func stopAndReturnTranscript() -> String {
        let transcript = latestTranscript
        cleanup()
        return transcript
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func hasMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            false
        }
    }

    private func hasSpeechRecognitionPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status != .notDetermined { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }
}

