# BUILD QUEUE

Chase, 2026-09-09 09:05 AM CT: *"Stop missing details… These are all massive issues
that YOU HAVE TO CATCH. Keep making lists of things to accomplish or get to for
building and make sure these are addressed asap… make sure our overall model has
what's needed to properly orchestrate and make optimal decisions. You MUST be
sharper."*

He is right, and the specific charge is right: **I found the three biggest
architectural gaps by accident.** They surfaced from a background workflow I had
launched to answer a retention question. My own adversarial review of the same
code that morning found three implementation bugs and missed all three
architecture gaps, because I was checking whether the code did what it said
rather than whether the system had what it needs.

This file is the standing answer. It is ordered, it carries status, and it is in
the repo rather than in a task tool nobody else can see.

**Rule for this file:** an item leaves only when it is measured closed, with the
check or migration that closed it named. "Probably fine" is not a status.

**The most predictive heuristic this codebase has, earned four times in one day:**
when looking for what is broken, do not look for what is missing — look for what
**exists and is never called**. G23 (`ottoq_purge_prior_runs`, correct, no
scheduler), P0 #3 (`ottoq_cert_matrix.stale`, correct, no consumer), `0167` (six
assert/check functions, correct, no caller), `0168` (the entire cost chain,
correct, no caller at link 1).

---

## THE DISCIPLINE FIX — why the misses happened, and what changes

Three misses, one cause: **I audited behaviour, never coverage.** The certification
rounds prove the engine is *deterministic*. Nothing was asking whether it is
*complete*. Those are different questions and only one of them was instrumented.

So the standing change is a coverage instrument, run and reported like a round:

| question | instrument | status |
|---|---|---|
| Which registered rules can never fire? | rule `applies_to_actions` vs the action contexts the engine announces | **built, ad-hoc** — needs to be a standing check |
| Which routines has nothing ever called? | static reachability over bodies + views + triggers + cron + dispatch tables | **built, ad-hoc** — `0167` |
| Which certification columns are stale? | `ottoq_cert_matrix.stale` | exists, but nothing *acts* on it — the 48t column sat stale five days |
| Which KPIs have no data behind them? | none | **MISSING** — `0251` is the first piece |
| Which declared capability has no test? | none | **MISSING** |

**And a measurement lesson worth more than the numbers.** Chasing this I found
`track_functions = 'none'` — `pg_stat_user_functions` is not recording calls at
all. I was one step from reporting "250 of 543 functions never called" as a
finding. It would have been an artifact of a disabled instrument, exactly the
class of error that produced the 22-second KPI view (`0098`) and the stale
CLAUDE.md row counts. **Validate the instrument before quoting it.**

**A second lesson, about my own reasoning rather than the code, earned twice in
one day.** Both times I wrote some version of *"erring in this direction is
safe"*, and both times it was false:

* `0247` — the delete list. The reasoning was that a purge covering *too much*
  of an over-broad class was tolerable. It was not: that class held the cuOpt
  ledger, the SDR rail and the conflict ledger.
* `0251` — the backfill cutoff. The file said *"an over-stamp here is safe (it
  says 'not whole' of a run that is whole)."* It was not: a two-day arithmetic
  slip would have stamped 182 intact runs, rounds 31–35 among them, and
  suppressed the KPIs of the very runs the certification rests on.

**The phrase itself is the tell.** "Erring this way is safe" means I have worked
out the failure mode in one direction and *not* in the other, and then licensed
myself to stop. The correction is not to be more careful — it is to notice the
sentence and treat it as an unfinished analysis. Where a value either reproduces
a known set or does not, there is no safe side: pin it and assert the count
(`0251` A7 pins the backfill to exactly 729).

---

## P0 — blocking a claim we already make

