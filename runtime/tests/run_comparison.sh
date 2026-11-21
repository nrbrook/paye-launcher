#!/bin/bash
# Compares the native runtime with HMRC's own server (in Rosetta on Apple Silicon).
#
# Both servers run side by side with separate temporary home folders, so your
# real Basic PAYE Tools data is never used. Fails if any result differs.
#
# Usage: runtime/tests/run_comparison.sh [RUNTIME_DIR]
#   RUNTIME_DIR  default: ~/Library/Caches/PAYELauncher/runtime-build/runtime
#   BPT_APP      default: /Applications/Basic PAYE Tools.app
#   RUNTIME_ARCH arm64 or x86_64: test that half of a universal runtime (x86_64 runs in Rosetta)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="${1:-$HOME/Library/Caches/PAYELauncher/runtime-build/runtime}"
BPT_APP="${BPT_APP:-/Applications/Basic PAYE Tools.app}"
RTI_APP="$BPT_APP/Contents/Helpers/rti.app"
[ -x "$RTI_APP/Contents/MacOS/rti" ] || { echo "Basic PAYE Tools not found at $BPT_APP" >&2; exit 2; }
[ -x "$RUNTIME/python/bin/python2.7" ] || { echo "Native runtime not found at $RUNTIME" >&2; exit 2; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
NATIVE_HOME="$TMP/native-home"
HMRC_HOME="$TMP/hmrc-home"
OUT="${OUT:-$TMP/results}"
mkdir -p "$NATIVE_HOME" "$HMRC_HOME" "$OUT"
PIDS=()
PORTS=()
# Stops the servers. They run in subshells, so also stop whatever listens on their ports.
stop_servers() {
  local pid port
  for pid in "${PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done
  for port in "${PORTS[@]:-}"; do
    [ -n "$port" ] || continue
    for pid in $(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null); do kill "$pid" 2>/dev/null || true; done
  done
  wait 2>/dev/null || true
  PIDS=()
  PORTS=()
}
trap stop_servers EXIT

ARCH_PREFIX=()
if [ -n "${RUNTIME_ARCH:-}" ]; then ARCH_PREFIX=(arch "-$RUNTIME_ARCH"); fi
native_rti() {
  HOME="$NATIVE_HOME" BPT_RTI_APP="$RTI_APP" "${ARCH_PREFIX[@]}" "$RUNTIME/python/bin/python2.7" -S -E -B -u "$RUNTIME/bpt_native_boot.py" "$@"
}
hmrc_rti() {
  (cd "$RTI_APP/Contents/MacOS" && HOME="$HMRC_HOME" PYTHONUNBUFFERED=1 ./rti "$@")
}
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# shellcheck disable=SC2329 # called through check()
wait_ready() {  # port seconds
  local end=$((SECONDS + $2))
  while [ "$SECONDS" -lt "$end" ]; do
    [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/")" != "000" ] && return 0
    sleep 0.5
  done
  return 1
}

failures=0
check() {  # name, then the command
  local name="$1"; shift
  if "$@"; then echo "PASS: $name"; else echo "FAIL: $name"; failures=$((failures + 1)); fi
}

echo "Basic PAYE Tools: $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$BPT_APP/Contents/Info.plist")"
echo "Runtime: $(head -2 "$RUNTIME/BUILD-INFO.txt" 2>/dev/null | tail -1), testing: ${RUNTIME_ARCH:-$(uname -m)}"
echo "Work folder: $TMP"

n=0; native_rti startdb > "$OUT/native-startdb.log" 2>&1 || n=$?
h=0; hmrc_rti startdb > "$OUT/hmrc-startdb.log" 2>&1 || h=$?
check "startdb exit codes (native $n, HMRC $h)" test "$n" = 0 -a "$h" = 0
sqlite3 "$NATIVE_HOME/HMRC/payetools-rti/sqlite3.db" .dump > "$OUT/native.sql"
sqlite3 "$HMRC_HOME/HMRC/payetools-rti/sqlite3.db" .dump > "$OUT/hmrc.sql"
check "blank database content" cmp -s "$OUT/native.sql" "$OUT/hmrc.sql"

NATIVE_PORT="$(free_port)"
HMRC_PORT="$(free_port)"
PORTS=("$NATIVE_PORT" "$HMRC_PORT")
start=$SECONDS
native_rti runserver "$NATIVE_PORT" > "$OUT/native-server.log" 2>&1 & PIDS+=($!)
check "native server starts" wait_ready "$NATIVE_PORT" 120
echo "Native server answered after $((SECONDS - start)) s"
start=$SECONDS
hmrc_rti runserver "$HMRC_PORT" > "$OUT/hmrc-server.log" 2>&1 & PIDS+=($!)
check "HMRC server starts" wait_ready "$HMRC_PORT" 300
echo "HMRC server answered after $((SECONDS - start)) s"

check "pages and static files" python3 -I "$HERE/compare_crawl.py" --native-port "$NATIVE_PORT" --hmrc-port "$HMRC_PORT" \
  --native-home "$NATIVE_HOME" --hmrc-home "$HMRC_HOME" --out "$OUT/crawl"
for year in 2025 2026; do
  check "net pay estimator $year" python3 -I "$HERE/compare_netpay.py" --native-port "$NATIVE_PORT" --hmrc-port "$HMRC_PORT" --year "$year"
done

echo "execfile('$HERE/irmark_probe.py')" | native_rti shell 2>&1 | grep -E '^(>>> )?(IRMARK|MISC)' | sed 's/^>>> //' > "$OUT/native-irmark.txt"
echo "execfile('$HERE/irmark_probe.py')" | hmrc_rti shell 2>&1 | grep -E '^(>>> )?(IRMARK|MISC)' | sed 's/^>>> //' > "$OUT/hmrc-irmark.txt"
check "IRmark output" cmp -s "$OUT/native-irmark.txt" "$OUT/hmrc-irmark.txt"
count="$(awk '/^IRMARK_COUNT/ {print $2}' "$OUT/native-irmark.txt")"
check "IRmarks made (${count:-0} of 48; EYU is not accepted by HMRC any more)" test "${count:-0}" -ge 36

stop_servers
n=0; native_rti autobackup > "$OUT/native-autobackup.log" 2>&1 || n=$?
h=0; hmrc_rti autobackup > "$OUT/hmrc-autobackup.log" 2>&1 || h=$?
check "autobackup (native $n, HMRC $h)" test "$n" = 0 -a "$h" = 0
check "backup file made" test -n "$(ls "$NATIVE_HOME/HMRC/payetools-rti/backups/" 2>/dev/null)"

echo
if [ "$failures" = 0 ]; then echo "All comparisons passed."; else echo "$failures comparison(s) failed. Results: $OUT"; fi
exit "$failures"
