import Foundation

/// Handles the generic `drive_*` intent family — each intent is one WDA primitive,
/// not a whole flow. Keeps playbooks + drive primitives in separate dispatch
/// branches: playbooks are deterministic recipes, drive primitives are steps a
/// caller's own planner (LLM inner loop) plans itself.
struct DriveDispatcher {
    let wda: WDAClient

    func handle(_ intent: IntentRequest) async -> IntentReply {
        let args = intent.stringArgs
        do {
            switch intent.intent {
            case "drive_activate":
                guard let bundleId = args["bundleId"], !bundleId.isEmpty else {
                    return .error(id: intent.id, code: "bad_args", message: "bundleId required")
                }
                try await wda.activate(bundleId: bundleId)
                NSLog("[fadriver-mac] drive_activate bundle=\(bundleId)")
                return .ok(id: intent.id, result: ["summary": "activated \(bundleId)"])

            case "drive_snapshot":
                let raw = try await wda.source()
                let elements = Self.extractElements(from: raw)
                NSLog("[fadriver-mac] drive_snapshot count=\(elements.count)")
                let lines = elements.enumerated().prefix(40).map { idx, el -> String in
                    let label = (el["label"] as? String) ?? (el["value"] as? String) ?? ""
                    let type = (el["type"] as? String) ?? "?"
                    return "[\(idx)] \(type): \(label)"
                }
                let text = lines.isEmpty ? "(screen appears empty)" : lines.joined(separator: "\n")
                return .ok(id: intent.id, result: [
                    "summary": text,
                    "count": elements.count
                ])

            case "drive_click":
                let label = args["label"] ?? ""
                let predicate = args["predicate"] ?? ""
                let eid: String
                if !predicate.isEmpty {
                    eid = try await wda.findElement(predicate: predicate)
                } else if !label.isEmpty {
                    if let exact = try? await wda.findElement(predicate: "label == '\(Self.sanitize(label))'") {
                        eid = exact
                    } else if let fuzzy = try? await wda.findElement(predicate: "label CONTAINS[c] '\(Self.sanitize(label))'") {
                        eid = fuzzy
                    } else if let byName = try? await wda.findElement(predicate: "name == '\(Self.sanitize(label))'") {
                        eid = byName
                    } else {
                        throw WDAError.elementNotFound("label: \(label)")
                    }
                } else {
                    return .error(id: intent.id, code: "bad_args", message: "label or predicate required")
                }
                try await wda.click(elementId: eid)
                NSLog("[fadriver-mac] drive_click label=\(label) pred=\(predicate)")
                return .ok(id: intent.id, result: ["summary": "clicked \(label.isEmpty ? predicate : label)"])

            case "drive_type":
                guard let text = args["text"], !text.isEmpty else {
                    return .error(id: intent.id, code: "bad_args", message: "text required")
                }
                try await wda.typeText(text)
                NSLog("[fadriver-mac] drive_type text=\(text)")
                return .ok(id: intent.id, result: ["summary": "typed '\(text)'"])

            default:
                return .error(id: intent.id, code: "unknown_drive_intent", message: "unknown: \(intent.intent)")
            }
        } catch {
            NSLog("[fadriver-mac] drive_dispatch_error intent=\(intent.intent) err=\(error)")
            return .error(id: intent.id, code: "drive_failed", message: error.localizedDescription)
        }
    }

    private static func extractElements(from root: [String: Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        walk(root, into: &out)
        return out
    }

    private static func walk(_ node: Any, into out: inout [[String: Any]]) {
        guard let dict = node as? [String: Any] else { return }
        let type = (dict["type"] as? String) ?? ""
        let label = (dict["label"] as? String) ?? ""
        let value = (dict["value"] as? String) ?? ""
        let name = (dict["name"] as? String) ?? ""
        let hittable = (dict["isVisible"] as? String) == "true" || (dict["isVisible"] as? Int) == 1
            || (dict["visible"] as? Bool) == true

        let isInteresting: Bool = {
            let text = label.isEmpty ? (value.isEmpty ? name : value) : label
            if text.isEmpty { return false }
            let interactive = ["Button", "Cell", "TextField", "SecureTextField", "SearchField",
                               "Link", "StaticText", "Switch", "Slider"]
            let short = type.hasPrefix("XCUIElementType") ? String(type.dropFirst("XCUIElementType".count)) : type
            return interactive.contains(short)
        }()

        if isInteresting {
            let short = type.hasPrefix("XCUIElementType") ? String(type.dropFirst("XCUIElementType".count)) : type
            let text = label.isEmpty ? (value.isEmpty ? name : value) : label
            out.append([
                "type": short,
                "label": text,
                "hittable": hittable,
            ])
        }

        if let children = dict["children"] as? [Any] {
            for child in children { walk(child, into: &out) }
        }
    }

    /// NSPredicate single-quote escape: double the apostrophes.
    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }
}