| # | item | why it blocks | status |
|---|---|---|---|
| 1 | **The 48-tick flagship column is stale** | We say "the flagship matrix is green". It is six of seven. `busy_day/171717/48t` has not run since 2026-09-04, sits below the recert floor, and its history predates four fingerprint migrations. | **RAN AND FAILED ITS BAR.** Both pairs fired 2026-09-09 15:45/16:10, each passed internally, and they disagree with each other on `endst` — within it, on `world` alone (`db/checks/0169`). `0252` applied, so the column is now declared and readable. Re-test scheduled as round 37 (jobids 552/553) with `wsec` recording which world section moves; prediction committed in `0170`. **Still six of seven. Not green.** |
| 2 | **`0251`: a purged run must say "gone", not "zero"** | `ottoq_kpi_five` returns `{}`/`null` for a purged run — identical to a real run with no bookings. A hollow number that carries a run ID defeats the one rule the whole project rests on. | **APPLIED** 2026-09-12 03:42 UTC, version 20260912034252. A1–A7 passed; 729 runs stamped, matching the doomed set exactly. A purged run now returns a `purged` block and nulls; an unpurged run still carries all eleven keys. |
| 3 | **Nothing acts on `stale`** | The matrix computes staleness and no process reads it. That is how #1 survived five days. A round should schedule its own stale columns. | **half done** — `0252` drafted: `ottoq_cert_columns` declares what should be covered and `ottoq_cert_coverage()` returns MISSING/OVERDUE/UNREGISTERED. It makes the gap visible; it does **not** close the loop. The auto-scheduler is still open. |

## P1 — the model cannot orchestrate optimally without these

| # | item | measured evidence | status |
|---|---|---|---|
| 4 | **CORRECTED 2026-09-12 — the objective function EXISTS. It is connected to nothing (G45)** | My original entry said "no objective function" and that was wrong in the direction that matters. What is true: **the SQL engine has none** — the catalog search stands, the decide path ranks by a fixed four-term key (`fits_window DESC, minutes_to_deploy ASC, open_must_do_min ASC, vehicle_id`) and there is no scalar. What I missed is that **the Python layer already has the whole thing**: `intent/intent_v1.json` declares 11 lexicographic objectives and 6 regimes; `intent/solve.py` resolves a regime to a pass sequence; `policies/regime.py` drives the solver from the declared intent; `solvers/cpsat/model.py` implements `min_tardy` / `min_peak` / `min_flow` with ε-constraints (`max_tardy_total`) and a `rejection_saving_ceiling` so weights cannot buy a better score by dropping assets. `policies/test_regime.py` shows *measured* trade-offs — `grid_peak` (min_tardy, min_peak) gives flow 2937 min / peak 150 kW, `rush` (min_tardy, min_flow, min_peak) gives 1676 min / 400 kW. And `intent/learn.py` is the learn loop, which deliberately refuses to train on run outcomes because the twin replays OTTO-Q's own decisions and would tune against our own bugs. **So the real defect is the wiring, and it is this list's governing pattern again:** `proposer/orchestrate.py` has no `psycopg`, no `supabase`, no `INSERT`, no `ottoq_submit_external_proposal`, and `grep` finds its only caller is `proposer/test_orchestrate.py`. `ottoq_certified_proposers` holds exactly three sources — `greedy_constrained` (12,403 proposals), `ottoq_service_priority` (1,904), `cuopt` (1) — and the forward/CP-SAT orchestrator is **not one of them**. The one component that optimises a declared objective cannot reach the component that decides. | **re-scoped, not started.** The work is an adapter + certification, not a design: submit through `ottoq_submit_external_proposal` under the existing deferral pattern so the disposer still disposes, register as a certified proposer, and let `h_prop` hash it into the verdict. **Two things must be settled first:** (a) `intent_v1`'s `steady_state` order (readiness → service_completion → energy_cost → … → bess_peak_shave 10th) vs the prototype's regime pass orders must be reconciled explicitly, or an A/B measures two different questions; (b) R-13 is still the right request, but narrowed — the *structure* question is largely answered by the prototype, so what remains is whether lexicographic-with-ε matches published practice and whether the weights are sourceable. #14 is unblocked by this entry: the quantity IS defined, just not where the engine can see it. |
| 5 | **DCFC cooldown absent** | Zero matches for `cooldown\|cool_down\|min_gap\|recovery_min` across every function in `public`, `ottoq`, `twin`. Back-to-back fast charges on one charger are schedulable with no gap. CLAUDE.md 2.5 names it as load-bearing. | not started |
| 6 | **Tariff never reaches a scheduling decision** | No function that writes a booking, reserves a stall or emits a command references tariff. Price is snapshotted, billed onto the SDR, rule-evaluated by `TW.004` (never fires) — never used to place work. | not started |
| 7 | **The overnight wave is a slot, not a mechanism** | `ottoq_plan_overnight_wave`: 0 callers. `ottoq_wave_plan`: 0 rows. `TW.002`: never evaluated. The twin reaches a charged fleet by charging everything. | not started |
| 8 | **No re-solve** | A shield refusal produces a hold and a logged decision; the vehicle is reconsidered next tick and nothing triggers a re-solve. `0156` exists because a proposal that could never fit was re-made and re-refused every tick for a whole run while a slower point stood empty. | not started |
| 8b | **The settlement rail is financially empty (`0168`)** | 220,946 SDRs, 100% with a `tariff_id`, **0% with energy, cost or cost components**. `ottoq_visit_cost_attribution` has 0 rows and **no function anywhere inserts into it**; `ottoq_compute_visit_cost` has 0 callers; the attach trigger is enabled, correct, and has never fired; `sdr_issued` 125,648 vs `sdr_costs_attached` 0. CLAUDE.md 2.6 calls the SDR the strategic instruction of the entire build — telemetry and protocol are real, **settlement is a pipe with nothing flowing**. Blocks the `energy_cost` objective, which is one of only five with a *sourced* dollar value. | **not started — needs a judgement call from Chase first: may twin-simulated energy produce a dollar figure that looks like production revenue?** |
| 8c | **The readiness floor is measured by a function nothing calls** | `intent_v1` ranks `readiness` **first, as a floor**. `ottoq_kpi_dispatch_readiness(p_run)` measures it *well*: filters to deadline-bearing needs, bounds by the run horizon (0176), separates `no_charge_needed` from `stranded`, and **reports its own denominators** (`visits_with_due`, `visits_without_due`, `due_beyond_horizon`) — the `0189` population discipline. It has **0 callers** and is **absent from `ottoq_kpi_five`**. Fifth instance of the pattern. **Not a one-line fix:** its `end_soc` comes from `public.vehicles.current_soc`, which the function itself flags as *live shared state, not run-scoped* — the `0145` defect class. Wiring it into the shipped payload without a run-scoped end-SoC source would put a non-reproducible read into a KPI. | **not started** — needs the run-scoped end-SoC first |
| 8d | **`dispatch_due_at` coverage is correct, and I nearly filed it as a bug** | 52,817 of 104,957 needs carry a due time — which looks like 50% blindness until you group it: `overnight_hold` 100%, `immediate_dispatch` 100%, `standard` 0%, `tech_hold` 0%. It is populated for exactly the urgency classes that *have* a deadline. A standard visit cannot be late; a tech hold is open-ended. **Recorded as a non-finding on purpose** — the near-miss is the useful part, and it is the same shape as `track_functions='none'`: a ratio that looks alarming until you ask what the denominator means. | closed, no action |
| 9 | **Cold-start, and segmented charging** | Both reach planning only as durations/derates. Scheduled segments with a per-segment power profile are CP-SAT-only. | not started |

