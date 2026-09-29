import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var wdaReady = false
    @Published var wsListening = false
    @Published var lastEvent: String = "idle"
    @Published var intentCount = 0

    private let server: CompanionServer
    private let launcher: WDALauncher
    let wda: WDAClient

    init() {
        self.wda = WDAClient(baseURL: URL(string: "http://localhost:8100")!)
        self.server = CompanionServer(port: 8090)
        self.launcher = WDALauncher()
        Task { await start() }
    }

    func start() async {
        launcher.onReady = { [weak self] in
            Task { @MainActor in self?.wdaReady = true; self?.lastEvent = "wda ready" }
        }
        launcher.start()

        server.onIntent = { [weak self] intent in
            guard let self else { return IntentReply.error(id: intent.id, code: "no_self", message: "no self") }
            return await self.handle(intent)
        }
        server.onListening = { [weak self] listening in
            Task { @MainActor in self?.wsListening = listening }
        }
        do {
            try server.start()
        } catch {
            lastEvent = "ws start failed: \(error)"
        }

        Task { await pollWDA() }
    }

    private func pollWDA() async {
        while !wdaReady {
            if await wda.isUp() {
                wdaReady = true
                lastEvent = "wda ready (probed)"
                break
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private let playbooks: [String: Playbook] = {
        let list: [Playbook] = [MessagesPlaybook(), RemindersPlaybook(), MapsPlaybook()]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.intent, $0) })
    }()

    private lazy var driveDispatcher = DriveDispatcher(wda: wda)

    func handle(_ intent: IntentRequest) async -> IntentReply {
        intentCount += 1
        lastEvent = "intent: \(intent.intent)"
        if intent.intent == "ping" {
            return .ok(id: intent.id, result: ["pong": true])
        }
        // mac_open_url: shell out to `xcrun simctl openurl booted <URL>` so the
        // sim opens the URL WITHOUT the caller calling UIApplication.shared.open.
        // That iOS-level call foregrounds the calling app briefly before the
        // target launches (visible as a flash between workflow steps). Routing
        // via the Mac host bypasses the caller app entirely.
        if intent.intent == "mac_open_url" {
            let url = intent.stringArgs["url"] ?? ""
            guard !url.isEmpty else {
                return .error(id: intent.id, code: "bad_args", message: "url required")
            }
            let process = Process()
            process.launchPath = "/usr/bin/xcrun"
            process.arguments = ["simctl", "openurl", "booted", url]
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    NSLog("[fadriver-mac] mac_open_url ok url=\(url)")
                    return .ok(id: intent.id, result: ["summary": "opened \(url)"])
                } else {
                    let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    NSLog("[fadriver-mac] mac_open_url failed status=\(process.terminationStatus) msg=\(msg)")
                    return .error(id: intent.id, code: "openurl_failed", message: msg)
                }
            } catch {
                return .error(id: intent.id, code: "openurl_exception", message: error.localizedDescription)
            }
        }
        // drive_* intents are caller-planned primitives, not playbooks.
        if intent.intent.hasPrefix("drive_") {
            guard wdaReady else {
                return .error(id: intent.id, code: "wda_not_ready", message: "WDA not reachable at http://localhost:8100")
            }
            return await driveDispatcher.handle(intent)
        }
        guard let playbook = playbooks[intent.intent] else {
            return .error(id: intent.id, code: "unknown_intent", message: "no playbook for \(intent.intent)")
        }
        guard wdaReady else {
            return .error(id: intent.id, code: "wda_not_ready", message: "WDA not reachable at http://localhost:8100")
        }
        do {
            let summary = try await playbook.run(
                args: intent.stringArgs,
                wda: wda,
                returnToCaller: intent.returnToCaller ?? true,
                returnDelaySeconds: intent.returnDelaySeconds ?? 2.5,
                callerBundleId: intent.callerBundleId
            )
            return .ok(id: intent.id, result: ["summary": summary])
        } catch {
            NSLog("[fadriver-mac] playbook_error intent=\(intent.intent) err=\(error)")
            return .error(id: intent.id, code: "playbook_failed", message: error.localizedDescription)
        }
    }
}
