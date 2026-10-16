#!/usr/bin/env bash
# repro-2-wedge-seen-projection.sh — VERIFY hypothesis: 'agent wait --until idle'
# never fires for a pane in a NON-focused tab because terminal Idle projects to
# Done while pane.seen == false (src/app/api_helpers.rs pane_agent_status), and
# each completion re-arms seen=false for background tabs
# (src/app/actions.rs apply_pane_state_change / active_tab_suppresses_notifications).
# Contrast: a DEFAULT wait (until = idle|done|blocked) fires on the same transition.
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/repro-2-wedge.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
api() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" "$1" "$2"; }
st() { cli agent get "$1" 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin); a=d.get('result',{}).get('agent',d.get('error')); print(json.dumps({'status':a.get('agent_status'),'seq':a.get('state_change_seq')} if 'agent_status' in a else a))"; }

echo "== [1] create background tab with pane w1:p2, keep focus on w1:t1 ==" | tee -a "$LOG"
cli tab create --label bg >> "$LOG" 2>&1
cli tab focus w1:t1 >> "$LOG" 2>&1
sleep 0.3

echo "== [2] report working on w1:p2 ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p2","source":"custom:docs","agent":"opencode","state":"working"}' >> "$LOG" 2>&1
echo "status_after_working: $(st w1:p2)" | tee -a "$LOG"

echo "== [3] start wait w1:p2 --until idle --timeout 8000 ==" | tee -a "$LOG"
cli agent wait w1:p2 --until idle --timeout 8000 > /tmp/opencode/herdr-5333/logs/repro-2-wait-out.json 2> /tmp/opencode/herdr-5333/logs/repro-2-wait-err.json &
WPID=$!
sleep 1

echo "== [4] report idle on w1:p2 (genuine completion) ==" | tee -a "$LOG"
api pane.report_agent '{"pane_id":"w1:p2","source":"custom:docs","agent":"opencode","state":"idle"}' >> "$LOG" 2>&1
sleep 0.3
echo "status_after_idle_report: $(st w1:p2)" | tee -a "$LOG"

echo "== [5] default-until wait (idle|done|blocked) on the same pane, while unseen ==" | tee -a "$LOG"
T0=$(date +%s%N)
cli agent wait w1:p2 --timeout 4000 > /tmp/opencode/herdr-5333/logs/repro-2-default-wait.json 2>&1
DRC=$?
T1=$(date +%s%N)
echo "default_wait_exit=$DRC elapsed_ms=$(( (T1-T0)/1000000 ))" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/repro-2-default-wait.json | tee -a "$LOG"

echo "== [6] collect the --until idle wait outcome ==" | tee -a "$LOG"
if wait $WPID; then WEXIT=0; else WEXIT=$?; fi
echo "until_idle_wait_exit=$WEXIT" | tee -a "$LOG"
echo "stdout: $(cat /tmp/opencode/herdr-5333/logs/repro-2-wait-out.json)" | tee -a "$LOG"
echo "stderr: $(cat /tmp/opencode/herdr-5333/logs/repro-2-wait-err.json)" | tee -a "$LOG"

echo "== [7] focus the background tab — expect status to flip done -> idle ==" | tee -a "$LOG"
cli tab focus w1:t2 >> "$LOG" 2>&1
sleep 0.3
echo "status_after_focus: $(st w1:p2)" | tee -a "$LOG"

echo "== [8] now --until idle matches immediately ==" | tee -a "$LOG"
cli agent wait w1:p2 --until idle --timeout 3000 > /tmp/opencode/herdr-5333/logs/repro-2-after-focus.json 2>&1
echo "after_focus_wait_exit=$?" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/repro-2-after-focus.json | tee -a "$LOG"
