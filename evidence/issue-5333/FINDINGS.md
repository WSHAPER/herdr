# herdr #5333 — empiric evidence record

Fork: WSHAPER/herdr @ master 143bf5fd (byte-identical to upstream/master at time of work)
Issue: herdrdev/herdr#5333 "opencode: wrong pane states and indefinite agent waits when integration registration is lost (manifest doesn't match v2 TUI)"
Date: 2026-10-16

## Method

All runtime verification ran in an isolated Docker container (`herdr-sandbox`,
ubuntu:24.04) with the host-built release binary, `HOME=/tmp/herdr-home`, and a
container-internal `HERDR_SOCKET_PATH`. The machine's live server, opencode
service, and panes were never touched. Agent state transitions were driven
exclusively through the documented `pane.report_agent` socket path
(custom-integration source) and a fake process named `opencode` that prints
fixture screens — never a real opencode instance.

Repro scripts and raw logs: `evidence/issue-5333/scripts/` and
`evidence/issue-5333/logs/` (numbered repro-1..repro-6).

Baseline: `cargo nextest run --locked` on master → 4097 passed, 16 skipped,
exit 0. (Plain `cargo test` is not a valid runner for this suite: shared-process
libtest runs produce env-crosstalk failures absent under nextest.)

## Verified / refuted per assumption

| # | Assumption (hypothesis space) | Verdict | Evidence |
|---|---|---|---|
| A1 | `agent wait` has no default timeout; without `--timeout` it waits indefinitely | **VERIFIED** | src/api/wait.rs:372-374 (`deadline = None`), src/cli/agent/bindings.rs:261 ("waits indefinitely"), docs/next cli-reference ("wait indefinitely when --timeout is omitted"); repro-3: no-timeout wait ran 5+s and only fired on a genuine transition |
| A2 | `--until idle` on an unseen (non-focused-tab) pane can never fire: terminal Idle projects to `Done` while `pane.seen == false`, and each background completion re-arms `seen=false` | **VERIFIED — primary wedge** | src/app/api_helpers.rs:96-107 (`(Idle,false) => Done`); src/app/actions.rs:1844-1848 + `active_tab_suppresses_notifications` (actions.rs:38-43); repro-2: idle reported on background-tab pane → status `done` (seq 6), default-until wait fired in 220 ms, `--until idle` timed out (would hang forever with no timeout), focusing the tab flipped the same seq to `idle`, wait then matched instantly |
| A3 | 512-event global ring + unchecked `events_after` in the wait can silently drop a pane transition → no probe → permanent hang | **STRUCTURALLY VERIFIED, NOT LIVE-REPRODUCED** | src/api/event_hub.rs:19,28-31 (MAX_EVENTS=512, FIFO drain), :34-44 (unchecked `events_after`; checked variant is subscriptions-only at src/api/subscriptions.rs:332); wait probes only on pane events (src/api/wait.rs:391-457). Live attempt: 700 events via 16 parallel connections took 0.64-0.92 s (≈0.9 ms/event) — cannot evict a fresh event inside the wait's 100 ms poll window from the external API. Remains possible under heavier internal event production; the fix (periodic poll-fallback probe) covers it deterministically |
| A4 | Registration race: wait registers after the transition already happened → misses it | **REFUTED** | src/api/wait.rs:140-152 snapshots current state first and resolves immediately on match; repro-1 step 4: wait on an already-idle pane returned in 67 ms |
| A5 | Pinned-occupant incarnation mismatch hangs the wait | **REFUTED as a hang** | The wait pins terminal_id/name/agent-label (src/api/wait.rs:375-382) and every probe re-checks identity (wait.rs:466-475,495-504); a changed occupant yields an immediate `agent_not_running` error, not a hang. Native session ids are deliberately not pinned (docs: "pins the resolved pane occupant"). Only in combination with A3 (missed events) could a replacement go unnoticed — covered by the poll-fallback fix |
| A6 | Status flapping (working→idle→working) misses the idle window | **REFUTED for plain waits** | The plain wait captures transient target statuses from the event stream (`matched_event_status`, wait.rs:428-431) and honors them at the next probe (wait.rs:476-480). REAL only for `agent prompt --wait`'s settled-state wait (`accept_transient_status: false`, wait.rs:305-307) — documented behavior, out of scope |
| A7 | Install defers cli.json registration while `tui.json`/`kv.json` exist without `cli.json`; nothing retries; during deferral status reads CURRENT (silent window); after opencode's own migration creates cli.json without the entry it flips to needs-repair, still with no retry | **VERIFIED** | src/integration/opencode_config.rs:54-74 (`add_cli_plugin` → `Ok(None)`), registry.rs:416-442 validity gate, cli/integration.rs:77-81 label; repro-5 reproduced the full lifecycle in-container: deferral message + absent cli.json → `current (v13)` → simulated migration → `needs repair (v13)` → 3 spaced checks over 6 s with server running: still needs-repair, cli.json untouched → manual reinstall appended `"plugins": ["./herdr-opencode"]` preserving `theme` → `current (v13)` |
| A8 | Bundled manifest permission rule matches v1 text only; real v2 permission footers never match | **VERIFIED** | src/detect/manifests/opencode.toml permission_required wants `esc dismiss` + (`↑↓ select`|`⇆ tab`); v2 footer is `⇆ select · enter confirm · esc cancel` (and `esc reject`). repro-6: both v2 footer variants on screen → state `idle`, rule null, `default_known_agent_idle_fallback`; v1 dialog → `blocked` via `permission_required` |
| A9 | `permission_required` scans `whole_recent`, so transcript text merely quoting footer strings classifies a working pane as blocked | **VERIFIED** | Engine: `whole_recent` = entire bottom-screen detection window (src/detect/manifest.rs:1287; snapshot = bottom `rows()` lines, src/pane/terminal.rs:2849-2860) — includes scrolled-in transcript. repro-6 fp pass: screen bottom `⠋ building…` with quoted v1 footer strings above → `blocked`, rule `permission_required`, region `whole_recent` |
| A10 | "There is no idle rule for opencode, so a non-match is Unknown" | **VERIFIED with correction** | No idle rule exists, but a non-match for a known agent is fallback **Idle** (`default_known_agent_idle_fallback`, manifest.rs:519-574), not `Unknown`; the UI-level symptom ("reads as idle") is real (observed in repro-6) |
| A11 | needs-repair is computed but nothing acts on it at runtime | **VERIFIED** | Verdict is pull-only (CLI status, settings tab) or boot-frozen (snapshot badge from App::new recommendations); `install_target` has no non-manual caller; repro-5 passive checks confirm no retry. Hook points that already wake: headless scheduled-task dispatcher src/server/headless.rs:3275 + deadline registry src/app/runtime.rs:143-177 |
| A12 | (Found en route) full-lifecycle hook reports (`herdr:opencode`) are ignored unless the pane has a matching detected agent process | **VERIFIED** | src/terminal/state.rs:941-1018: non-full-lifecycle sources route `Accept` directly; `herdr:opencode` requires `process_present` (detected agent == label, no recent exit) else `Ignore` — reproduces the "integration lost → heuristics" fallover of the issue and explains why pane states silently switch to screen detection |

