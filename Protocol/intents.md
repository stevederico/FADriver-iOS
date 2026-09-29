# FADriver wire protocol

All communication happens over a single WebSocket connection at `ws://localhost:8090`. Frames are JSON text frames — one request per frame, one reply per frame.

This document is the source of truth for non-Swift clients. Swift clients can use `FADriverKit` (typed `Intent` + `MacBridge`) instead.

## Connection

1. Connect to `ws://localhost:8090`.
2. Send a JSON request frame.
3. Receive a JSON reply frame with matching `id`.

No handshake, no auth — the daemon is a local-only loopback service.

## Request shape

```json
{
  "id": "<client-generated UUID or string>",
  "intent": "<intent name>",
  "args": { ... intent-specific args ... },
  "returnToCaller": true,
  "returnDelaySeconds": 2.5,
  "callerBundleId": "com.example.myagent"
}
```

| Field | Type | Default | Purpose |
|---|---|---|---|
| `id` | string | required | Client-chosen correlation id echoed back in the reply |
| `intent` | string | required | One of the names below |
| `args` | object | `{}` | Intent-specific args |
| `returnToCaller` | bool | `true` | After the action completes, activate the caller's bundle so the user sees your app foregrounded again |
| `returnDelaySeconds` | number | `2.5` | Seconds to pause on the target app's final screen BEFORE activating the caller (so the user can see the result) |
| `callerBundleId` | string | daemon default | iOS bundle id to activate when `returnToCaller` is true. Lets any client override the daemon's default caller. |

## Reply shape

```json
{
  "id": "<same id as request>",
  "status": "ok",
  "result": { "summary": "Sent to Kate Bell" }
}
```

On error:

```json
{
  "id": "<same id>",
  "status": "error",
  "error": { "code": "wda_not_ready", "message": "WDA not reachable at http://localhost:8100" }
}
```

| Field | Type | Purpose |
|---|---|---|
| `id` | string | Echoes the request's `id` |
| `status` | string | `"ok"` or `"error"` |
| `result` | object | Present on `ok`. Contains at minimum `summary` (human-readable string). |
| `error` | object | Present on `error`. Has `code` + `message`. |

### Error codes

| Code | Meaning |
|---|---|
| `bad_args` | Request args failed validation |
| `bad_json` | Request JSON was malformed |
| `unknown_intent` | The `intent` name has no playbook |
| `unknown_drive_intent` | A `drive_*` name isn't in the daemon's dispatch table |
| `wda_not_ready` | WebDriverAgent not reachable at `http://localhost:8100` |
| `playbook_failed` | The playbook raised mid-flow (element not found, WDA HTTP error, …) |
| `drive_failed` | A `drive_*` primitive raised |
| `openurl_failed` | `mac_open_url` subprocess returned non-zero |
| `openurl_exception` | `mac_open_url` subprocess failed to spawn |
| `no_handler` | Server received a request before a handler was attached (shouldn't happen in practice) |

## Intents

### `ping`

Liveness probe. No args.

```json
{ "id": "1", "intent": "ping" }
→ { "id": "1", "status": "ok", "result": { "pong": true } }
```

### `send_message`

Drive iOS Messages.app: compose a new message, type recipient + body, tap Send.

```json
{
  "id": "1",
  "intent": "send_message",
  "args": {
    "contact": "+14155551212",
    "body": "running late",
    "displayName": "Kate Bell"
  }
}
```

| Arg | Type | Required | Notes |
|---|---|---|---|
| `contact` | string | yes | Phone digits (preferred — iOS reliably accepts them) or display name |
| `body` | string | yes | Message text |
| `displayName` | string | no | Used when disambiguating contact-picker suggestions |

### `navigate`

Drive iOS Maps.app: search for a destination, tap the top result, trigger the Directions action.

```json
{ "id": "1", "intent": "navigate", "args": { "destination": "Market Street" } }
```

| Arg | Type | Required |
|---|---|---|
| `destination` | string | yes |

### `add_reminder`

Drive iOS Reminders.app: tap New Reminder, type the title, commit.

```json
{ "id": "1", "intent": "add_reminder", "args": { "title": "pick up milk" } }
```

| Arg | Type | Required |
|---|---|---|
| `title` | string | yes |

### `mac_open_url`

Open a URL on the booted simulator via `xcrun simctl openurl booted <URL>`. Bypasses the caller's `UIApplication.shared.open(...)`, which foregrounds the calling app briefly before the target launches.

```json
{ "id": "1", "intent": "mac_open_url", "args": { "url": "https://example.com" } }
```

| Arg | Type | Required |
|---|---|---|
| `url` | string | yes |

### `drive_*` — generic app control

The five drive primitives let a client's LLM plan its own path through an app. Call one per turn.

#### `drive_activate`

Open an iOS app by bundle id.

```json
{ "id": "1", "intent": "drive_activate", "args": { "bundleId": "com.whatsapp.WhatsApp" } }
```

#### `drive_snapshot`

Return a compact list of visible interactive elements. Reply `result.summary` is a newline-separated numbered list; `result.count` is the total count. First 40 elements only.

```json
{ "id": "1", "intent": "drive_snapshot" }
→ {
  "id": "1", "status": "ok",
  "result": {
    "summary": "[0] Button: Compose\n[1] Cell: Kate Bell (555-1212)\n...",
    "count": 37
  }
}
```

#### `drive_click`

Tap an element by visible label or raw NSPredicate.

```json
{ "id": "1", "intent": "drive_click", "args": { "label": "Send" } }
{ "id": "1", "intent": "drive_click", "args": { "predicate": "name == 'composeButton'" } }
```

| Arg | Type | Required | Notes |
|---|---|---|---|
| `label` | string | one of | Tries `label ==`, then `label CONTAINS[c]`, then `name ==`. |
| `predicate` | string | one of | Raw NSPredicate. Advanced. |

Exactly one of `label` or `predicate` must be supplied.

#### `drive_type`

Type into the currently focused text field.

```json
{ "id": "1", "intent": "drive_type", "args": { "text": "hello" } }
```

## Examples

### wscat

```
$ wscat -c ws://localhost:8090
> {"id":"1","intent":"ping"}
< {"id":"1","status":"ok","result":{"pong":true}}

> {"id":"2","intent":"navigate","args":{"destination":"Market Street"},"returnToCaller":false}
< {"id":"2","status":"ok","result":{"summary":"Showed directions to Market Street"}}
```

### Python (websockets)

```python
import asyncio, json, websockets

async def run():
    async with websockets.connect("ws://localhost:8090", ping_interval=None) as ws:
        await ws.send(json.dumps({
            "id": "1",
            "intent": "send_message",
            "args": {"contact": "+14155551212", "body": "hi"},
            "returnToCaller": False,
        }))
        reply = json.loads(await ws.recv())
        print(reply)

asyncio.run(run())
```

### Swift (via FADriverKit)

```swift
import FADriverKit

let reply = try await MacBridge.shared.send(
    .sendMessage(contact: "+14155551212", body: "hi", displayName: "Kate"),
    options: .intermediate
)
print(reply.summary)
```
