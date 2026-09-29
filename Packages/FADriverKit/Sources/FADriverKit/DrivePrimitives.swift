import Foundation

/// The 5 primitives the inner-loop planner exposes to the LLM: activate,
/// snapshot, click, type, finish. Kept small — Gemma 4 E2B is most reliable
/// when picking from ≤5 tools per turn.
enum DrivePrimitives {
    static let all: [[String: Any]] = [
        [
            "name": "activate",
            "description": "Open an iOS app by bundle ID (e.g. com.whatsapp.WhatsApp).",
            "parameters": [
                "type": "object",
                "properties": ["bundleId": ["type": "string", "description": "iOS app bundle identifier."]],
                "required": ["bundleId"]
            ]
        ],
        [
            "name": "snapshot",
            "description": "Read the current screen. Returns a list of visible interactive elements with labels.",
            "parameters": ["type": "object", "properties": [:]]
        ],
        [
            "name": "click",
            "description": "Tap an element by its visible label or name.",
            "parameters": [
                "type": "object",
                "properties": ["label": ["type": "string", "description": "Visible label, name, or static text on the element."]],
                "required": ["label"]
            ]
        ],
        [
            "name": "type",
            "description": "Type text into the currently focused text field.",
            "parameters": [
                "type": "object",
                "properties": ["text": ["type": "string", "description": "The text to type."]],
                "required": ["text"]
            ]
        ],
        [
            "name": "finish",
            "description": "End the task and report what was accomplished.",
            "parameters": [
                "type": "object",
                "properties": ["summary": ["type": "string", "description": "Short human-readable summary of what happened."]],
                "required": ["summary"]
            ]
        ],
    ]

    static let json: String = {
        (try? JSONSerialization.data(withJSONObject: all))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }()

    static let systemPrompt: String = """
    /no_think You are an iOS automation driver. You control an iPhone by calling ONE primitive per turn.

    Available primitives:
    - activate(bundleId): open an iOS app by its bundle ID.
      Examples: com.whatsapp.WhatsApp, com.burbn.instagram, com.tinyspeck.chatlyio, \
    com.ubercab.UberClient, com.apple.MobileSMS.
    - snapshot(): read the current screen. Returns a numbered list of visible elements and their labels.
    - click(label): tap an element by its visible label or name.
    - type(text): type text into the currently focused field.
    - finish(summary): end the task and report what you accomplished.

    Rules:
    - Call ONE primitive per turn. Never batch multiple tool calls.
    - Start with snapshot if you don't know the screen state.
    - After activate, always call snapshot before clicking.
    - Call finish as soon as the goal is satisfied.
    """
}
