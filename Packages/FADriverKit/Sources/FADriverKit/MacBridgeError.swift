import Foundation

public enum MacBridgeError: LocalizedError {
    case disconnected
    case timeout
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .disconnected: return "FADriver daemon not connected"
        case .timeout: return "FADriver daemon timed out"
        case .encodingFailed: return "failed to encode intent"
        }
    }
}
