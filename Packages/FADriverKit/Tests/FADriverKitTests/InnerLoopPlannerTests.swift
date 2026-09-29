import XCTest
@testable import FADriverKit

final class InnerLoopPlannerTests: XCTestCase {
    func testTerminatesOnFinishCall() async throws {
        let llm = MockLLM(replies: [
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "snapshot", arguments: [:])]),
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "finish", arguments: ["summary": "sent message"])]),
        ])
        var sent: [String] = []
        let planner = InnerLoopPlanner(llm: llm) { intent, _ in
            sent.append(intent.wireName)
            return IntentReply(id: UUID().uuidString, status: "ok", summary: "screen snapshot", result: [:], error: nil)
        }
        let result = try await planner.run(goal: "send Kate a message")
        XCTAssertEqual(result, "sent message")
        XCTAssertEqual(sent, ["drive_snapshot"])
    }

    func testEmptyGoalThrows() async {
        let llm = MockLLM(replies: [])
        let planner = InnerLoopPlanner(llm: llm) { _, _ in
            IntentReply(id: "1", status: "ok", summary: "", result: [:], error: nil)
        }
        do {
            _ = try await planner.run(goal: "   ")
            XCTFail("expected emptyGoal error")
        } catch PlannerError.emptyGoal {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testMaxStepsExceeded() async {
        let infiniteReplies = (0..<20).map { _ in
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "snapshot", arguments: [:])])
        }
        let llm = MockLLM(replies: infiniteReplies)
        let planner = InnerLoopPlanner(llm: llm) { _, _ in
            IntentReply(id: "1", status: "ok", summary: "ok", result: [:], error: nil)
        }
        do {
            _ = try await planner.run(goal: "loop forever", maxSteps: 3)
            XCTFail("expected maxStepsExceeded")
        } catch PlannerError.maxStepsExceeded(_, let max) {
            XCTAssertEqual(max, 3)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testUnknownPrimitiveThrows() async {
        let llm = MockLLM(replies: [
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "teleport", arguments: [:])]),
        ])
        let planner = InnerLoopPlanner(llm: llm) { _, _ in
            IntentReply(id: "1", status: "ok", summary: "", result: [:], error: nil)
        }
        do {
            _ = try await planner.run(goal: "do a thing")
            XCTFail("expected unknownPrimitive")
        } catch PlannerError.unknownPrimitive(let name, _) {
            XCTAssertEqual(name, "teleport")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testActivateDispatchesCorrectIntent() async throws {
        let llm = MockLLM(replies: [
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "activate", arguments: ["bundleId": "com.whatsapp.WhatsApp"])]),
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "finish", arguments: ["summary": "opened whatsapp"])]),
        ])
        var capturedArgs: [String: Any] = [:]
        let planner = InnerLoopPlanner(llm: llm) { intent, options in
            if case .driveActivate = intent {
                capturedArgs = intent.wireArgs
            }
            XCTAssertFalse(options.returnToCaller)
            XCTAssertEqual(options.returnDelaySeconds, 0)
            return IntentReply(id: "1", status: "ok", summary: "activated", result: [:], error: nil)
        }
        let result = try await planner.run(goal: "open whatsapp")
        XCTAssertEqual(result, "opened whatsapp")
        XCTAssertEqual(capturedArgs["bundleId"] as? String, "com.whatsapp.WhatsApp")
    }

    func testForceToolsPassedThrough() async throws {
        let llm = MockLLM(replies: [
            LLMReply(text: "", toolCalls: [LLMToolCall(name: "finish", arguments: ["summary": "done"])]),
        ])
        let planner = InnerLoopPlanner(llm: llm) { _, _ in
            IntentReply(id: "1", status: "ok", summary: "", result: [:], error: nil)
        }
        _ = try await planner.run(goal: "test")
        XCTAssertEqual(llm.receivedTools.count, 1)
        XCTAssertNotNil(llm.receivedTools.first ?? nil)
    }
}
