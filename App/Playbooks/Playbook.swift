import Foundation

/// A named sequence of WDA calls that drives one iOS app to completion.
protocol Playbook {
    var intent: String { get }
    func run(args: [String: String], wda: WDAClient, returnToCaller: Bool, returnDelaySeconds: Double, callerBundleId: String?) async throws -> String
}

enum PlaybookError: LocalizedError {
    case missingArg(String)
    var errorDescription: String? {
        switch self {
        case .missingArg(let a): return "missing arg: \(a)"
        }
    }
}

extension Playbook {
    /// Auto-return to the caller at the end of the playbook so the user can
    /// chain the next command without touching the phone. If `delaySeconds`
    /// is > 0, pause that long on the target app's final screen first so the
    /// user can see the result of the action (message delivered, reminder
    /// added, route shown) before the foreground flips.
    func autoReturn(wda: WDAClient, enabled: Bool, delaySeconds: Double = 0, callerBundleId: String? = nil) async throws {
        guard enabled else { return }
        if delaySeconds > 0 {
            NSLog("[fadriver-mac] auto_return_pause seconds=\(delaySeconds)")
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        guard let bundleId = callerBundleId else {
            NSLog("[fadriver-mac] auto_return skipped: client sent no callerBundleId")
            return
        }
        try await wda.activate(bundleId: bundleId)
        NSLog("[fadriver-mac] auto_return bundle=\(bundleId)")
    }
}
