# post-fix verification (fix/5333 binary, sandboxed container)

- FIX A (config default timeout): exit 1 at 2055 ms with wait_timeout_ms=2000, message includes 'current status is working'
- FIX B (done hint): 'current status is done; done means the agent finished with unseen output - it reports idle once the pane is viewed, or include done in the requested states'
- FIX C (boot health repair): needs repair (v13) before restart -> server restart -> cli.json gains plugins:[./herdr-opencode] with theme preserved -> current (v13)
- FIX D (v2 manifest, fresh fake-opencode pane w1:p4):
  v2 esc cancel  -> blocked permission_required visible_blocker=True
  v2 esc reject  -> blocked permission_required visible_blocker=True
  transcript quoting -> idle fallback (permission_required region preview = bottom line only, matched=false)
