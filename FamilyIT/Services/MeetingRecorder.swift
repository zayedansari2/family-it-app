@preconcurrency import AVFoundation
@preconcurrency import Speech
@preconcurrency import ScreenCaptureKit
import Foundation

/// Audio only: no screen output is registered, and no audio is written to disk.
@MainActor final class MeetingRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = ""
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var microphone: MeetingTranscriber?
    private var remote: MeetingTranscriber?
    private var output: MeetingAudioOutput?
    private var segments: [UUID: (Date, String, String)] = [:]
    private var started = Date()
    private var recordingID = UUID()
    private var limitReached = false

    func start() async throws {
        guard !isRecording else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw AssistantFailure("Allow Microphone access to take meeting notes.") }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { throw AssistantFailure("Allow Speech Recognition access to transcribe meeting notes.") }
        guard SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition == true else {
            throw AssistantFailure("On-device English speech recognition is unavailable on this Mac.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        let zoom = content.applications.filter { ["us.zoom.xos", "us.zoom.caphost"].contains($0.bundleIdentifier) }
        guard !zoom.isEmpty, let display = content.displays.first else { throw AssistantFailure("Open your Zoom meeting before starting meeting notes.") }
        segments = [:]; transcript = ""; started = Date(); recordingID = UUID(); limitReached = false
        let id = recordingID
        let update: @Sendable (UUID, Date, String, String) -> Void = { [weak self] segment, date, source, text in
            Task { @MainActor [weak self] in
                guard let self, self.recordingID == id, !self.limitReached else { return }
                self.segments[segment] = (date, source, text)
                self.transcript = self.segments.values.sorted { $0.0 < $1.0 }.map {
                    "[\(Int($0.0.timeIntervalSince(self.started)))s \($0.1)] \($0.2)"
                }.joined(separator: "\n")
                if self.transcript.count > 200_000 {
                    self.limitReached = true
                    self.status = "The meeting notes limit was reached. Stop and save this visit before starting another."
                    Task { await self.stop() }
                }
            }
        }
        let failure: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.status = message }
        }
        let mic = MeetingTranscriber(source: "You", update: update, failure: failure)
        let other = MeetingTranscriber(source: "Meeting", update: update, failure: failure)
        microphone = mic; remote = other
        let filter = SCContentFilter(display: display, including: zoom, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000; config.channelCount = 1
        config.width = 2; config.height = 2
        let output = MeetingAudioOutput(transcriber: other, failure: failure)
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "FamilyIT.meeting.audio"))
        self.output = output; self.stream = stream
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { await stop(); throw AssistantFailure("No microphone is available.") }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in mic.append(buffer) }
        self.engine = engine
        do {
            try engine.start()
            try await stream.startCapture()
            try Task.checkCancellation()
            isRecording = true; status = "Taking notes from your microphone and Zoom audio."
        } catch {
            await stop()
            throw AssistantFailure("Meeting capture could not start. Check Microphone and Screen & System Audio Recording permissions.")
        }
    }

    func stop() async {
        isRecording = false
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        try? await stream?.stopCapture(); stream = nil; output = nil
        microphone?.finish(); remote?.finish()
        // Give Apple's final result callbacks a short opportunity to settle.
        try? await Task.sleep(for: .milliseconds(900))
        microphone?.cancel(); remote?.cancel(); microphone = nil; remote = nil
    }
    func clear() { recordingID = UUID(); transcript = ""; segments = [:]; status = "" }
}

private nonisolated final class MeetingAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let transcriber: MeetingTranscriber
    let failure: @Sendable (String) -> Void
    init(transcriber: MeetingTranscriber, failure: @escaping @Sendable (String) -> Void) {
        self.transcriber = transcriber; self.failure = failure
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        transcriber.append(sampleBuffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failure("Zoom audio capture stopped. Stop notes to save the speech captured so far.")
    }
}

/// Rolls recognition requests every 45 seconds and preserves late final results by segment ID.
private nonisolated final class MeetingTranscriber: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tasks: [SFSpeechRecognitionTask] = []
    private var timer: DispatchSourceTimer?
    private let source: String
    private let update: @Sendable (UUID, Date, String, String) -> Void
    private let failure: @Sendable (String) -> Void
    private var active = true
    private var currentID = UUID()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    init(source: String, update: @escaping @Sendable (UUID, Date, String, String) -> Void, failure: @escaping @Sendable (String) -> Void) {
        self.source = source; self.update = update; self.failure = failure
        roll()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "FamilyIT.speech.\(source)"))
        timer.schedule(deadline: .now() + 45, repeating: 45)
        timer.setEventHandler { [weak self] in self?.roll() }
        self.timer = timer; timer.resume()
    }
    private func roll() {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.request = request
        let id = UUID(), date = Date(), source = source, update = update, failure = failure
        currentID = id
        guard let recognizer, recognizer.isAvailable else {
            failure("Speech recognition became unavailable. Some meeting notes may be incomplete."); return
        }
        tasks.removeAll { $0.state == .completed || $0.state == .canceling }
        tasks.append(recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result { update(id, date, source, result.bestTranscription.formattedString) }
            if error != nil, result == nil { failure("Some \(source.lowercased()) speech could not be transcribed. Notes may be incomplete.") }
            if result?.isFinal == true {
                DispatchQueue.global().async { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let shouldRoll = self.active && self.currentID == id
                    self.lock.unlock()
                    if shouldRoll { self.roll() }
                }
            }
        })
    }
    func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); defer { lock.unlock() }; request?.append(buffer) }
    func append(_ buffer: CMSampleBuffer) { lock.lock(); defer { lock.unlock() }; request?.appendAudioSampleBuffer(buffer) }
    func finish() { lock.lock(); defer { lock.unlock() }; active = false; timer?.cancel(); timer = nil; request?.endAudio() }
    func cancel() { lock.lock(); defer { lock.unlock() }; tasks.forEach { $0.cancel() }; tasks = []; request = nil }
}
