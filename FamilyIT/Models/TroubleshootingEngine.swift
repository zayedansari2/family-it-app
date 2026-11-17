import Foundation

/// The assistant logic boundary. The SwiftUI views do not know whether a turn
/// came from Codex or another future local guidance provider.
@MainActor protocol TroubleshootingEngine: AnyObject {
    var backendLabel: String { get }
    func start(problem: String) async throws -> AssistantTurn
    func advance(with userResponse: String?) async throws -> AssistantTurn
    func provideMoreHelp(context: String?) async throws -> AssistantTurn
    func recordActionOutcome(succeeded: Bool)
    func rewind()
    func reset()
}