## P2 — registered but unreachable capability

| # | item | measured evidence | status |
|---|---|---|---|
| 10 | **9 of 29 rules can never fire (G44)** | Six are `block` severity. The engine announces four action contexts; every unreached rule listens outside that set. `SM.001` has had 1.19M vehicle state-change events go past it. | not started |
| 11 | **`SM.006` fail-closed defect** | Verified by me from the catalog, not taken on report: `pronargs=5, pronargdefaults=0` against a dispatcher hard-coded to `%I($1,$2,$3,$4)`. Every other active evaluator is 4-arg. `SM.001`/`002`/`003` each have a dedicated 4-arg wrapper; SM.006 alone was wired straight to the generic. | **APPLIED** 2026-09-12 03:38 UTC, version 20260912033843. Re-confirmed from the live catalog first: 1 bad-arity rule → 0, 1 dangling 4-arg signature → 0, SM.006 now points at `ottoq_eval_sm_006_bess_transition`. A5 asserts the routing is unchanged, so the rule is still unreachable and no verdict can move — the mine is defused, #10 is untouched. |
| 12 | **137 routines have no in-database caller** | Static reachability, corrected for dispatch tables. ~27 are API surface and ~15 ML scaffold; the rest need triage. Named subsets: 6 assertion/check functions never run, 3 janitors never scheduled, 4 A/B functions. | `0167` measures; triage not started |
| 13 | **Multi-tenancy is empty** | `ottoq_rule_parameters`: 0 rows. `ottoq_rule_overrides`: 0 rows. All four OEM SLA rows carry identical values on every enforceable field. **No active rule produces a different verdict for a different operator.** | not started |
| 14 | **`ottoq_ab_runs` is an empty instrument** | 68–77 rows, one policy, one seed, no writer. And the baselines evaluate **no rules at all**, so greedy would "win" on throughput by checking nothing. Blocked behind #4: the quantity has not been defined. | blocked on #4 |

