import Foundation

/// One-shot LLM completion seam. The inner-loop planner and any future
/// FADriverKit subsystem that needs a model call takes one of these and does
/// not depend on a specific engine (Cactus, MLX, CoreML, remote API, …).
///
/// Streaming is intentionally out of scope — the inner loop needs a terminal
/// reply, not partial tokens. Host apps doing token streaming for UI keep that
/// concern outside FADriverKit.
public protocol LLMProtocol: AnyObject {
    /// Complete a chat against an optional tool catalog. `messagesJson` is the
    /// OpenAI-style `[{"role": "...", "content": "..."}]` array serialized to a
    /// string. `toolsJson` is the OpenAI-style tool-definitions array serialized
    /// to a string, or nil if the caller wants text-only. `forceTools` instructs
    /// the engine to guarantee a tool call (used by the inner-loop planner).
    func complete(messagesJson: String, toolsJson: String?, forceTools: Bool) async throws -> LLMReply
}

public struct LLMReply: Sendable {
    public let text: String
    public let toolCalls: [LLMToolCall]

    public init(text: String, toolCalls: [LLMToolCall]) {
        self.text = text
        self.toolCalls = toolCalls
    }
}

public struct LLMToolCall: @unchecked Sendable {
    public let name: String
    public let arguments: [String: Any]

    public init(name: String, arguments: [String: Any]) {
        self.name = name
        self.arguments = arguments
    }
}
