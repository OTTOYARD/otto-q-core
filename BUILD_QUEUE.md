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

---

## P0 — blocking a claim we already make

| # | item | why it blocks | status |
|---|---|---|---|
| 1 | **The 48-tick flagship column is stale** | We say "the flagship matrix is green". It is six of seven. `busy_day/171717/48t` has not run since 2026-09-04, sits below the recert floor, and its history predates four fingerprint migrations. | **scheduled** — two consecutive pairs after round 36 |
| 2 | **`0251`: a purged run must say "gone", not "zero"** | `ottoq_kpi_five` returns `{}`/`null` for a purged run — identical to a real run with no bookings. A hollow number that carries a run ID defeats the one rule the whole project rests on. | **drafted**, applies after round 36 |
| 3 | **Nothing acts on `stale`** | The matrix computes staleness and no process reads it. That is how #1 survived five days. A round should schedule its own stale columns. | **half done** — `0252` drafted: `ottoq_cert_columns` declares what should be covered and `ottoq_cert_coverage()` returns MISSING/OVERDUE/UNREGISTERED. It makes the gap visible; it does **not** close the loop. The auto-scheduler is still open. |

## P1 — the model cannot orchestrate optimally without these

| # | item | measured evidence | status |
|---|---|---|---|
| 4 | **No objective function (G45)** | Catalog search for `objective\|weight` returns one function and it is the energy MPC lookahead. The engine has fixed greedy orders and no scalar. **The agent layer has nothing to propose against; "better" is undefined inside the kernel.** | **not started — biggest item on this list** |
| 5 | **DCFC cooldown absent** | Zero matches for `cooldown\|cool_down\|min_gap\|recovery_min` across every function in `public`, `ottoq`, `twin`. Back-to-back fast charges on one charger are schedulable with no gap. CLAUDE.md 2.5 names it as load-bearing. | not started |
| 6 | **Tariff never reaches a scheduling decision** | No function that writes a booking, reserves a stall or emits a command references tariff. Price is snapshotted, billed onto the SDR, rule-evaluated by `TW.004` (never fires) — never used to place work. | not started |
| 7 | **The overnight wave is a slot, not a mechanism** | `ottoq_plan_overnight_wave`: 0 callers. `ottoq_wave_plan`: 0 rows. `TW.002`: never evaluated. The twin reaches a charged fleet by charging everything. | not started |
| 8 | **No re-solve** | A shield refusal produces a hold and a logged decision; the vehicle is reconsidered next tick and nothing triggers a re-solve. `0156` exists because a proposal that could never fit was re-made and re-refused every tick for a whole run while a slower point stood empty. | not started |
| 8b | **The settlement rail is financially empty (`0168`)** | 220,946 SDRs, 100% with a `tariff_id`, **0% with energy, cost or cost components**. `ottoq_visit_cost_attribution` has 0 rows and **no function anywhere inserts into it**; `ottoq_compute_visit_cost` has 0 callers; the attach trigger is enabled, correct, and has never fired; `sdr_issued` 125,648 vs `sdr_costs_attached` 0. CLAUDE.md 2.6 calls the SDR the strategic instruction of the entire build — telemetry and protocol are real, **settlement is a pipe with nothing flowing**. Blocks the `energy_cost` objective, which is one of only five with a *sourced* dollar value. | **not started — needs a judgement call from Chase first: may twin-simulated energy produce a dollar figure that looks like production revenue?** |
| 9 | **Cold-start, and segmented charging** | Both reach planning only as durations/derates. Scheduled segments with a per-segment power profile are CP-SAT-only. | not started |

## P2 — registered but unreachable capability

| # | item | measured evidence | status |
|---|---|---|---|
| 10 | **9 of 29 rules can never fire (G44)** | Six are `block` severity. The engine announces four action contexts; every unreached rule listens outside that set. `SM.001` has had 1.19M vehicle state-change events go past it. | not started |
| 11 | **`SM.006` fail-closed defect** | Verified by me from the catalog, not taken on report: `pronargs=5, pronargdefaults=0` against a dispatcher hard-coded to `%I($1,$2,$3,$4)`. Every other active evaluator is 4-arg. `SM.001`/`002`/`003` each have a dedicated 4-arg wrapper; SM.006 alone was wired straight to the generic. | **`0253` drafted** — ships *before* #10 rather than with it, so the mine is defused before the work that arms it. Two behavioural assertions, both directions. |
| 12 | **137 routines have no in-database caller** | Static reachability, corrected for dispatch tables. ~27 are API surface and ~15 ML scaffold; the rest need triage. Named subsets: 6 assertion/check functions never run, 3 janitors never scheduled, 4 A/B functions. | `0167` measures; triage not started |
| 13 | **Multi-tenancy is empty** | `ottoq_rule_parameters`: 0 rows. `ottoq_rule_overrides`: 0 rows. All four OEM SLA rows carry identical values on every enforceable field. **No active rule produces a different verdict for a different operator.** | not started |
| 14 | **`ottoq_ab_runs` is an empty instrument** | 68–77 rows, one policy, one seed, no writer. And the baselines evaluate **no rules at all**, so greedy would "win" on throughput by checking nothing. Blocked behind #4: the quantity has not been defined. | blocked on #4 |

## P3 — hygiene with a real cost

| # | item | evidence | status |
|---|---|---|---|
| 15 | Finish G23 | purge built fail-closed (`0250`); needs #2, then an observed pass, then `REINDEX`, then cron | in progress |
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
