import Foundation

/// Per-send options that used to be racy mutable fields on `MacBridge`. Now
/// passed explicitly so two concurrent callers can't clobber each other's
/// return-to-caller preference mid-await.
public struct SendOptions: Sendable {
    /// Whether the daemon should activate the caller's bundle when the playbook
    /// finishes. `false` lets chain intermediate steps avoid visible flashes
    /// between hops.
    public var returnToCaller: Bool
    /// Seconds to pause on the target app's final screen BEFORE activating the
    /// caller. Lets the user see the result of the action.
    public var returnDelaySeconds: Double
    /// Bundle id to activate on return. When nil, daemon falls back to its
    /// configured default caller bundle (see `Protocol/intents.md`).
    public var callerBundleId: String?
    /// Seconds to wait for the daemon's reply before giving up and throwing.
    public var timeout: TimeInterval

    public init(returnToCaller: Bool = true, returnDelaySeconds: Double = 2.5, callerBundleId: String? = nil, timeout: TimeInterval = 45) {
        self.returnToCaller = returnToCaller
        self.returnDelaySeconds = returnDelaySeconds
        self.callerBundleId = callerBundleId
        self.timeout = timeout
    }

    /// Convenience for intermediate steps in a chain/workflow: no return-flip,
    /// no delay, default timeout.
    public static let intermediate = SendOptions(returnToCaller: false, returnDelaySeconds: 0)
}
