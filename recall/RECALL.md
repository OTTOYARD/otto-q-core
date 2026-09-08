# RECALL.md — the Recall Decision primitive

**Run 3, Phase C9 deliverable.** 2026-08-19. Code: `recall/recall_decision.py`,
tests: `recall/test_recall.py` (all passing).

## The interface (CLAUDE.md 2.7, verbatim)

```ts
interface RecallDecision {
  decide(
    asset: AssetState,      // SoC/fuel, faults, component hours, payload
    work: WorkSideSignals,  // mission status, demand forecast, release windows
    site: SiteForecast      // predicted congestion, price windows, availability
  ): { recall_time; target_site; service_bundle: Operation[]; target_ready_time }
}
```

This is the **single interface** between OTTO-Q and every work-side system —
the pit-lane boundary. Work-side systems own the mission; OTTO-Q owns the asset
from recall until ready-for-work. The inputs are sector-free (kernel purity: a
mining pack and a vertiport pack consume the same three structs unchanged).

## The two implementations

| Name | What it is | Why it exists |
|---|---|---|
| `naive_threshold_v1` | **Deliberately naive.** The rung ladder now live as `public.ottoq_recall_naive_threshold_v1` (md5 `cd3ffc2a…`; it WAS `public.ottoq_evaluate_return_need` until migration 0206, md5 `0c463ada…`, which is the body captured in `db/fn_current/`) as fixed thresholds, top-down, first hit wins: critical_reserve → fault_safety_critical → fault_major → low_soc_reserve → comms_stale → (behind the contention gate) service_interval_due → sensor_soil → wash_cadence. No forecasting, no cost model, no learning. | So the interface is real on day one and every smarter successor has a baseline to beat on the same ledger. |
| `fixed_window_dummy` | Recalls everything inside a fixed window. Not a policy anyone should run. | The **swap proof**: demonstrates config-swappability with zero call-site changes. |

### Where the ladder lives, and where the wrapper lives

Migration 0206 split one function into two, and any note citing the old name is
now pointing at the wrong one:

| live function | md5 | what it is |
|---|---|---|
| `public.ottoq_recall_naive_threshold_v1` | `cd3ffc2a…` | the rung ladder itself |
| `public.ottoq_evaluate_return_need` | `53018872…` | the wrapper: reads `recall_implementation_id` from the run's policy, `EXECUTE`s whichever evaluator `ottoq_recall_implementations` names for it, and writes the row to `ottoq_recall_decisions` with its content hash |

`db/fn_current/public.ottoq_evaluate_return_need.sql` holds the **pre-0206**
body, md5 `0c463ada…`. It is still byte-exact for the ladder — renaming the live
`ottoq_recall_naive_threshold_v1` back to `ottoq_evaluate_return_need` md5s to
`0c463ada…`, and the name occurs exactly once in the definition, so the rename is
the whole difference — but it sits under a name that now belongs to the wrapper.
The capture's header says so, and `recall/test_recall.py` refuses a capture whose
header hash and body have drifted apart.

**Swapping is a config change, never a code change:**
`make_recall({"implementation": "naive_threshold_v1"})` vs
`make_recall({"implementation": "fixed_window_dummy", …})` — the call site
(`run_recall_cycle`) is byte-identical for both (proven in
`test_swap_zero_call_site_changes`).

## The event contract — no silent decisions

Every issued or refused recall emits exactly one record shaped for the runs
machinery, using the event types **registered by migration 0045 §4**
(`recall_issued`, `recall_refused`): implementation name, full inputs snapshot
(asset/work/site), the decision, a content hash, keyed by `sim_run_id` and
sim-minute. A stay-deployed evaluation emits nothing (it is not an event).
In production these rows insert into `ottoq_events`; offline they are the
committed record. This is the same "no number without a run ID" machinery every
other decision already lands in.

## Work-side refusal — first-class, never an error

`run_recall_cycle` puts every non-critical recall to the work side
(`work_side_accepts`). A refusal (mission overrun):

1. emits `recall_refused` with the refusal reason and the full snapshot,
2. invokes the re-solve hook (rolling re-solve with previous-feasible
   retention — the site is never without a schedule),
3. returns a no-recall outcome tagged `work_side_refusal`.

It never raises. The C8 scenario `work_side_recall_refusal`
(`sites/site_alpha/`) exercises the downstream consequence: refused assets
return 90 min late and re-enter the queue with immediate urgency
(`policy_otto_q_asis` orders refused-recall returns first).

## Lineage and forward path

The concept predates this phase (`early_recall_log`); this formalizes it. The
naive ladder's thresholds mirror the live policy keys
(`p99_burn_pct_per_min`, `reserve_margin_pct`, `dtc_debt_threshold`, …) so the
Python primitive and the SQL cursor agree on vocabulary. Successor
implementations (forecast-aware, price-window-aware, demand-shaped) register in
`IMPLEMENTATIONS` and are adopted by config — the ledger decides whether they
earn the switch.
