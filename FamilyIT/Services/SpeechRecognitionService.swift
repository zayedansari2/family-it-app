@preconcurrency import AVFoundation
@preconcurrency import Speech
import CoreMedia
import Foundation

enum SpeechRecognitionServiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case microphoneUnavailable
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
        case .microphoneUnavailable:
            "I couldn’t find an available microphone. Check your Mac’s sound input, or type your problem instead."
        case .couldNotStartAudio:
            "I couldn’t start the microphone. You can type your problem instead."
        case let .recognitionFailed(message):
            "I couldn’t understand the recording. \(message) Please try again or type your problem."
        }
    }
}

@MainActor
final class SpeechRecognitionService {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let microphoneCapture = MicrophoneCapture()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
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

        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: receiveRecognitionResult)
        do {
            try await microphoneCapture.start(feeding: request)
        } catch {
            if let captureError = error as? MicrophoneCaptureError, captureError == .noAudioDevice {
                report(error: SpeechRecognitionServiceError.microphoneUnavailable)
            } else {
                report(error: SpeechRecognitionServiceError.couldNotStartAudio)
            }
            return
        }
        guard !Task.isCancelled else {
            cleanup()
            return
        }
    }

    @discardableResult
    func stopAndReturnTranscript() -> String {
        let transcript = latestTranscript
        cleanup()
        return transcript
    }

    private func cleanup() {
        microphoneCapture.stop()
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

private enum MicrophoneCaptureError: Error {
    case noAudioDevice
    case cannotAddInput
    case cannotAddOutput
    case failedToStart
}

/// AVCaptureSession's start/stop calls are blocking. This helper owns them on a
/// serial background queue and forwards native sample buffers directly to Speech.
/// It intentionally has no UI or MainActor state.
private nonisolated final class MicrophoneCapture: NSObject, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.familyit.microphone.session", qos: .userInitiated)
    private let sampleBufferQueue = DispatchQueue(label: "com.familyit.microphone.samples", qos: .userInitiated)
    private let requestBox = SpeechAudioRequestBox()
    private var isConfigured = false

    func start(feeding request: SFSpeechAudioBufferRecognitionRequest) async throws {
        requestBox.set(request)

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                    guard captureSession.isRunning else {
                        throw MicrophoneCaptureError.failedToStart
                    }
                    continuation.resume()
                } catch {
                    requestBox.clear()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        requestBox.clear()
        sessionQueue.async { [self] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw MicrophoneCaptureError.noAudioDevice
        }

        let input = try AVCaptureDeviceInput(device: audioDevice)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard captureSession.canAddInput(input) else {
            throw MicrophoneCaptureError.cannotAddInput
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(output) else {
            throw MicrophoneCaptureError.cannotAddOutput
        }
        captureSession.addOutput(output)
        isConfigured = true
    }
}

nonisolated extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return
        }
        requestBox.append(sampleBuffer)
    }
}

private nonisolated final class SpeechAudioRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        request?.appendAudioSampleBuffer(sampleBuffer)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        request = nil
        lock.unlock()
    }
}

