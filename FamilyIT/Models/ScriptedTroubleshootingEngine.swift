import Foundation

/// The boundary for the assistant's troubleshooting logic. A future local model,
/// Codex integration, or Mac automation adapter can implement this protocol
/// without changing the views or speech services.
protocol TroubleshootingEngine: AnyObject {
    func start(problem: String) -> AssistantTurn
    func advance(with userResponse: String?) -> AssistantTurn
    func provideMoreHelp() -> AssistantTurn
    func reset()
}

final class ScriptedTroubleshootingEngine: TroubleshootingEngine {
    private enum Topic {
        case zoomAudio
        case findApp
        case findPhotos
        case general
    }

    private var topic: Topic = .general
    private var stepIndex = 0
    private var steps: [AssistantTurn] = []

    func start(problem: String) -> AssistantTurn {
        topic = detectTopic(in: problem)
        steps = script(for: topic)
        stepIndex = 0
        return steps[stepIndex]
    }

    func advance(with userResponse: String?) -> AssistantTurn {
        if currentTurn.kind == .question, stepIndex == steps.count - 2, userResponse != nil {
            if isSuccessResponse(userResponse) {
                stepIndex = steps.count - 1
                return currentTurn
            }
            return provideMoreHelp()
        }

        if stepIndex < steps.count - 1 {
            stepIndex += 1
        }
        return currentTurn
    }

    func provideMoreHelp() -> AssistantTurn {
        switch topic {
        case .zoomAudio:
            return AssistantTurn(
                text: "That’s okay. Look at the very bottom-left of the Zoom window. Find the small microphone picture. Just to its right is a tiny upward arrow. Click that arrow once.",
                kind: .instruction
            )
        case .findApp:
            return AssistantTurn(
                text: "No problem. Press and hold the Command key, then tap the Space bar. A search box will appear in the middle of your screen.",
                kind: .instruction
            )
        case .findPhotos:
            return AssistantTurn(
                text: "That’s all right. Look along the bottom edge of the screen for a flower made of several colors. That is the Photos app. Click it once.",
                kind: .instruction
            )
        case .general:
            return AssistantTurn(
                text: "We can slow down. Tell me what you see on the screen right now, including any words or pictures that stand out.",
                kind: .question
            )
        }
    }

    func reset() {
        topic = .general
        stepIndex = 0
        steps = []
    }

    private var currentTurn: AssistantTurn {
        steps[stepIndex]
    }

    private func detectTopic(in problem: String) -> Topic {
        let words = problem.lowercased()
        if words.contains("zoom") || words.contains("hear") || words.contains("meeting") || words.contains("sound") {
            return .zoomAudio
        }
        if words.contains("photo") || words.contains("picture") {
            return .findPhotos
        }
        if words.contains("app") || words.contains("application") || words.contains("program") {
            return .findApp
        }
        return .general
    }

    private func isSuccessResponse(_ response: String?) -> Bool {
        guard let response else { return false }
        let answer = response.lowercased()
        return answer.contains("yes") || answer.contains("hear it") || answer.contains("working") || answer.contains("fixed")
    }

    private func script(for topic: Topic) -> [AssistantTurn] {
        switch topic {
        case .zoomAudio:
            return [
                AssistantTurn(
                    text: "I can help with that. Is the Zoom meeting window open on your screen now?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Look at the bottom-left corner of the Zoom window. Click the small upward arrow next to the microphone picture.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "In the menu that opens, find “Select a Speaker.” Click the option called “MacBook Speakers” or “Built-in Output.”",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "Now press the volume-up key on your keyboard three times. It has a speaker picture with sound waves.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "Can you hear the Zoom meeting now?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Wonderful. You fixed the sound. If it happens again, you can use that little arrow beside the microphone to choose your speakers.",
                    kind: .completion
                )
            ]
        case .findApp:
            return [
                AssistantTurn(
                    text: "We’ll find it together. Do you remember the name of the app?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Press and hold the Command key, then tap the Space bar. A search box will appear.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "Type the name of the app in the search box. When its picture appears, press the Return key to open it.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "Did the app open?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Great work. You can use Command and Space whenever you need to find an app on your Mac.",
                    kind: .completion
                )
            ]
        case .findPhotos:
            return [
                AssistantTurn(
                    text: "I can help you find them. Are you looking for the Photos app, or for one particular picture?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Look along the bottom edge of the screen for a flower made of several colors. Click it once to open Photos.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "In Photos, click “Library” on the left. Your newest pictures will be near the bottom.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "Can you see your pictures now?",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Excellent. You found your photo library.",
                    kind: .completion
                )
            ]
        case .general:
            return [
                AssistantTurn(
                    text: "I’m here to help. What do you see on the screen right now? You can read me any message that appears.",
                    kind: .question
                ),
                AssistantTurn(
                    text: "Thank you. Let’s begin with one safe step: do not close the window yet. Look for a word or button that seems related to what you want to do.",
                    kind: .instruction
                ),
                AssistantTurn(
                    text: "What changed after that? Tell me what you see now.",
                    kind: .question
                ),
                AssistantTurn(
                    text: "You’re doing well. This first version has guided examples for Zoom sound, finding an app, and finding photos. Go back and choose one of those examples for a complete walkthrough.",
                    kind: .completion
                )
            ]
        }
    }
}

