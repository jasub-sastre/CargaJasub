# Handoff Summary — Phase 3 (final)

No next phase reads this — kept for the record per MASTER_PLAN.md §5.

## State achieved
CI workflow authored as two jobs (`k6-quick-gate` on PR, `k6-extended` on `workflow_dispatch`/
nightly `schedule`) and copied to `.github/workflows/perf.yml`; YAML-validated with a parser,
not executed (see Open issues). Performance matrix completed in `wiki.md` covering every
scenario from Phases 1–2 with SLO, result, and artifact path. Wiki completed end-to-end:
CI/CD section, Mejoras propuestas, and a final written reflection added. `todo.md` updated to
reflect what was actually verified versus authored-but-unverified.

## Files changed or added
- `.github/workflows/perf.yml` (new) — active workflow, copied from the template below
- `perf/ci/github-actions.yml` — rewritten as two jobs (quick PR gate, extended dispatch/nightly), dead CLI `--vus`/`--duration` flags removed (k6 ignores them when `options.scenarios` is set)
- `wiki.md` — added "Matriz de rendimiento (Fase 3)", "CI/CD", completed "Mejoras propuestas", added "Reflexión final"
- `todo.md` — Phase 3 items checked, with two items left honestly unchecked (CI execution unverified) and one `[skip]` (README, justified)
- `handoff-phase-3.md` (this file)

## Numbers obtained
No new measurement runs this phase (Phase 3 is CI/packaging, not a measurement phase). All
numbers carried forward from `handoff-phase-2.md` into the wiki's performance matrix; see that
file or `wiki.md` → "Matriz de rendimiento (Fase 3)" for the full table. Post-fix `load` remains
the current reference: p95 31.5 ms, p99 47.4 ms, 8,104 req/s, 0% error (2026-09-21).

## Open issues
- **The CI workflow was never actually executed.** This working environment has no GitHub
  Actions runner and no network access to install k6 or reach GitHub, so `k6-quick-gate` and
  `k6-extended` were authored and syntax-validated (YAML parses cleanly) but not run
  end-to-end. Two `todo.md` items are left unchecked because of this. **Action needed from the
  user**: push the branch, open a PR, and confirm `k6-quick-gate` boots the service and passes;
  then do the deliberate-threshold-breach spot-check described in `wiki.md`'s CI/CD section
  (temporarily set a threshold like `p(95)<1` in `register_person_k6.js`, confirm the PR check
  goes red, revert).
- **README was not re-read this phase**, per the user's explicit instruction to save tokens.
  This means the "Repo reviewed against rubric in README §9" todo item is genuinely not done —
  it needs a human pass (or a future session that reads the README) before submission.
- Carried forward, still unresolved: the ~1.1s latency outlier (Phase 2), `sample_actuator.ps1`
  untested by any Claude session directly and not wired into CI (Phase 2), throughput noise on
  shared hardware (Phase 2) — all listed as "Mejoras propuestas" in the wiki rather than blocking
  issues, since none of them affect SLO compliance.
- **`defectos_template.md` is missing from the repo** (confirmed deleted relative to the last
  git commit; only `defectos.md` — the completed version — was available this phase). Not a
  blocker since the template's structure is already fully instantiated in `defectos.md`, but
  flagging in case the rubric expects the template file to exist standalone.

## Decisions Log (cumulative — copy forward prior entries, then add new ones)
- [Phase 1] Used PowerShell's `Invoke-RestMethod` instead of `curl.exe` for manual endpoint
  checks on Windows — `curl.exe` invoked from PowerShell mangles nested double-quotes in the
  JSON body even inside single quotes, causing false 400s unrelated to the service itself.
- [Phase 1] Did not re-run baseline/load solely to capture exact p99 values (would cost ~19
  extra minutes for one number already confirmed passing via threshold check); instead flagged
  the `--summary-trend-stats` flag for use starting Phase 2, where p99 comparisons pre/post
  bugfix will matter more.
