import Foundation
@testable import FADriverKit

/// Deterministic LLM stub for unit tests. Returns queued `LLMReply` values in
/// order. Exhausting the queue throws.
final class MockLLM: LLMProtocol {
    private var replies: [LLMReply]
    private(set) var receivedMessages: [String] = []
    private(set) var receivedTools: [String?] = []

    init(replies: [LLMReply]) {
        self.replies = replies
    }

    func complete(messagesJson: String, toolsJson: String?, forceTools: Bool) async throws -> LLMReply {
        receivedMessages.append(messagesJson)
        receivedTools.append(toolsJson)
        guard !replies.isEmpty else {
            throw NSError(domain: "MockLLM", code: 0, userInfo: [NSLocalizedDescriptionKey: "no more replies queued"])
        }
        return replies.removeFirst()
    }
}
