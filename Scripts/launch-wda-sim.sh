#!/usr/bin/env bash
# Build + launch WebDriverAgent on the iPhone 17 Pro simulator.
# Idempotent: re-running rebuilds (fast when cached) and re-launches.
#
# Usage:
#   Scripts/launch-wda-sim.sh
#
# Once running, WDA exposes http://localhost:8100. Leave this script in the foreground
# or Ctrl+C to stop WDA. The FADriver daemon probes /status and does not own the WDA
# process lifecycle.
#
# Environment overrides:
#   FADRIVER_SIM_UDID      target iOS Simulator UDID (default: the first booted simulator)
#   FADRIVER_WDA_PROJ      path to WebDriverAgent.xcodeproj (defaults to vendor submodule)
#   FADRIVER_WDA_DERIVED   derived-data dir for the WDA build

set -euo pipefail

UDID="${FADRIVER_SIM_UDID:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1 || true)}"
if [ -z "$UDID" ]; then
  echo "No booted simulator. Boot one, or set FADRIVER_SIM_UDID." >&2
  exit 1
fi
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WDA_PROJ="${FADRIVER_WDA_PROJ:-$REPO_ROOT/vendor/WebDriverAgent/WebDriverAgent.xcodeproj}"
DERIVED="${FADRIVER_WDA_DERIVED:-$REPO_ROOT/build/wda}"

if [ ! -d "$WDA_PROJ" ]; then
  echo "WebDriverAgent not found at $WDA_PROJ" >&2
  echo "Run: git submodule update --init --recursive" >&2
  echo "(or set FADRIVER_WDA_PROJ to an external WebDriverAgent.xcodeproj)" >&2
  exit 1
fi

echo "--- building WebDriverAgent for sim ($UDID) ---"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build-for-testing \
    -project "$WDA_PROJ" \
    -scheme WebDriverAgentRunner \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
  > /tmp/wda-build.log 2>&1

XCTESTRUN="$(find "$DERIVED/Build/Products" -name '*.xctestrun' | head -1)"
if [ -z "$XCTESTRUN" ]; then
  echo "no xctestrun produced — see /tmp/wda-build.log" >&2
  tail -40 /tmp/wda-build.log >&2
  exit 1
fi

echo "--- launching WDA ($XCTESTRUN) ---"
echo "--- http://localhost:8100 will be live once ready ---"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  exec xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN" \
    -destination "id=$UDID"
