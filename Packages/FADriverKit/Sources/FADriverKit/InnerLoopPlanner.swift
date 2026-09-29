import Foundation

/// Generic "drive any iOS app" planner. Runs an inner LLM loop — observe screen,
/// decide next WDA primitive, ship it, observe again — until the model calls
/// `finish` or we hit `maxSteps`.
///
/// Decoupled from a specific send transport via the `SendFunc` closure: tests
/// inject a fake that echoes canned replies; production passes
/// `MacBridge.shared.send(_:options:)`.
public final class InnerLoopPlanner {
    public typealias SendFunc = (Intent, SendOptions) async throws -> IntentReply

    private let llm: LLMProtocol
    private let send: SendFunc

    public init(llm: LLMProtocol, send: @escaping SendFunc) {
        self.llm = llm
        self.send = send
    }

    /// Convenience initializer that wires the planner up to a live `MacBridge`.
    public convenience init(llm: LLMProtocol, macBridge: MacBridge) {
        self.init(llm: llm) { intent, options in
            try await macBridge.send(intent, options: options)
        }
    }

    /// Drive until the model calls `finish` or `maxSteps` is reached. Returns
    /// the model's summary string. Throws on empty goal, LLM failure, or
    /// maxSteps exhaustion.
    public func run(goal: String, maxSteps: Int = 12) async throws -> String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { throw PlannerError.emptyGoal }

        var history: [[String: Any]] = [
            ["role": "system", "content": DrivePrimitives.systemPrompt],
            ["role": "user", "content": "Goal: \(trimmedGoal)\n\nPick the next primitive. Start with snapshot if you don't know the screen state."],
        ]

        for step in 1...maxSteps {
            guard let messagesJson = Self.serialize(history) else {
                throw PlannerError.serializationFailed(step: step)
            }
            NSLog("[fadriver] drive_step=%d goal=%@", step, trimmedGoal)

            let reply = try await llm.complete(
                messagesJson: messagesJson,
                toolsJson: DrivePrimitives.json,
                forceTools: true
            )
            guard let call = reply.toolCalls.first else {
                NSLog("[fadriver] drive_no_tool_call step=%d text=%@", step, reply.text)
                throw PlannerError.noToolCall(step: step, text: reply.text)
            }

            NSLog("[fadriver] drive_call step=%d name=%@", step, call.name)

            if call.name == "finish" {
                let summary = (call.arguments["summary"] as? String) ?? "done"
                NSLog("[fadriver] drive_finish step=%d summary=%@", step, summary)
                return summary
            }

            let intent: Intent
            switch call.name {
            case "activate":
                intent = .driveActivate(bundleId: (call.arguments["bundleId"] as? String) ?? "")
            case "snapshot":
                intent = .driveSnapshot
            case "click":
                intent = .driveClick(
                    label: call.arguments["label"] as? String,
                    predicate: call.arguments["predicate"] as? String
                )
            case "type":
                intent = .driveType(text: (call.arguments["text"] as? String) ?? "")
            default:
                throw PlannerError.unknownPrimitive(name: call.name, step: step)
            }

            let result: String
            do {
                let wdaReply = try await send(intent, SendOptions(returnToCaller: false, returnDelaySeconds: 0, timeout: 20))
                if wdaReply.isOK {
                    result = wdaReply.summary.isEmpty ? "ok" : wdaReply.summary
                } else {
                    result = "error: \(wdaReply.error?.message ?? "unknown")"
                }
            } catch {
                result = "error: \(error.localizedDescription)"
            }
            NSLog("[fadriver] drive_result step=%d result=%@", step, result.prefix(200).description)

            history.append([
                "role": "assistant",
                "content": "Called \(call.name) with \(Self.compactJSON(call.arguments))"
            ])
            history.append([
                "role": "user",
                "content": "Result:\n\(result)\n\nNext primitive? Call finish when the goal is accomplished."
            ])
        }
        throw PlannerError.maxStepsExceeded(goal: trimmedGoal, max: maxSteps)
    }

    // MARK: - Helpers

    private static func serialize(_ messages: [[String: Any]]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: messages) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func compactJSON(_ args: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
