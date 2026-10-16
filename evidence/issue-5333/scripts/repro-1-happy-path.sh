#!/usr/bin/env bash
# repro-1-happy-path.sh — VERIFY: agent wait fires on a genuine reported idle
# transition (happy path, sandboxed, custom-source reporting).
# Preconditions: sandbox server up (sbx.sh), workspace w1 exists with root pane
# w1:p1. Uses only pane.report_agent (documented custom-integration path).
set -u
CT=herdr-sandbox
SBX=/tmp/opencode/herdr-5333/scripts/sbx.sh
LOG=/tmp/opencode/herdr-5333/logs/repro-1-happy-path.log
S=/tmp/herdr-home/herdr.sock
: > "$LOG"

api() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" "$1" "$2"; }

echo "== [1] report working on w1:p1 (custom:docs authority) ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"working","message":"sim turn"}' >> "$LOG" 2>&1

echo "== [2] start 'agent wait w1:p1 --until idle --timeout 15000' in background ==" | tee -a "$LOG"
docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr agent wait w1:p1 --until idle --timeout 15000 > /tmp/opencode/herdr-5333/logs/repro-1-wait-out.json 2> /tmp/opencode/herdr-5333/logs/repro-1-wait-err.json &
WPID=$!
sleep 1

echo "== [3] report idle (genuine transition) ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"idle"}' >> "$LOG" 2>&1

if wait $WPID; then WEXIT=0; else WEXIT=$?; fi
echo "wait_exit=$WEXIT" | tee -a "$LOG"
echo "wait stdout:" | tee -a "$LOG"; cat /tmp/opencode/herdr-5333/logs/repro-1-wait-out.json 2>/dev/null | tee -a "$LOG"
echo "wait stderr:" | tee -a "$LOG"; cat /tmp/opencode/herdr-5333/logs/repro-1-wait-err.json 2>/dev/null | tee -a "$LOG"

echo "== [4] immediate-match: wait again while already idle (no timeout) ==" | tee -a "$LOG"
T0=$(date +%s%N)
docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr agent wait w1:p1 --until idle --timeout 5000 > /tmp/opencode/herdr-5333/logs/repro-1-wait2-out.json 2>&1
RC=$?
T1=$(date +%s%N)
echo "immediate_match_exit=$RC elapsed_ms=$(( (T1-T0)/1000000 ))" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/repro-1-wait2-out.json 2>/dev/null | tee -a "$LOG"
