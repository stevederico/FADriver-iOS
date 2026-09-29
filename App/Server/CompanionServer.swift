import Foundation
import Network

struct IntentRequest: Decodable {
    let id: String
    let intent: String
    let args: [String: AnyCodable]?
    /// Whether the daemon should activate the caller's bundle id when the
    /// playbook finishes, so the user sees the calling app foregrounded again.
    /// Default: true. Wire name intentionally generic — any client can be the
    /// caller.
    let returnToCaller: Bool?
    /// The bundle id the daemon should activate on return. If nil and
    /// `returnToCaller` is true, auto-return is skipped.
    /// Lets any client specify its own bundle without a daemon-side rename.
    let callerBundleId: String?
    /// Seconds to pause AFTER the playbook completes its task but BEFORE
    /// activating the caller. Lets the user see the result of the action on
    /// screen. Default 0 (snap back instantly).
    let returnDelaySeconds: Double?

    var stringArgs: [String: String] {
        var out: [String: String] = [:]
        for (k, v) in args ?? [:] {
            if let s = v.value as? String { out[k] = s }
        }
        return out
    }
}

struct IntentReply: Encodable {
    let id: String
    let status: String
    let result: [String: AnyCodable]?
    let error: ErrorBody?

    struct ErrorBody: Encodable {
        let code: String
        let message: String
    }

    static func ok(id: String, result: [String: Any]) -> IntentReply {
        IntentReply(id: id, status: "ok", result: result.mapValues { AnyCodable($0) }, error: nil)
    }

    static func error(id: String, code: String, message: String) -> IntentReply {
        IntentReply(id: id, status: "error", result: nil, error: .init(code: code, message: message))
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self.value = b }
        else if let i = try? c.decode(Int.self) { self.value = i }
        else if let d = try? c.decode(Double.self) { self.value = d }
        else if let s = try? c.decode(String.self) { self.value = s }
        else if let a = try? c.decode([AnyCodable].self) { self.value = a.map { $0.value } }
        else if let o = try? c.decode([String: AnyCodable].self) { self.value = o.mapValues { $0.value } }
        else { self.value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]: try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try c.encode(v.mapValues { AnyCodable($0) })
        default: try c.encodeNil()
        }
    }
}

final class CompanionServer {
    let port: NWEndpoint.Port
    var onIntent: ((IntentRequest) async -> IntentReply)?
    var onListening: ((Bool) -> Void)?

    private var listener: NWListener?

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        let params = NWParameters(tls: nil)
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let listener = try NWListener(using: params, on: port)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onListening?(true)
                NSLog("[fadriver-mac] ws listening on :\(self?.port.rawValue ?? 0)")
            case .failed(let err):
                self?.onListening?(false)
                NSLog("[fadriver-mac] ws listener failed: \(err)")
            case .cancelled:
                self?.onListening?(false)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            NSLog("[fadriver-mac] ws conn_open")
            conn.stateUpdateHandler = { state in
                switch state {
                case .failed(let err): NSLog("[fadriver-mac] ws conn_failed: \(err)")
                case .cancelled: NSLog("[fadriver-mac] ws conn_cancelled")
                default: break
                }
            }
            conn.start(queue: .main)
            self?.receiveLoop(on: conn)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func receiveLoop(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, isComplete, err in
            if let err {
                NSLog("[fadriver-mac] ws recv_err: \(err)")
                return
            }
            guard let self else { return }
            if let data, let context,
               let md = context.protocolMetadata.first(where: { $0 is NWProtocolWebSocket.Metadata }) as? NWProtocolWebSocket.Metadata,
               md.opcode == .text {
                Task { await self.handle(data: data, on: conn) }
            } else if let context, let md = context.protocolMetadata.first(where: { $0 is NWProtocolWebSocket.Metadata }) as? NWProtocolWebSocket.Metadata,
                      md.opcode == .close {
                NSLog("[fadriver-mac] ws conn_close_frame")
                return
            }
            self.receiveLoop(on: conn)
        }
    }

    private func handle(data: Data, on conn: NWConnection) async {
        let decoder = JSONDecoder()
        let reply: IntentReply
        do {
            let req = try decoder.decode(IntentRequest.self, from: data)
            NSLog("[fadriver-mac] ws intent_recv id=\(req.id) intent=\(req.intent)")
            reply = await onIntent?(req) ?? IntentReply.error(id: req.id, code: "no_handler", message: "no handler attached")
        } catch {
            reply = IntentReply.error(id: "0", code: "bad_json", message: "\(error)")
        }
        send(reply: reply, on: conn)
    }

    private func send(reply: IntentReply, on conn: NWConnection) {
        let encoder = JSONEncoder()
        guard let payload = try? encoder.encode(reply) else { return }
        let md = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "reply", metadata: [md])
        NSLog("[fadriver-mac] ws reply_send id=\(reply.id) status=\(reply.status) bytes=\(payload.count)")
        conn.send(content: payload, contentContext: ctx, isComplete: true, completion: .contentProcessed { err in
            if let err {
                NSLog("[fadriver-mac] ws send_err id=\(reply.id): \(err)")
            } else {
                NSLog("[fadriver-mac] ws reply_sent id=\(reply.id)")
            }
        })
    }
}
