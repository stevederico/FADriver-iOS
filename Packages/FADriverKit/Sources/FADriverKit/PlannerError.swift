import Foundation

public enum PlannerError: LocalizedError {
    case emptyGoal
    case serializationFailed(step: Int)
    case noToolCall(step: Int, text: String)
    case unknownPrimitive(name: String, step: Int)
    case maxStepsExceeded(goal: String, max: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyGoal:
            return "inner loop: goal is empty"
        case .serializationFailed(let step):
            return "inner loop: history serialization failed at step \(step)"
        case .noToolCall(let step, _):
            return "inner loop: no tool call at step \(step)"
        case .unknownPrimitive(let name, let step):
            return "inner loop: unknown primitive '\(name)' at step \(step)"
        case .maxStepsExceeded(let goal, let max):
            return "inner loop: exceeded \(max) steps (goal: \(goal))"
        }
    }
}
