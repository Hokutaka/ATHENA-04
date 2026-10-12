#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if ! command -v hare >/dev/null 2>&1; then
    echo "Hare not found. Run: nix-shell -p hare openssh coreutils python3" >&2
    exit 1
fi

mkdir -p .build-v062
# A separate cache ensures that build artifacts from the old layout aren't reused.
HARECACHE="$(mktemp -d)"
export HARECACHE
trap 'rm -rf -- "$HARECACHE"' EXIT

# Verify readable Windows probe is encoded by the Hare runtime, not pre-encoded in source.
python3 tools/check-probe.py
python3 tools/test-probe-structure.py
hare build -o .build-v062/athena cmd/cli/main.ha
hare build -o .build-v062/athena-web-v062 cmd/web/main.ha

# Fail closed if stale code is produced, instead of asking someone to debug a running server.
if ! grep -aFq 'ATHENA-04 / WEB CONSOLE v0.6.2 / WINDOWS READY' .build-v062/athena-web-v062; then
    echo 'CHECK FAILED: v0.6.2 startup marker absent from compiled server.' >&2
    exit 1
fi
if ! grep -aFq 'GET or guarded POST only' .build-v062/athena-web-v062; then
    echo 'CHECK FAILED: v0.6.2 HTTP route marker absent from compiled server.' >&2
    exit 1
fi
if grep -aFq 'GET requests only' .build-v062/athena-web-v062; then
    echo 'CHECK FAILED: old v0.3 HTTP code is present in compiled server.' >&2
    exit 1
fi

if ! grep -aFq 'WINDOWS PROBE OK' .build-v062/athena; then
    echo 'CHECK FAILED: Windows probe marker absent from CLI binary.' >&2
    exit 1
fi
# Output files are updated only when both programs built and passed the binary check.
cp .build-v062/athena ./athena
cp .build-v062/athena-web-v062 ./athena-web-v062
chmod +x ./athena ./athena-web-v062
printf '%s\n' 'ATHENA-04 v0.6.2 build checks passed.' 'Start with: ./athena-web-v062'
