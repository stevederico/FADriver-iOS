# BasicClient — minimal FADriverKit example

A small SwiftUI app that demonstrates the four core `FADriverKit` intent shapes against a running FADriver daemon: `ping`, `send_message`, `add_reminder`, `navigate`.

## Run it

```bash
# Terminal 1 — start the FADriver daemon
cd ~/Desktop/projects/FADriver
Scripts/launch-wda-sim.sh    # or skip if WDA is already running
swift run FADriver

# Terminal 2 — run the example client
cd Examples/BasicClient
swift run BasicClient
```

A window opens with four buttons (ping, send message, add reminder, navigate). The header shows live connection state against the daemon at `ws://localhost:8090`.

## What it shows

- Attach-and-connect pattern: `MacBridge.shared.connect()` in the app's `init()` block.
- `@StateObject` binding for `isConnected` + `lastEvent` so SwiftUI re-renders on daemon state changes.
- Typed intent builders (`.ping`, `.sendMessage(...)`, `.addReminder(...)`, `.navigate(...)`) — no raw strings.
- `SendOptions` per call — here `init(returnToCaller: false)` so the example window stays focused after the daemon drives iOS.
- Reply handling with `IntentReply.status` / `.summary` / `.error`.

## What it deliberately omits

- **LLM-driven `mac_drive`** — the generic "drive any iOS app" flow needs an `LLMProtocol` implementation (Cactus, MLX, remote API, …). Out of scope for a minimal example. See `FADriverKit.InnerLoopPlanner` to wire it up.
- **ChainSplitter** — one-shot intents don't chain. Multi-step chains are a host-app concern.
- **Error recovery / reconnect UI** — `MacBridge` reconnects with exponential backoff automatically; a production app would surface a reconnect indicator.

## Platform notes

This example builds as a **macOS** executable because SwiftPM doesn't produce iOS `.app` bundles. The `FADriverKit` API is identical on iOS — copy `ContentView.swift` into an Xcode iOS app target that links `FADriverKit` as a local-path SPM dependency and it works unchanged.

From the iOS Simulator, `localhost:8090` routes to the host Mac's loopback so the daemon is reachable as-is. From a physical iOS device, replace `ws://localhost:8090` with `ws://<mac-lan-ip>:8090` when constructing `MacBridge(endpoint:)`.
