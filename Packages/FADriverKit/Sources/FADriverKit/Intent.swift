import Foundation

/// Typed builder for the FADriver wire intents. Each case maps to a wire name
/// + args shape documented in `Protocol/intents.md`.
///
/// Keeping the wire surface as untyped JSON means the daemon parses a string
/// intent name, not a Swift enum — so this enum can grow without a daemon
/// re-release.
public enum Intent: Sendable {
    case ping

    // Playbook intents
    case sendMessage(contact: String, body: String, displayName: String? = nil)
    case navigate(destination: String)
    case addReminder(title: String)

    // Daemon-side helpers
    case openURL(String)

    // Drive primitives — the inner-loop planner's vocabulary
    case driveActivate(bundleId: String)
    case driveSnapshot
    case driveClick(label: String? = nil, predicate: String? = nil)
    case driveType(text: String)

    public var wireName: String {
        switch self {
        case .ping: return "ping"
        case .sendMessage: return "send_message"
        case .navigate: return "navigate"
        case .addReminder: return "add_reminder"
        case .openURL: return "mac_open_url"
        case .driveActivate: return "drive_activate"
        case .driveSnapshot: return "drive_snapshot"
        case .driveClick: return "drive_click"
        case .driveType: return "drive_type"
        }
    }

    public var wireArgs: [String: Any] {
        switch self {
        case .ping:
            return [:]
        case .sendMessage(let contact, let body, let displayName):
            var a: [String: Any] = ["contact": contact, "body": body]
            if let displayName { a["displayName"] = displayName }
            return a
        case .navigate(let destination):
            return ["destination": destination]
        case .addReminder(let title):
            return ["title": title]
        case .openURL(let url):
            return ["url": url]
        case .driveActivate(let bundleId):
            return ["bundleId": bundleId]
        case .driveSnapshot:
            return [:]
        case .driveClick(let label, let predicate):
            var a: [String: Any] = [:]
            if let label { a["label"] = label }
            if let predicate { a["predicate"] = predicate }
            return a
        case .driveType(let text):
            return ["text": text]
        }
    }
}
