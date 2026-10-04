#!/bin/bash
# Exercises OmnieAgent/Core against a live Hermes. Linux only (the test
# WebSocket client uses Glibc sockets; Linux libcurl has no WebSockets).
#
# Needs: a Swift 5.10+ toolchain on PATH as `swiftc`, and a Hermes checkout
# installed in a Python 3.14 venv ($HERMES_PY, default: python3).
#
#   Tools/ProtocolHarness/run.sh            # all suites
#   Tools/ProtocolHarness/run.sh dashboard  # gateway | dashboard | openai
#
# It starts a scripted fake model on :18080, `hermes gateway run` (API
# server on :8642) and `hermes serve` (dashboard on :9119, basic auth),
# then drives every backend through streaming, tools, approvals, clarify,
# interrupt, history, rename and delete.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
HERMES_PY=${HERMES_PY:-python3}
HERMES_BIN=${HERMES_BIN:-hermes}

export HERMES_HOME="$WORK/home"
mkdir -p "$HERMES_HOME"
cat > "$HERMES_HOME/config.yaml" <<YAML
model:
  default: "fake-1"
  provider: "custom"
  base_url: "http://127.0.0.1:18080/v1"
  api_key: "sk-fake"
YAML
export API_SERVER_ENABLED=true API_SERVER_HOST=127.0.0.1 API_SERVER_PORT=8642
export API_SERVER_KEY=omnie-test-key-0123456789abcdef
export HERMES_DASHBOARD_BASIC_AUTH_USERNAME=omnie
export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=omnie-password-123
export HERMES_DASHBOARD_BASIC_AUTH_SECRET=omnie-secret-0123456789abcdef0123456789

cleanup() { kill $(jobs -p) 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

"$HERMES_PY" "$HERE/fake_llm.py" > "$WORK/fake.log" 2>&1 &
"$HERMES_BIN" gateway run > "$WORK/gateway.log" 2>&1 &
"$HERMES_BIN" serve --host 127.0.0.1 --port 9119 > "$WORK/serve.log" 2>&1 &
for _ in $(seq 1 60); do
  sleep 2
  curl -sf localhost:8642/health >/dev/null && curl -sf localhost:9119/api/health >/dev/null && break
done

SOURCES=$(find "$ROOT/OmnieAgent/Core" -name '*.swift')
mkdir -p "$WORK/src"
for f in $SOURCES; do
  # Swift 5.10 lacks type-level `nonisolated` (Swift 6.2); strip it for the harness.
  sed -E 's/^nonisolated (struct|enum|final class|class|actor|extension|protocol)/\1/' "$f" > "$WORK/src/$(basename "$f")"
done
EXTRA=""
[ "$(uname)" = "Linux" ] && EXTRA="$HERE/LinuxShims.swift"
swiftc -module-name OmnieCore "$WORK"/src/*.swift $EXTRA "$HERE/PosixSocket.swift" "$HERE/main.swift" -o "$WORK/harness"
"$WORK/harness" "$@"
