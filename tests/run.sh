#!/bin/bash
# Runs the real pairing and remote classes (TVPairing, TVRemote, TVLink, TVTLS on mbedTLS) natively on the Mac against tools/mock_tv.py,
# then checks what the mock saw. Needs macOS (Xcode command line tools) and python3 with venv + network access for the first pip install.
#   tests/run.sh            uses ports 7466 (remote) and 7467 (pairing); override with MOCK_PORT
set -euo pipefail
cd "$(dirname "$0")/.."
B=build/test
PORT="${MOCK_PORT:-7466}"
export MOCK_CODE_FILE="$PWD/$B/mock_tv_code"
mkdir -p "$B/obj"

# 1. python environment for the mock TV
if [ ! -x build/venv/bin/python ]; then
    python3 -m venv build/venv
    build/venv/bin/pip install -q androidtvremote2 pyOpenSSL
fi

# 2. native build of mbedTLS + the app's networking classes + the test
CFLAGS=(-DMBEDTLS_CONFIG_FILE='"hn_mbedtls_config.h"' -Ithird_party -Ithird_party/mbedtls/include -Ithird_party/mbedtls/library -Isrc -O1 -w)
for f in third_party/mbedtls/library/*.c src/TVTLS.c; do
    o="$B/obj/$(basename "$f" .c).o"
    if [ ! "$o" -nt "$f" ]; then
        xcrun clang "${CFLAGS[@]}" -c "$f" -o "$o" &
        while [ "$(jobs -r | wc -l)" -ge 8 ]; do sleep 0.1; done
    fi
done
wait
xcrun clang -fobjc-arc -O0 -Wno-deprecated-declarations -Isrc -framework Foundation \
    tests/flowtest.m src/TVStore.m src/TVPairing.m src/TVRemote.m src/TVLink.m src/TVProto.m "$B"/obj/*.o -o "$B/flowtest"

# 3. the mock TV: both ports must be free
python3 - "$PORT" <<'PY'
import socket, sys
for p in (int(sys.argv[1]), int(sys.argv[1]) + 1):
    s = socket.socket()
    try: s.bind(("0.0.0.0", p))
    except OSError: sys.exit(f"port {p} is in use; set MOCK_PORT to another value")
    finally: s.close()
PY
MOCK_PID=""
# flowtest keeps its throw-away client identity in the "flowtest" defaults domain; remove it afterwards
trap '[ -n "$MOCK_PID" ] && { kill "$MOCK_PID" || true; wait "$MOCK_PID" || true; } 2>/dev/null; defaults delete flowtest 2>/dev/null; true' EXIT
build/venv/bin/python -u tools/mock_tv.py --host 127.0.0.1 --port "$PORT" --name "Test TV" > "$B/mock.log" 2>&1 &
MOCK_PID=$!
for _ in $(seq 1 50); do grep -q "mock TV on" "$B/mock.log" 2>/dev/null && break; sleep 0.2; done

# 4. run, then verify from the mock's side
"$B/flowtest" "127.0.0.1:$PORT" | tee "$B/flowtest.log"
sleep 0.5
fail=0
expect() { grep -q "$1" "$B/mock.log" || { echo "FAIL: mock did not see: $2"; fail=1; }; }
expect "pairing: OK" "a successful pairing"
expect "key: KEYCODE_DPAD_UP SHORT" "DPAD_UP"
expect "key: KEYCODE_DPAD_CENTER SHORT" "DPAD_CENTER"
expect "key: KEYCODE_DPAD_RIGHT START_LONG" "DPAD_RIGHT held"
expect "key: KEYCODE_DPAD_RIGHT END_LONG" "DPAD_RIGHT released"
expect "launch: https://www.youtube.com" "the app link"
grep -q "^done$" "$B/flowtest.log" || { echo "FAIL: flowtest did not finish"; fail=1; }
[ "$fail" = 0 ] && echo "ALL OK"
exit "$fail"
