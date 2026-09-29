<div align="center">

# FADriver-iOS

### an ios os-control daemon, swift client sdk, and runnable example

_FADriver = Full Agent Driver for iOS, formerly iosClaw_

</div>

<br />

## ⚡ Quick Start

```bash
# Terminal 1 — launch WebDriverAgent on the iPhone 17 Pro sim
./Scripts/launch-wda-sim.sh

# Terminal 2 — run the menubar daemon
swift run FADriver
```

The menubar shows `WDA: ready` + `WebSocket: listening :8090` when the daemon is up. Any client — Swift, Python, TypeScript, curl — can then speak the JSON protocol at `ws://localhost:8090`.

<br />

## ✨ What's Included

### 🛰️ **`FADriver.app` — the daemon**
- **macOS menubar** you build + run locally. Wraps WebDriverAgent, exposes the WebSocket API, shows live connection + activity state.
- **JSON intent protocol** at `ws://localhost:8090` — `send_message`, `navigate`, `add_reminder`, `mac_open_url`, plus the five `drive_*` primitives for generic app control.
- **Three playbooks shipped:** Messages, Reminders, Maps — each drives the target Apple app end-to-end + auto-activates the caller bundle on completion.

### 📦 **`FADriverKit` — Swift client SDK**
- **Typed `Intent` enum** with `wireName` + `wireArgs` — compile-time safety for Swift clients, zero lock-step with the daemon.
- **`MacBridge`** WebSocket client (`@MainActor ObservableObject`) with exponential-backoff reconnect, per-send `SendOptions`, and `attach(llm:)` for plugging in any `LLMProtocol`.
- **`ChainSplitter`** — peels `"text Kate and then open maps"` into sequential segments on `and then` / `then` / `;`.
- **`InnerLoopPlanner`** — generic `mac_drive` loop. Takes an `LLMProtocol` + a `MacBridge`; plans one WDA primitive per turn (activate / snapshot / click / type / finish) until the model says finish. Bring-your-own-model.
- **28 unit tests** — `swift test` under 10ms. Mocks `LLMProtocol` + `MacBridge.send` directly.

### 🧪 **`Examples/BasicClient` — runnable demo**
- **SwiftUI app** that wires `FADriverKit` into a real UI. Four intent buttons (ping / send_message / add_reminder / navigate), live connection indicator, reply panel.
- **`swift run BasicClient`** from the package directory. Code copies verbatim into an iOS target when you're ready — same SDK surface on both platforms.

### 📘 **`Protocol/intents.md` — wire-format spec**
- Every intent, arg shape, reply shape, and error code documented. Read this first if writing a non-Swift client.
- Examples included: `wscat`, Python `websockets`, Swift via `FADriverKit`.

<br />

## 🗂️ Architecture

```
App/                    ← the daemon (swift run FADriver)
  FADriverApp.swift      @main SwiftUI MenuBarExtra
  AppState.swift        Intent dispatcher + WDA probe + playbook registry
  MenuBar/              MenuContent view
  Server/               CompanionServer (Network.framework WebSocket), DriveDispatcher
  WDA/                  WDAClient (http://localhost:8100), WDALauncher
  Playbooks/            Messages, Reminders, Maps + shared auto-return helper

Packages/FADriverKit/    ← the Swift client SDK
  Sources/FADriverKit/   MacBridge, Intent, SendOptions, LLMProtocol, ChainSplitter,
                        InnerLoopPlanner, DrivePrimitives, IntentReply, errors
  Tests/FADriverKitTests Chain + Intent + InnerLoopPlanner tests with MockLLM

Examples/BasicClient/   ← SwiftUI demo (swift run BasicClient)
Protocol/intents.md     ← wire-format spec
Scripts/                ← launch-wda-sim.sh
Tests/smoke/            ← mac-companion-smoke.sh (3-playbook end-to-end)
vendor/WebDriverAgent/  ← submodule pin, appium/WebDriverAgent
```

### Wire flow

```
client ─JSON intent─→ ws://localhost:8090 ─→ CompanionServer
                                              → DriveDispatcher (drive_*)
                                              → Playbook (send_message/navigate/add_reminder)
                                              → WDAClient → http://localhost:8100 → WDA → iOS sim
                                              → auto-activate caller bundle (optional)
                                              ← JSON reply (id, status, summary)
```

### Swift client flow

```
LLMProtocol (your engine) ──┐
                            ├─→ InnerLoopPlanner.run(goal:) ──→ MacBridge.send(Intent, SendOptions)
MacBridge (WebSocket)    ──┘                                        │
                                                                    ▼
                                                          FADriver.app on ws://localhost:8090
```

<br />

## 🔧 Tech Stack

| Layer | Tech | Notes |
|---|---|---|
| **Daemon runtime** | Swift + SwiftUI MenuBarExtra, macOS 14+ | `swift run FADriver` — SPM executable |
| **WebSocket server** | Network.framework `NWListener` | built-in `NWProtocolWebSocket`, auto-reply pings |
| **UI automation** | [WebDriverAgent](https://github.com/appium/WebDriverAgent) | vendored submodule, W3C WebDriver subset |
| **Client SDK** | Swift Package, iOS 17+ / macOS 14+ | `URLSessionWebSocketTask`, Combine for `@Published` |
| **LLM seam** | `LLMProtocol` | bring-your-own: Cactus, MLX, remote API, whatever |

<br />

## 🧪 Testing

```bash
# SDK unit tests (~10ms, no daemon required)
cd Packages/FADriverKit && swift test

# Daemon + three-playbook smoke (needs WDA + daemon running)
./Scripts/launch-wda-sim.sh        # terminal 1
swift run FADriver                   # terminal 2
./Tests/smoke/mac-companion-smoke.sh
```

Unit tests cover `ChainSplitter` markers + case preservation, `Intent.wireArgs` round-trips for all nine intents, `InnerLoopPlanner` termination on finish + maxSteps + unknown primitive + activate-dispatch, and `SendOptions` defaults.

<br />

## 📚 Documentation

| File | Purpose |
|---|---|
| [Protocol/intents.md](Protocol/intents.md) | Wire-format spec — source of truth for non-Swift clients |
| [Packages/FADriverKit/Sources/FADriverKit/](Packages/FADriverKit/Sources/FADriverKit/) | Client SDK sources — read `Intent.swift` + `MacBridge.swift` first |
| [Examples/BasicClient/README.md](Examples/BasicClient/README.md) | Example client setup + iOS porting recipe |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

<br />

## 🙏 Acknowledgements

- [WebDriverAgent](https://github.com/appium/WebDriverAgent) — Appium's iOS WebDriver server, the only thing that makes this possible

<br />

## 🚀 Get Started

```bash
./Scripts/launch-wda-sim.sh &
swift run FADriver
```

<br />

## 📄 License

MIT. See [LICENSE](LICENSE).
