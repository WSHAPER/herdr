#!/usr/bin/env bash
# repro-6-manifest.sh — VERIFY detection-manifest behavior against captured
# v2 footer text (issue #5333): the v2 permission footer
#   "⇆ select · enter confirm · esc cancel" (and "esc reject" variant)
# does NOT match the bundled permission_required rule (which wants "esc
# dismiss" + "↑↓ select"/"⇆ tab"), while v1 dialogs DO match, and — worse —
# a WORKING pane whose transcript merely QUOTES the v1 footer strings matches
# blocked because permission_required scans whole_recent.
# Drives a fake process named `opencode` (never the real opencode service).
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/repro-6-manifest.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
shx() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" sh -c "$1"; }

echo "== [1] install fake opencode fixture printer ==" | tee -a "$LOG"
shx 'mkdir -p ~/bin && cat > ~/bin/opencode <<"EOF"
#!/bin/bash
# fake opencode for herdr #5333 manifest verification (sandbox only)
phase="${1:-cycle}"
v2perm() {
  printf "  OpenCode\n\n"
  printf "  Bash command blocked by permission setting\n\n"
  printf "  rm -rf /tmp/scratch\n\n\n\n\n\n\n\n\n\n"
  printf "  \xe2\x87\x86 select \xc2\xb7 enter confirm \xc2\xb7 esc cancel       \n"
}
v2perm_reject() {
  printf "  OpenCode\n\n"
  printf "  Apply file edit?\n\n\n\n\n\n\n\n\n\n\n\n\n"
  printf "  \xe2\x87\x86 select \xc2\xb7 enter confirm \xc2\xb7 esc reject       \n"
}
v1perm() {
  printf "  \xe2\x96\xb3 Permission required\n\n"
  printf "  rm -rf /tmp/scratch\n\n"
  printf "  \xe2\x86\x91\xe2\x86\x93 select \xc2\xb7 enter confirm \xc2\xb7 esc dismiss\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
}
transcript_quoting_footer() {
  printf "  user: how do I dismiss the dialog?\n"
  printf "  assistant: press esc dismiss, or pick with \xe2\x86\x91\xe2\x86\x93 select then enter confirm.\n"
  printf "  assistant: the footer reads: esc dismiss / \xe2\x86\x91\xe2\x86\x93 select / enter confirm.\n\n"
  printf "  Running build...\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
  printf "  \xe2\xa0\x8b building\xe2\x80\xa6\n"
}
if [ "$phase" = cycle ]; then
  v2perm; sleep 10
  v2perm_reject; sleep 10
  v1perm; sleep 10
  transcript_quoting_footer; sleep 10
else
  "$phase"
fi
sleep 9999
EOF
chmod +x ~/bin/opencode'
echo "fake installed" | tee -a "$LOG"

echo "== [2] new tab + run fake opencode in its pane ==" | tee -a "$LOG"
cli tab create --label detect >> "$LOG" 2>&1
sleep 0.3
PANE=$(cli pane list 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print([p['pane_id'] for p in d['result']['panes'] if p['tab_id'].endswith(':t3')][0])")
echo "detection pane: $PANE" | tee -a "$LOG"
cli tab focus w1:t1 >> "$LOG" 2>&1
cli pane send-text "$PANE" '~/bin/opencode cycle' >> "$LOG" 2>&1
cli pane send-keys "$PANE" enter >> "$LOG" 2>&1 || cli pane send-text "$PANE" $'\n' >> "$LOG" 2>&1

explain() {
  cli agent explain "$PANE" --json 2>&1 | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
  r=d.get('result',d)
  def pick(x,*ks):
    for k in ks:
      if isinstance(x,dict) and k in x: x=x[k]
      else: return None
    return x
  print(json.dumps({'agent':pick(r,'agent'),'state':pick(r,'state') or pick(r,'agent_state'),'rule':pick(r,'matched_rule','id') or pick(r,'rule','id'),'reason':pick(r,'reason') or pick(r,'fallback_reason'),'skip':pick(r,'screen_detection_skipped')}))
except Exception as e:
  print('explain parse error:', e, file=sys.stderr); print(sys.stdin.read() if False else '')"
}

for phase in "v2_permission_esc_cancel" "v2_permission_esc_reject" "v1_permission_dialog" "working_transcript_quoting_v1_footer"; do
  echo "== phase: $phase ==" | tee -a "$LOG"
  sleep 6
  echo "detection_text (last 3 lines):" | tee -a "$LOG"
  cli agent read "$PANE" --source detection --format text 2>/dev/null | tail -3 | tee -a "$LOG"
  echo "explain: $(explain)" | tee -a "$LOG"
done
echo "final explain: $(explain)" | tee -a "$LOG"
