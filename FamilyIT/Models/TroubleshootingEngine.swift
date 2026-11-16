import Foundation

/// The assistant logic boundary. The SwiftUI views do not know whether a turn
/// came from Codex or another future local guidance provider.
protocol TroubleshootingEngine: AnyObject {
    func start(problem: String) async throws -> AssistantTurn
    func advance(with userResponse: String?) async throws -> AssistantTurn
    func provideMoreHelp(context: String?) async throws -> AssistantTurn
    func rewind()
    func reset()
}