- [Phase 1] Ran `register_voter_k6.js` baseline twice: first attempt reused IDs from a prior
  run without restarting the service (H2 is in-memory and persists while the process lives),
  producing a false 65% `register_failed` rate. Second attempt, after restarting the service,
  gave a clean 0%. Documented as a reminder, not treated as a real defect.
- [Phase 2] Reduced `soak` from the scripted 2h to 25 min, as allowed by `todo.md`'s
  "reduced duration if time-boxed" clause — time budget agreed with the user. Added
  `__ENV.SOAK_DURATION` to `register_person_k6.js` so the default (`2h`) is preserved for anyone
  who wants the full run later.
- [Phase 2] Kept the `stress` run despite 22 failures in its first second, instead of repeating
  it — the failures were `connection refused` (service not yet listening), not
  request-under-load failures, and they don't affect the `status:200`-tagged latency metrics or
  the 1% error threshold at this volume (22 of 2,077,936). Added a step to the routine from then
  on: wait for `/actuator/health` = `UP` before starting k6.
- [Phase 2] Added `server.tomcat.mbeanregistry.enabled=true` to `application.properties` before
  the pre-fix `load` run, so both the pre-fix and post-fix comparisons use the same
  instrumentation (Tomcat busy/current/max threads). Observability-only change, no behavior
  impact.
- [Phase 2] Used a two-layer comparison (4 alternated short `regression` runs, then a direct
  `load` before/after) instead of a single before/after `load` run, after discovering throughput
  varies by up to ~60% run-to-run on this shared machine. This let GC/CPU-per-request be isolated
  from machine noise before trusting the larger `load` comparison.
- [Phase 2] Fixed the connection-pooling defect with HikariCP (fixed pool size, default 20,
  configurable via `registry.pool.max-size`) rather than, e.g., switching to a JDBC template or
  ORM — smallest change that addresses the specific defect (`DriverManager` per call) without
  touching the repository's SQL or the use case's contract. Old string-based constructors kept
  so `RegistryTest` (unit tests from a prior workshop) still compile unchanged.
- [Phase 3] Split the single CI job into two (`k6-quick-gate` on PR, `k6-extended` on
  `workflow_dispatch`/nightly `schedule`) rather than one job gated by `if` conditions on steps —
  cleaner separation, and it means a PR's required check list doesn't include ~40 minutes of
  stress/spike/soak it was never going to run.
- [Phase 3] Removed the `--duration 60s --vus 20` CLI flags from the original `baseline` CI
  step. They were dead: `register_person_k6.js` defines `options.scenarios`, and k6 ignores
  `--vus`/`--duration` whenever a `scenarios` block is present, so those flags were silently
  no-ops. `baseline` genuinely runs its full 5 minutes in CI either way — left as-is since 5 min
  ×2 scripts (~10 min) still doesn't meaningfully block a PR, but the misleading flags were
  removed to avoid a future reader assuming CI shortens the run.
- [Phase 3] Did not re-read `README.md` or the `perf/results/*.json` files this phase, at the
  user's explicit request to save tokens — relied on `handoff-phase-2.md`'s numbers table
  instead for the performance matrix. This is why the README-rubric-review todo item is left
  genuinely undone rather than checked off on the assumption nothing needed updating.
- [Phase 3] Did not execute the CI workflow (no GitHub Actions runner or k6-install network
  access in this environment) — authored and YAML-syntax-validated only. Documented as an open
  issue and two explicit unchecked `todo.md` items rather than marking CI as fully done.

## Important to know
This is the last phase — no handoff needed for a Phase 4. Before submitting:
1. Push and open a PR to verify `k6-quick-gate` actually runs (see Open issues above).
2. Do the deliberate-threshold-breach spot-check, then revert it.
3. Do a manual pass of `README.md` against its own §9 rubric — not done by any Claude session
   this phase.
4. Confirm `defectos_template.md`'s absence from the repo isn't a rubric problem, or restore it
   if it is.
