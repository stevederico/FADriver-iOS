import Foundation

/// Client-side view of a reply from the FADriver daemon. Mirrors the wire
/// protocol documented in `Protocol/intents.md`: status is "ok" or "error",
/// result + error are mutually exclusive per status.
public struct IntentReply: @unchecked Sendable {
    public let id: String
    public let status: String
    public let summary: String
    public let result: [String: Any]
    public let error: ErrorInfo?

    public struct ErrorInfo: Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public init(id: String, status: String, summary: String, result: [String: Any], error: ErrorInfo?) {
        self.id = id
        self.status = status
        self.summary = summary
        self.result = result
        self.error = error
    }

    public var isOK: Bool { status == "ok" }
}
