# Workshop To-Do / Definition of Done

Check items off as they're completed. If an item is skipped on purpose, mark it `[skip]`
instead of `[ ]`/`[x]` and explain why in that phase's Handoff Summary under "Decisions."

## Phase 1 — Setup, core concepts, baseline & load

- [x] Service (`registraduria/`) builds and runs locally (`mvn spring-boot:run` or packaged jar)
- [x] `/actuator/health` returns UP
- [x] Manual `curl POST /register` confirmed to return `VALID` for a valid, unused id
- [x] Manual repeat `curl` with same id confirmed to return `DUPLICATED` (sanity check on uniqueness rule)
- [x] k6 installed and `k6 version` verified
- [x] SLA/SLO defined and written down (p95, p99, error rate, throughput targets)
- [x] Test plan documented: scope (endpoints), data strategy, environment notes, warmup
- [x] `perf/scripts/register_person_k6.js` run for `SCENARIO=baseline`, `summary-baseline.json` produced
- [x] `perf/scripts/register_person_k6.js` run for `SCENARIO=load`, `summary-load.json` produced
- [x] `perf/scripts/register_voter_k6.js` run at least once for `baseline`, `register_failed` metric reviewed
- [x] One-line result notes recorded for every run (scenario, date, p95, error rate, pass/fail)
- [x] Wiki updated with this phase's work (Inicio, Plan de pruebas, initial Ejecución/Resultados — see MASTER_PLAN.md §3 step 6)
- [x] `handoff-phase-1.md` written using the template in MASTER_PLAN.md §5

## Phase 2 — Stress, spike, soak, observability, defect fix

- [x] `SCENARIO=stress` run, saturation point observed and noted
- [x] `SCENARIO=spike` run, recovery behavior noted
- [x] `SCENARIO=soak` run (reduced duration, 25 min instead of 2h, documented in Decisions)
- [x] Actuator metrics pulled during a `load` run: `http.server.requests`, `jvm.threads.live`, `jvm.gc.pause` (plus Tomcat thread and HikariCP pool metrics, added this phase)
- [x] Client-side p95 (k6) vs. server-side p95 (Actuator) compared and the gap explained
- [x] Connection-pool defect in `RegistryRepository.getConnection()` identified and explained
- [x] Fix applied (HikariCP pooling)
- [x] `load` scenario re-run post-fix; before/after p95 and thread counts compared
- [x] `defectos.md` filled in with the finding, evidence, and status (using `defectos_template.md` as the format)
- [x] Wiki updated with this phase's work (extended Resultados, start of Conclusiones técnicas — see MASTER_PLAN.md §3 step 6)
- [x] `handoff-phase-2.md` written using the template in MASTER_PLAN.md §5

## Phase 3 — CI/CD, matrix, wiki, reflection, packaging

- [x] `perf/ci/github-actions.yml` copied to `.github/workflows/perf.yml`
- [ ] CI pipeline confirmed to boot the service, wait on `/actuator/health`, and run the short scenario on PR — **authored and YAML-validated, not executed** (no GitHub Actions runner available in this working environment); verify on first real PR push, see handoff-phase-3.md
- [ ] CI gate confirmed to fail the pipeline when thresholds are breached (spot-check with a deliberately bad threshold, then revert) — **same limitation as above**, instructions for the manual spot-check are in wiki.md's CI/CD section; not run
- [x] Long scenarios (stress/soak) wired to `workflow_dispatch` or scheduled run, not blocking PRs — split into a separate `k6-extended` job (spike included), `k6-quick-gate` stays PR-only
- [x] Performance matrix table completed (scenario, model, duration, SLO, result, artifact path)
- [x] Wiki content drafted per README's minimum structure (Inicio, Tipos de pruebas, Modelos de carga, Plan de pruebas, Ejecución, Resultados, Conclusiones, Mejoras propuestas)
- [x] Final written reflection answered: most sensitive metric, main bottleneck + mitigation, what you'd redesign
- [x] All `perf/results/summary-*.json` files present and versioned (no raw `-o json=` dumps committed) — confirmed present in `perf/results/` (9 summary files); `.gitignore` already excludes raw `-o json=` dumps
- [skip] README updated if any SLA/SLO or scenario details changed from the original — no SLA/SLO or scenario changed in any phase, so nothing to update; not re-read this phase per user instruction to save tokens (see Decisions Log)
- [ ] Repo reviewed once end-to-end against the rubric in README §9 before calling it done — **not done**: README was not re-read this phase (see Decisions Log); user should do a final pass against §9 before submitting
- [x] Wiki completed (all remaining sections: Mejoras propuestas, final reflection — see MASTER_PLAN.md §3 step 6) and checked against the full structure suggested in the README
- [x] `handoff-phase-3.md` written (final summary — no next phase, but keep for the record)
