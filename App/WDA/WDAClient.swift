import Foundation

final class WDAClient {
    let baseURL: URL
    private var sessionId: String?
    private let urlSession: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: cfg)
    }

    func isUp() async -> Bool {
        let url = baseURL.appendingPathComponent("status")
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (data, _) = try await urlSession.data(for: req)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = obj["value"] as? [String: Any],
               let state = value["state"] as? String {
                return state == "success"
            }
        } catch {}
        return false
    }

    func ensureSession() async throws -> String {
        if let s = sessionId { return s }
        let url = baseURL.appendingPathComponent("session")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "capabilities": ["alwaysMatch": ["platformName": "iOS"]]
        ])
        let (data, _) = try await urlSession.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = (obj["sessionId"] as? String) ?? ((obj["value"] as? [String: Any])?["sessionId"] as? String)
        else { throw WDAError.missingSessionId }
        sessionId = sid
        NSLog("[fadriver-mac] wda session=\(sid)")
        return sid
    }

    func activate(bundleId: String) async throws {
        let sid = try await ensureSession()
        _ = try await post(path: "session/\(sid)/wda/apps/launch", body: ["bundleId": bundleId])
    }

    func terminate(bundleId: String) async throws {
        let sid = try await ensureSession()
        _ = try await post(path: "session/\(sid)/wda/apps/terminate", body: ["bundleId": bundleId])
    }

    /// Find an element by predicate — returns the WDA element UUID.
    func findElement(predicate: String) async throws -> String {
        let sid = try await ensureSession()
        let json = try await post(path: "session/\(sid)/element", body: [
            "using": "predicate string",
            "value": predicate
        ])
        if let value = json["value"] as? [String: Any], let elementId = value["ELEMENT"] as? String {
            return elementId
        }
        throw WDAError.elementNotFound(predicate)
    }

    /// Find by accessibility id (matches SwiftUI's .accessibilityIdentifier).
    func findByAccessibilityId(_ aid: String) async throws -> String {
        let sid = try await ensureSession()
        let json = try await post(path: "session/\(sid)/element", body: [
            "using": "accessibility id",
            "value": aid
        ])
        if let value = json["value"] as? [String: Any], let elementId = value["ELEMENT"] as? String {
            return elementId
        }
        throw WDAError.elementNotFound("accessibility id: \(aid)")
    }

    /// Find by label (element name / visible text).
    func findByLabel(_ label: String) async throws -> String {
        let sid = try await ensureSession()
        let json = try await post(path: "session/\(sid)/element", body: [
            "using": "link text",
            "value": "label=\(label)"
        ])
        if let value = json["value"] as? [String: Any], let elementId = value["ELEMENT"] as? String {
            return elementId
        }
        throw WDAError.elementNotFound("label: \(label)")
    }

    func click(elementId: String) async throws {
        let sid = try await ensureSession()
        _ = try await post(path: "session/\(sid)/element/\(elementId)/click", body: [:])
    }

    /// Clear a text field's contents — standard WebDriver `POST /element/:id/clear`.
    /// Wraps WDA's `XCUIElement.clearText` which does the proper tap-to-focus +
    /// select-all + delete, so a subsequent `typeText` writes cleanly instead of
    /// appending to any leftover draft.
    func clear(elementId: String) async throws {
        let sid = try await ensureSession()
        _ = try await post(path: "session/\(sid)/element/\(elementId)/clear", body: [:])
    }

    func typeText(_ text: String) async throws {
        let sid = try await ensureSession()
        _ = try await post(path: "session/\(sid)/wda/keys", body: ["value": Array(text).map { String($0) }])
    }

    /// Return the current accessibility-tree source as JSON. Used by `drive_snapshot`
    /// to ship the screen state back to the caller. The full tree can be tens of KB —
    /// callers should filter to hittable / labeled elements before shipping.
    func source() async throws -> [String: Any] {
        let sid = try await ensureSession()
        let base = baseURL.appendingPathComponent("session/\(sid)/source")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = comps.url else { throw WDAError.httpFailure(status: -1, body: "bad source url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw WDAError.httpFailure(status: status, body: bodyStr)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Wait for an element matching the predicate, polling every 300ms up to `timeout` seconds.
    func waitFor(predicate: String, timeout: Double = 5.0) async throws -> String {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let eid = try? await findElement(predicate: predicate) { return eid }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        throw WDAError.elementNotFound(predicate)
    }

    @discardableResult
    private func post(path: String, body: [String: Any], retryOnSessionDeath: Bool = true) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body.isEmpty ? [:] : body)
        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            // "Session does not exist" happens when another client created/deleted a
            // session and ours got evicted. Drop cached sid and retry once.
            if retryOnSessionDeath, bodyStr.contains("Session does not exist"), let oldSid = sessionId, path.contains("session/\(oldSid)") {
                NSLog("[fadriver-mac] wda session \(oldSid) dead; re-establishing")
                sessionId = nil
                let newSid = try await ensureSession()
                let rewritten = path.replacingOccurrences(of: "session/\(oldSid)", with: "session/\(newSid)")
                return try await post(path: rewritten, body: body, retryOnSessionDeath: false)
            }
            throw WDAError.httpFailure(status: status, body: bodyStr)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

enum WDAError: LocalizedError {
    case missingSessionId
    case elementNotFound(String)
    case httpFailure(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingSessionId: return "WDA returned no sessionId"
        case .elementNotFound(let q): return "element not found: \(q)"
        case .httpFailure(let s, let b): return "HTTP \(s): \(b.prefix(200))"
        }
    }
}