| 4b | **The entire Python intelligence layer has zero production callers** | Not a restatement of #4 — it is the scope. `proposer/orchestrate.py`, `policies/regime.py`, `intent/solve.py`, `intent/learn.py`, `solvers/cpsat/model.py` are all tested (886 passed / 5 skipped at last full run) and all reachable only from tests. `tests/test_separation.py` enforces kernel/pack separation on them, so the boundary discipline is real — what is missing is a door into the engine. **This is the sixth and largest instance of the list's governing pattern: correct machinery with no caller.** | not started — same work as #4 |
| 4c | **Two world sections are invisible to every stream atom** | Found while narrowing `0169`. `h_bkg` hashes `ottoq_stall_bookings` (the calendar) and never the `stalls` table's own `reserved_by` / `reserved_at` / `reservation_expires_at`; `h_nrg` hashes `ottoq_energy_commands` (what was *commanded*) and never `ottoq_bess_units` state, whose `lifetime_kwh_charged` / `_discharged` / `current_cycle_count` are **cumulative across runs**. So identical commands do not entail identical battery state, and an identical calendar does not entail identical stall rows. These are the only two of five world sections with that property, which is why they are the prime suspects for the 48-tick divergence. | **instrument shipped** (`0254`, `wsec` MEASURED); mechanism not yet named |

## P3 — hygiene with a real cost

| # | item | evidence | status |
|---|---|---|---|
| 15 | Finish G23 | purge built fail-closed (`0250`); **#2 is now applied, so the blocker is cleared**. Remaining: one observed full pass, then `REINDEX` on the calendar's three GiST EXCLUDE constraints (deleting rows does not shrink a GiST index — `0164` Q4), then cron. Still deliberately unscheduled. | in progress — unblocked |
| 16 | `no_overlap_v2` is fully redundant given v3 | strict superset state list, identical predicate, scan counters 0.25% apart. 170 MB + a share of every insert. | not started |
| 17 | 28 of 35 `db/fn_current` captures are stale | re-measured 2026-09-09; `ottoq_decide_tick`'s capture predates `0132` and lacks the site power gate | labelled honestly; bodies not refreshed |
| 18 | G26: production and the proof harness share one database | root cause behind G43 | not started |
| 19 | G12: CI does not run the SQL | migrations and checks never execute against a database in CI | not started |
| 20 | G14: calibration priors sit outside the reproducibility key | the weekly ingest can refit them mid-round | not started |
| 21 | G8, G9, G10, G13 | command lifecycle; forward power schedule; SDR terminus; Benchmark depot janitor | not started |

---

## Research to hand Hermes

Chase offered to route research. These are the questions where an external answer
changes the build rather than decorating it:

1. **Objective functions in depot/fleet turnaround scheduling (for #4).** What
   objective structures do published flexible-flow-shop and EV-depot schedulers
   actually optimise, and how do they handle the fact that no operator publishes
   a dollar value for a late minute? `intent_v1` chose lexicographic ordering for
   that reason (R-10) — the question is whether that survives contact with a
   solver that needs a scalar, or whether the standard move is a hierarchy of
   ε-constraints. Needs sources with dates and URLs.
2. **DCFC cooldown / thermal recovery as a scheduling constraint (for #5).**
   Real charger-side minimum-gap figures by cabinet class, sourced. Our 18-minute
   figure lives only in the CP-SAT prototype and I do not know where it came from.
3. **Demand-charge-aware load shifting (for #6).** How schedulers place *vehicle*
   load (not just battery dispatch) against a 15-minute demand window.
