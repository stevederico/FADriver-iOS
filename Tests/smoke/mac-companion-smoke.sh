#!/usr/bin/env bash
# Manual smoke test for the three playbooks against a running FADriver daemon.
# Prerequisites:
#   1. WDA running:    Scripts/launch-wda-sim.sh   (in a separate terminal)
#   2. Daemon running: swift run FADriver            (in a separate terminal)
#   3. Python `websockets` library: pip3 install websockets
#
# Usage:  Tests/smoke/mac-companion-smoke.sh
#
# Fires each of the three intents at ws://localhost:8090 and asserts status:ok
# within 45s. Not wired into any automatic harness — WDA + daemon are
# lifecycle-heavy external deps.

set -euo pipefail

python3 - <<'PY'
import asyncio, json, sys, websockets

async def send(payload, timeout=45):
    async with websockets.connect("ws://localhost:8090", ping_interval=None) as ws:
        await ws.send(json.dumps(payload))
        raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
        return json.loads(raw)

async def main():
    intents = [
        {"id": "smoke-msg", "intent": "send_message",
         "args": {"app": "messages", "contact": "Test Contact", "body": "hello from smoke test"},
         "returnToCaller": False},
        {"id": "smoke-rem", "intent": "add_reminder",
         "args": {"title": "smoke test reminder"},
         "returnToCaller": False},
        {"id": "smoke-map", "intent": "navigate",
         "args": {"destination": "Market Street"},
         "returnToCaller": False},
    ]
    failed = 0
    for intent in intents:
        print(f"--- {intent['intent']} ---", flush=True)
        try:
            reply = await send(intent)
            status = reply.get("status", "?")
            summary = (reply.get("result") or {}).get("summary") or reply.get("error", {}).get("message", "")
            print(f"  status={status}  summary={summary!r}", flush=True)
            if status != "ok":
                failed += 1
        except Exception as e:
            print(f"  ERROR: {e}", flush=True)
            failed += 1
        await asyncio.sleep(2)
    print(f"\nDONE {len(intents)-failed}/{len(intents)} passed", flush=True)
    sys.exit(1 if failed else 0)

asyncio.run(main())
PY
