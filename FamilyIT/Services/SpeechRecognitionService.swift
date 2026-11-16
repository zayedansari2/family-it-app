@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

enum SpeechRecognitionServiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case couldNotStartAudio
    case recognitionFailed(String)

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
        case let .recognitionFailed(message):
            "I couldn’t understand the recording. \(message) Please try again or type your problem."
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
    private var partialResultHandler: ((String) -> Void)?
    private var automaticFinishHandler: ((String) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    func start(
        onPartialResult: @escaping (String) -> Void,
        onAutomaticFinish: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        stopAndReturnTranscript()
        partialResultHandler = onPartialResult
        automaticFinishHandler = onAutomaticFinish
        errorHandler = onError

        let microphoneAllowed = await hasMicrophonePermission()
        guard !Task.isCancelled else {
            cleanup()
            return
        }
        guard microphoneAllowed else {
            report(error: SpeechRecognitionServiceError.microphoneDenied)
            return
        }

        let speechRecognitionAllowed = await hasSpeechRecognitionPermission()
        guard !Task.isCancelled else {
            cleanup()
            return
        }
        guard speechRecognitionAllowed else {
            report(error: SpeechRecognitionServiceError.speechRecognitionDenied)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            report(error: SpeechRecognitionServiceError.recognizerUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        latestTranscript = ""

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            report(error: SpeechRecognitionServiceError.couldNotStartAudio)
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
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
            report(error: SpeechRecognitionServiceError.couldNotStartAudio)
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: receiveRecognitionResult)
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
        partialResultHandler = nil
        automaticFinishHandler = nil
        errorHandler = nil
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

        return await Self.requestSpeechRecognitionPermission()
    }

    private nonisolated static func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }

    private nonisolated func receiveRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        let transcript = result?.bestTranscription.formattedString
        let isFinal = result?.isFinal ?? false
        let errorMessage = error?.localizedDescription

        Task { @MainActor [weak self] in
            self?.handleRecognitionResult(
                transcript: transcript,
                isFinal: isFinal,
                errorMessage: errorMessage
            )
        }
    }

    private func handleRecognitionResult(
        transcript: String?,
        isFinal: Bool,
        errorMessage: String?
    ) {
        guard recognitionRequest != nil else { return }

        if let transcript {
            latestTranscript = transcript
            partialResultHandler?(transcript)
            if isFinal {
                let finishHandler = automaticFinishHandler
                cleanup()
                finishHandler?(transcript)
            }
        } else if let errorMessage {
            report(error: SpeechRecognitionServiceError.recognitionFailed(errorMessage))
        }
    }

    private func report(error: Error) {
        let handler = errorHandler
        cleanup()
        handler?(error)
    }
}

