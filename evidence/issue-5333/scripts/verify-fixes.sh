#!/usr/bin/env bash
# verify-fixes.sh — re-verify the four fix/5333 behaviors against the FIXED
# binary, sandboxed in the container. Requires: release binary built from
# fix/5333 and copied in (sbx.sh cp), server NOT yet started (fresh state).
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/verify-fixes.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
api() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" python3 hapi.py "$S" "$1" "$2"; }
shx() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" sh -c "$1"; }

echo "== FIX A: CLI default timeout from config (agent.wait_timeout_ms = 2000) ==" | tee -a "$LOG"
shx 'mkdir -p ~/.config/herdr && printf "[agent]\nwait_timeout_ms = 2000\n" > ~/.config/herdr/config.toml'
docker cp /tmp/opencode/herdr-5333/scripts/hapi.py "$CT:/tmp/herdr-home/hapi.py" >/dev/null
/tmp/opencode/herdr-5333/scripts/sbx.sh server
/tmp/opencode/herdr-5333/scripts/sbx.sh ready >> "$LOG"
cli workspace create --cwd /tmp --label fix >/dev/null 2>&1
api pane.report_agent '{"pane_id":"w1:p1","source":"custom:docs","agent":"opencode","state":"working"}' >/dev/null
T0=$(date +%s%N)
cli agent wait w1:p1 --until blocked > /tmp/opencode/herdr-5333/logs/fixA-out.json 2> /tmp/opencode/herdr-5333/logs/fixA-err.json
RC=$?
T1=$(date +%s%N)
echo "fixA_exit=$RC elapsed_ms=$(( (T1-T0)/1000000 )) (expect ~2000, exit 1)" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/fixA-err.json | tee -a "$LOG"

echo "== FIX B: timeout error reports done + unseen-output hint ==" | tee -a "$LOG"
cli tab create --label bg >/dev/null 2>&1
cli tab focus w1:t1 >/dev/null 2>&1
api pane.report_agent '{"pane_id":"w1:p2","source":"custom:docs","agent":"opencode","state":"working"}' >/dev/null
sleep 0.2
api pane.report_agent '{"pane_id":"w1:p2","source":"custom:docs","agent":"opencode","state":"idle"}' >/dev/null
cli agent wait w1:p2 --until idle --timeout 1500 > /dev/null 2> /tmp/opencode/herdr-5333/logs/fixB-err.json
echo "fixB_exit=$?" | tee -a "$LOG"
cat /tmp/opencode/herdr-5333/logs/fixB-err.json | tee -a "$LOG"

echo "== FIX C: boot-time integration health repair ==" | tee -a "$LOG"
shx 'mkdir -p ~/.config/opencode ~/.local/state/opencode && printf "{\"theme\":\"dark\"}" > ~/.config/opencode/tui.json && printf "{}" > ~/.local/state/opencode/kv.json'
cli integration install opencode >/dev/null 2>&1
echo "cli.json after deferred install: $(shx 'cat ~/.config/opencode/cli.json 2>/dev/null || echo ABSENT')" | tee -a "$LOG"
shx 'printf "{\"theme\":\"dark\"}" > ~/.config/opencode/cli.json'
echo "status before restart: $(cli integration status 2>/dev/null | grep opencode)" | tee -a "$LOG"
cli server stop >/dev/null 2>&1; sleep 1
/tmp/opencode/herdr-5333/scripts/sbx.sh server
/tmp/opencode/herdr-5333/scripts/sbx.sh ready >> "$LOG"
sleep 3
echo "cli.json after server restart: $(shx 'cat ~/.config/opencode/cli.json')" | tee -a "$LOG"
echo "status after restart: $(cli integration status 2>/dev/null | grep opencode)" | tee -a "$LOG"

echo "== FIX D: v2 manifest rules ==" | tee -a "$LOG"
shx 'mkdir -p ~/bin && cat > ~/bin/opencode <<"EOF"
#!/bin/bash
printf "  OpenCode\n\n  Allow command execution?\n\n\n\n\n\n\n\n\n\n\n\n\n"
printf "  \xe2\x87\x86 select \xc2\xb7 enter confirm \xc2\xb7 esc cancel       \n"
sleep 8
printf "\033[2J\033[H  OpenCode\n\n  Apply file edit?\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
printf "  \xe2\x87\x86 select \xc2\xb7 enter confirm \xc2\xb7 esc reject       \n"
sleep 8
printf "\033[2J\033[H  user: how do I dismiss the dialog?\n"
printf "  assistant: press esc dismiss, or pick with \xe2\x86\x91\xe2\x86\x93 select then enter confirm.\n\n\n\n\n\n\n\n\n\n\n"
printf "  \xe2\xa0\x8b building\xe2\x80\xa6\n"
sleep 9999
EOF
chmod +x ~/bin/opencode'
cli tab create --label detect >/dev/null 2>&1
sleep 0.3
PANE=$(cli tab list 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
tabs = d['result']['tabs'] if 'tabs' in d.get('result', {}) else d['result'].get('tab_list', [])
tab_id = next(t['tab_id'] for t in tabs if t.get('label') == 'detect')
print(tab_id)" 2>/dev/null)
PANE=$(cli pane list 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print([p['pane_id'] for p in d['result']['panes'] if p['tab_id']=='$PANE'][0])")
cli tab focus w1:t1 >/dev/null 2>&1
cli pane send-text "$PANE" '~/bin/opencode' >/dev/null 2>&1
cli pane send-text "$PANE" $'\n' >/dev/null 2>&1
sleep 5
echo "v2 esc cancel -> $(cli agent explain "$PANE" --json 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r.get('state'), (r.get('matched_rule') or {}).get('id'))")" | tee -a "$LOG"
sleep 8
echo "v2 esc reject -> $(cli agent explain "$PANE" --json 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r.get('state'), (r.get('matched_rule') or {}).get('id'))")" | tee -a "$LOG"
sleep 8
echo "transcript quoting -> $(cli agent explain "$PANE" --json 2>/dev/null | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r.get('state'), (r.get('matched_rule') or {}).get('id'), r.get('fallback_reason'))")" | tee -a "$LOG"
