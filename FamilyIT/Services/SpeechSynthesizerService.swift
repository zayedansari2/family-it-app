@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SpeechSynthesizerService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finishHandler: (() -> Void)?
    private var activeUtterance: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: @escaping () -> Void) {
        stop()
        let preferences = UserDefaults.standard
        guard preferences.object(forKey: "voiceEnabled") == nil || preferences.bool(forKey: "voiceEnabled") else {
            onFinish()
            return
        }
        finishHandler = onFinish

        let utterance = AVSpeechUtterance(string: text)
        activeUtterance = ObjectIdentifier(utterance)
        let speed = preferences.double(forKey: "voiceSpeed")
        utterance.rate = speed == 0 ? 0.42 : Float(min(max(speed, 0.25), 0.55))
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        let identifier = preferences.string(forKey: "voiceIdentifier") ?? ""
        utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
            ?? AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("en") }
                .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finishHandler = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.activeUtterance == identifier else { return }
            let handler = self?.finishHandler
            self?.finishHandler = nil
            self?.activeUtterance = nil
            handler?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.activeUtterance == identifier else { return }
            self?.finishHandler = nil
            self?.activeUtterance = nil
        }
    }
}

