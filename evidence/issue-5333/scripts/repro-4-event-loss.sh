#!/usr/bin/env bash
# repro-4-event-loss.sh — VERIFY hypothesis: the agent-wait loop reads the
# 512-event global ring UNCHECKED (src/api/event_hub.rs events_after; the
# checked variant is subscriptions-only). If the pane's PaneAgentStatusChanged
# transition is evicted by an event burst (>512 newer events) before the wait's
# 100ms poll, should_probe is never set, state is never re-read, and a
# no-timeout wait wedges silently even though the server state advanced.
# Trials: (A) no timeout — expect either normal fire or WEDGE; (B) --timeout
# 2500 — expect fire at deadline (final probe re-reads state) if the event was
# lost. Control run without burst confirms normal firing.
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/repro-4-event-loss.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
api() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" "$1" "$2"; }
race() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" parallel workspace.rename "$1" 16; }

cli tab focus w1:t1 >> "$LOG" 2>&1; sleep 0.2

run_trial() {
  local label="$1" timeout_args="$2" use_burst="$3"
  api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"working"}' >> "$LOG" 2>&1
  sleep 0.2
  T0=$(date +%s%N)
  docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr agent wait w1:p1 --until idle $timeout_args > "/tmp/opencode/herdr-5333/logs/repro-4-${label}-out.json" 2>&1 &
  local WPID=$!
  sleep 0.4
  api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"idle"}' >> "$LOG" 2>&1
  if [ "$use_burst" = "yes" ]; then
    BURST=$(race 700)
    echo "burst_result: $BURST" | tee -a "$LOG"
  fi
  sleep 3
  if kill -0 $WPID 2>/dev/null; then
    echo "[$label] WEDGED: wait still running 3s after idle report (event lost, no probe)" | tee -a "$LOG"
    if [ "$timeout_args" = "" ]; then
      echo "[$label] rescue attempt: report working then idle (new pane events)" | tee -a "$LOG"
      api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"working"}' >> "$LOG" 2>&1
      sleep 0.2
      api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"idle"}' >> "$LOG" 2>&1
      sleep 1
      if kill -0 $WPID 2>/dev/null; then
        echo "[$label] still wedged after rescue events; killing" | tee -a "$LOG"
        docker exec "$CT" pkill -f "agent wait w1:p1" >/dev/null 2>&1 || true
        wait $WPID 2>/dev/null || true
      else
        wait $WPID; echo "[$label] rescued by later pane events, exit=$?" | tee -a "$LOG"
      fi
    else
      wait $WPID; echo "[$label] exited late, exit=$?" | tee -a "$LOG"
    fi
  else
    wait $WPID; local RC=$?
    local T1=$(date +%s%N)
    echo "[$label] fired normally, exit=$RC elapsed_ms=$(( (T1-T0)/1000000 ))" | tee -a "$LOG"
  fi
  cat "/tmp/opencode/herdr-5333/logs/repro-4-${label}-out.json" 2>/dev/null | head -2 | tee -a "$LOG"
}

echo "== control (no burst, no timeout) ==" | tee -a "$LOG"
run_trial control "" no
echo "== trial B: burst + --timeout 2500 (late-fire-at-deadline contrast) ==" | tee -a "$LOG"
run_trial timeout2500 "--timeout 2500" yes
echo "== trial A1: burst, no timeout (wedge hunt) ==" | tee -a "$LOG"
run_trial wedge1 "" yes
echo "== trial A2: burst, no timeout (wedge hunt) ==" | tee -a "$LOG"
run_trial wedge2 "" yes
echo "== trial A3: burst, no timeout (wedge hunt) ==" | tee -a "$LOG"
run_trial wedge3 "" yes
