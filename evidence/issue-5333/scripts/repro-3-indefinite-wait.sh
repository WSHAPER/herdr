#!/usr/bin/env bash
# repro-3-indefinite-wait.sh — VERIFY: 'agent wait' with NO --timeout waits
# indefinitely (documented "waits indefinitely", src/cli/agent/bindings.rs:261)
# and remains responsive to a genuine transition while waiting.
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/repro-3-indefinite.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
api() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" "$1" "$2"; }

echo "== [1] pane w1:p1 idle; start 'agent wait w1:p1 --until blocked' with NO timeout ==" | tee -a "$LOG"
docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr agent wait w1:p1 --until blocked > /tmp/opencode/herdr-5333/logs/repro-3-wait-out.json 2>&1 &
WPID=$!

for i in 1 2 3 4 5; do
  sleep 1
  if kill -0 $WPID 2>/dev/null; then echo "t=${i}s: wait still running (no timeout => indefinite)" | tee -a "$LOG"; else echo "t=${i}s: wait exited early?!" | tee -a "$LOG"; fi
done

echo "== [2] report blocked — the wait should fire immediately ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"blocked"}' >> "$LOG" 2>&1
if wait $WPID; then WEXIT=0; else WEXIT=$?; fi
echo "wait_exit=$WEXIT (0 = fired on genuine transition after 5+s of indefinite waiting)" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/repro-3-wait-out.json | tee -a "$LOG"

echo "== [3] restore idle ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"idle"}' >> "$LOG" 2>&1
