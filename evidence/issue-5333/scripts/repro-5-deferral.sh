#!/usr/bin/env bash
# repro-5-deferral.sh — VERIFY: integration install defers cli.json registration
# while tui.json/kv.json exist without cli.json (src/integration/opencode_config.rs
# add_cli_plugin); during deferral `integration status` reads CURRENT (silent
# window); after opencode's own migration creates cli.json without the plugin
# entry, status flips to NEEDS REPAIR and nothing retries — only a manual
# reinstall completes registration.
set -u
CT=herdr-sandbox
S=/tmp/herdr-home/herdr.sock
LOG=/tmp/opencode/herdr-5333/logs/repro-5-deferral.log
: > "$LOG"
cli() { docker exec -e HOME=/tmp/herdr-home -e HERDR_SOCKET_PATH=$S -w /tmp/herdr-home "$CT" /herdr "$@"; }
shx() { docker exec -e HOME=/tmp/herdr-home -w /tmp/herdr-home "$CT" sh -c "$1"; }

echo "== [1] simulate legacy v1 opencode machine (tui.json + kv.json, no cli.json) ==" | tee -a "$LOG"
shx 'mkdir -p ~/.config/opencode ~/.local/state/opencode && printf "{\"theme\":\"dark\"}" > ~/.config/opencode/tui.json && printf "{}" > ~/.local/state/opencode/kv.json'
shx 'ls ~/.config/opencode ~/.local/state/opencode' | tee -a "$LOG"

echo "== [2] herdr integration install opencode ==" | tee -a "$LOG"
cli integration install opencode 2>&1 | tee -a "$LOG"
echo "-- files after install:" | tee -a "$LOG"
shx 'ls ~/.config/opencode; echo; cat ~/.config/opencode/tui.jsonc 2>/dev/null; echo; cat ~/.config/opencode/cli.json 2>/dev/null || echo "cli.json ABSENT"' | tee -a "$LOG"

echo "== [3] integration status during deferral ==" | tee -a "$LOG"
cli integration status 2>&1 | tee -a "$LOG"

echo "== [4] simulate opencode first V2 start: migration creates cli.json WITHOUT herdr plugin ==" | tee -a "$LOG"
shx 'printf "{\"theme\":\"dark\"}" > ~/.config/opencode/cli.json'
cli integration status 2>&1 | tee -a "$LOG"

echo "== [5] prove nothing retries: 3 spaced status checks (server stays running) ==" | tee -a "$LOG"
for i in 1 2 3; do sleep 2; echo "check $i:" | tee -a "$LOG"; cli integration status 2>&1 | tee -a "$LOG"; done
echo "-- cli.json plugins after passive checks:" | tee -a "$LOG"
shx 'cat ~/.config/opencode/cli.json' | tee -a "$LOG"

echo "== [6] manual reinstall repairs ==" | tee -a "$LOG"
cli integration install opencode 2>&1 | tee -a "$LOG"
shx 'cat ~/.config/opencode/cli.json' | tee -a "$LOG"
cli integration status 2>&1 | tee -a "$LOG"