## The wedge mechanism (synthesis)

`herdr agent wait <pane> --until idle` hangs forever when the target pane is not
in the currently-focused tab, even with perfectly healthy plugin reporting:

1. The pane's agent completes its turn; the hook report lands
   (`pane.report_agent` → `HookStateReported`), terminal state becomes `Idle`.
2. `apply_pane_state_change` sets `pane.seen = suppress_active_tab_notifications`
   for completion transitions — `false` for any pane outside the focused tab
   (headless or not attached makes no difference when the pane's tab isn't
   active).
3. The public projection maps `(Idle, seen=false) → Done`. The emitted
   `PaneAgentStatusChanged` carries `done`. Server state is correct and
   advancing — but the string "idle" is unobservable for that pane.
4. The wait's `until = [Idle]` never matches, not on the event, not on probes.
   With `timeout_ms: None` (CLI default) there is no deadline; the error path
   that would at least report the status never runs. Silent indefinite hang.

Sibling waits fired "on equivalent panes the same day" because they either used
the default until-set (`idle|done|blocked` — fires on `Done` in 220 ms in
repro-2) or targeted panes in the focused tab (`seen=true` → `Idle`).
Viewing the pane (tab focus) flips the projection to `idle` at the same
`state_change_seq` — confirmed live in repro-2 step 7-8.

Independent amplifiers (both verified): no default timeout (A1) and
event-gated probing with an unchecked 512-event ring (A3) mean *any* missed
transition becomes permanent, not just the seen-projection mismatch.

## Fix implications (what the evidence justifies)

1. **agent wait**: periodic poll-fallback probe (state re-read not gated on
   events) so no event-delivery condition can wedge a wait; timeout errors must
   carry the current status and, when the wait asked for `idle` and the pane
   sits at `done`, an explicit unseen-completion hint; a CLI default timeout
   (configurable, with explicit infinite opt-out) converts any residual
   silent hang into an actionable error.
2. **deferral/needs-repair**: a runtime health pass over the installed opencode
   integration — attempt reinstall when the deferred registration's blocker has
   cleared (cli.json now exists) or the verdict is needs-repair; warn and
   surface recommendations when the config is unwritable. Reuse the existing
   scheduled-task/dispatcher pattern; repair is the existing idempotent install
   path (JSONC-preserving, atomic).
3. **manifest**: bottom-anchored v2 permission rules (both `esc cancel` and
   `esc reject` variants), v1 variants kept but scoped to the footer line
   (`bottom_non_empty_lines(1)`) so transcript quoting cannot classify
   `blocked`; version bump + byte-identical distribution catalog sync in the
   same change. No idle/working rules added: no captured v2 idle/working
   screen evidence exists to justify their strings (fallback idle already
   covers the observed behavior).
