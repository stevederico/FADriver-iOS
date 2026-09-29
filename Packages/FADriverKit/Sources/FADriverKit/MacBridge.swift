import Foundation
import Combine

/// WebSocket client for the FADriver daemon (`ws://localhost:8090`). Host apps
/// attach an `LLMProtocol` once, then call `send(_:options:)` for each intent.
///
/// Kept as `@MainActor ObservableObject` (not a true `actor`) so SwiftUI views
/// can bind directly to `isConnected` / `lastEvent` without an AsyncStream
/// shim. The override-field race the earlier version had is gone
/// — return-to-caller preference lives on per-send `SendOptions` now.
@MainActor
public final class MacBridge: ObservableObject {
    public static let shared = MacBridge()

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastEvent: String = "idle"

    /// The attached LLM. Weak so FADriverKit doesn't keep a host engine alive.
    /// The inner-loop planner reads this via `attachedLLM`.
    private weak var llm: LLMProtocol?

    private let endpoint: URL
    private var task: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<IntentReply, Error>] = [:]
    private var backoffSeconds: Double = 1.0
    private var reconnectTask: Task<Void, Never>?

    public init(endpoint: URL = URL(string: "ws://localhost:8090")!) {
        self.endpoint = endpoint
    }

    // MARK: - LLM attachment

    public func attach(llm: LLMProtocol) {
        self.llm = llm
        NSLog("[fadriver] mac_bridge_attached")
    }

    /// Access to the attached LLM. Returns nil if `attach(llm:)` hasn't been
    /// called or the host engine has been deallocated.
    public var attachedLLM: LLMProtocol? { llm }

    // MARK: - Connection

    public func connect() {
        guard task == nil else { return }
        openSocket()
    }

    public func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        failAllPending(error: MacBridgeError.disconnected)
        isConnected = false
    }

    private func openSocket() {
        let ws = URLSession.shared.webSocketTask(with: endpoint)
        task = ws
        ws.resume()
        NSLog("[fadriver] mac_bridge_connecting endpoint=\(endpoint.absoluteString)")
        isConnected = true
        backoffSeconds = 1.0
        lastEvent = "connecting"
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let msg):
                    self.handle(msg)
                    self.receiveLoop()
                case .failure(let err):
                    NSLog("[fadriver] mac_bridge_recv_err \(err.localizedDescription)")
                    self.isConnected = false
                    self.lastEvent = "disconnected"
                    self.failAllPending(error: MacBridgeError.disconnected)
                    self.task = nil
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        let delay = min(backoffSeconds, 16)
        backoffSeconds = min(backoffSeconds * 2, 16)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.reconnectTask = nil
                self?.openSocket()
            }
        }
    }

    // MARK: - Send

    /// Ship a typed intent to the FADriver daemon and await the reply. Throws
    /// `MacBridgeError.disconnected` if the socket is down and `.timeout` if
    /// the daemon doesn't answer within `options.timeout`.
    public func send(_ intent: Intent, options: SendOptions = .init()) async throws -> IntentReply {
        guard isConnected, let task else { throw MacBridgeError.disconnected }
        let id = UUID().uuidString
        var payload: [String: Any] = [
            "id": id,
            "intent": intent.wireName,
            "args": intent.wireArgs,
            "returnToCaller": options.returnToCaller,
            "returnDelaySeconds": options.returnDelaySeconds,
        ]
        if let bid = options.callerBundleId {
            payload["callerBundleId"] = bid
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { throw MacBridgeError.encodingFailed }
        NSLog("[fadriver] mac_bridge_send id=\(id) intent=\(intent.wireName)")
        lastEvent = "send \(intent.wireName)"

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(options.timeout * 1_000_000_000))
            await MainActor.run {
                if let cont = self?.pending.removeValue(forKey: id) {
                    cont.resume(throwing: MacBridgeError.timeout)
                }
            }
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            Task {
                do {
                    try await task.send(.string(text))
                } catch {
                    await MainActor.run {
                        if let c = self.pending.removeValue(forKey: id) {
                            c.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Receive

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        let text: String
        switch msg {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else {
            NSLog("[fadriver] mac_bridge_malformed_reply")
            return
        }
        let status = (obj["status"] as? String) ?? "error"
        let result = (obj["result"] as? [String: Any]) ?? [:]
        let errorInfo = obj["error"] as? [String: Any]
        let summary = (result["summary"] as? String) ?? ""
        NSLog("[fadriver] mac_bridge_recv id=\(id) status=\(status)")
        lastEvent = "recv \(status)"

        guard let cont = pending.removeValue(forKey: id) else {
            NSLog("[fadriver] mac_bridge: dropped reply for unknown id=\(id)")
            return
        }
        let reply = IntentReply(
            id: id,
            status: status,
            summary: summary,
            result: result,
            error: errorInfo.flatMap {
                IntentReply.ErrorInfo(
                    code: ($0["code"] as? String) ?? "unknown",
                    message: ($0["message"] as? String) ?? ""
                )
            }
        )
        cont.resume(returning: reply)
    }

    private func failAllPending(error: Error) {
        let copy = pending
        pending.removeAll()
        for (_, cont) in copy {
            cont.resume(throwing: error)
        }
    }
}
