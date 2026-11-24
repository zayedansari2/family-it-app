import Foundation

nonisolated enum TurnKind: String, Codable, Equatable, Sendable {
    case question
    case instruction
    case reassurance
    case completion

    var isInstruction: Bool {
        self == .instruction
    }
}

struct AssistantTurn: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let kind: TurnKind
    var action: ComputerAction? = nil
}

enum AssistantActivity: Equatable {
    case idle
    case listening
    case speaking
    case preparing
    case error(String)

    var label: String? {
        switch self {
        case .idle:
            nil
        case .listening:
            "Listening…"
        case .speaking:
            "Speaking…"
        case .preparing:
            "Preparing a response…"
        case let .error(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .preparing: "ellipsis"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

enum AppScreen {
    case home
    case assistant
    case telehealthDemo
}

