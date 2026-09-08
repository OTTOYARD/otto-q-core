# FINDINGS.md — the open findings register

Every finding this build track has convicted but not yet closed, with the file that
convicts it. Written 2026-09-08 because the register existed only in agent session
state: `db/checks/` holds the evidence and `db/migrations/` holds the fixes, but
nothing in the repo said which findings were still **open**. A finding that lives
only in a session dies with it.

**Scope and provenance.** Reconstructed from the working task register on 2026-09-08.
Items are listed with the file that convicts them where one exists, and marked
*not yet written up* where the finding is recorded only as a task line — those
entries state the task line verbatim rather than a reconstruction of it.

Closed items are listed too, in one line each, because "what has already been
fixed" is the question a reader asks second.

---

## Open

| # | Finding | Evidence | Fix | State |
|---|---|---|---|---|
| **G8** | Outbound command lifecycle has no lease, ack, retry, TTL or dead-letter. | *not yet written up* | — | open |
| **G9** | No producer for the forward power schedule (`ServiceProfile`). The publication boundary in CLAUDE.md 2.5 is described but nothing emits it. | *not yet written up* | — | open |
| **G10** | The SDR terminus does not bind to the operation ledger; SDRs are mutable; negative durations exist. Also: `ottoq_emit_sdr` signs a payload containing `leg_id` (run-scoped) and omitting `booking_id`/`visit_id` (the attribution) — the signature covers what cannot survive a replay and omits what must. | [0123](db/checks/0123_the_settlement_record_was_outside_the_certification_and_the_scan_that_wrote_it_grew_with_history.sql), [0218](db/migrations/0218_h_sdr_hashed_a_signature_computed_over_a_run_scoped_id.sql) (names it, does not fix it) | — | open — full six-column recert when done |
| **G12** | CI does not run the SQL. `verify.yml` runs four Python batteries; no migration or check has ever executed against a database in CI. | — | — | open |
| **G13** | Reserve CAS lets 96 double-seat attempts reach the unique index; Benchmark depot carries 64 orphan occupancies; the grant is keyed by run; seven 0129 leg cursors; per-seat subtransactions. | *not yet written up* | — | open |
| **G14** | Calibration priors sit outside the reproducibility key, and the weekly ingest refit them mid-round (round 19). | [0115](db/checks/0115_round_nineteen_the_priors_moved_under_the_engine.sql) | partial — `h_cal` now in the verdict | open |
| **G16** | Arm B's boot writes are stamped with arm A's run id: teardown pins the GUC and nothing re-points it. | *not yet written up* | — | open |
| **G17** | KPI-4's touch vocabulary is seven-eighths unsatisfiable — seven of its eight actor types are rejected by the `ottoq_events` CHECK — and it misses every real human actor the constraint does permit. | header of [0213](db/migrations/0213_kpi_four_counted_seven_actor_types_that_cannot_exist.sql) | **0213 drafted** | fix written, not applied |
| **G20** | The second SDR emitter would bill a DCFC charge at the L2 tariff. `charge` is the one `svc_code` mapping to two operations and the lookup picked with an unordered `LIMIT 1`. Dormant since 2026-06-18. | [0124](db/checks/0124_the_other_sdr_emitter_would_bill_a_dcfc_charge_at_the_l2_tariff.sql) | **0220 drafted** | fix written, not applied |

## Open, but diagnosed this session

| # | Finding | Evidence | Fix | State |
|---|---|---|---|---|
| **G19** | The certification pair got ~2x slower in seven days on a fixed workload. **Cause found:** `ottoq.ottoq_validate_assignment` scopes its calendar lookup with `COALESCE(b.sim_run_id, nil) = COALESCE(p_sim_run_id, nil)` — a function of the column, so the planner cannot use the leading column of `ottoq_stall_bookings_live_stall_idx (sim_run_id, stall_id)` and walks every booking that stall ever had in every run that ever ran. cost 5311.29 → 2.65. 33 functions carry the same predicate, from 0123/0124. | [0126](db/checks/0126_where_the_tick_actually_spends_its_time.sql), [0127](db/checks/0127_the_run_scope_predicate_that_no_index_can_read.sql) | **0221 drafted** (one function; the other 32 wait for a measurement) | fix written, not applied |

---

## Closed

| # | Finding | Closed by |
|---|---|---|
| G2 | Anon `EXECUTE` on privileged mutations; proposals and overrides took identity from the client. | server-derived identity |
| G3 | Two need-derivation paths — twin and real feed — that could disagree. | one shared path reading asset state |
| G4 | The verdict could not see the proposal stream. | `h_prop` + `h_defr` |
| G5 | The L1 rule-evaluation ledger was not run-scoped. | run-scoping migration |
| G6 | The recall decision left no ledger row. | [0206](db/migrations/0206_every_recall_decision_is_a_ledger_row_and_the_implementation_is_a_name.sql) |
| G7 | The work side had no way to refuse a recall. | [0211](db/migrations/0211_the_work_side_can_refuse_a_recall_and_the_refusal_is_a_ledger_row.sql), [0212](db/migrations/0212_the_tick_asks_the_work_side_before_it_books_the_stall.sql) |
| G11 | The event stream carried no sim time. | sim-clock column on `ottoq_events` |
| G15 | The L1 shield read the wall clock inside the twin — 12 of 29 active evaluators. | [0204](db/migrations/0204_the_run_has_one_clock_and_the_shield_and_the_events_read_it.sql) |
| G18 | The repo had stopped following the change-control discipline `scripts/APPLYING.md` documents: 93 migration files carried no version header, 98 carried invented ones, and CI never looked at `db/migrations` at all. | `tests/test_migration_hygiene.py`, `scripts/gen-migration-index.py`, `db/migrations/UNFILED.md` |

---

## The one thing on this page that is not ours to close

`db/migrations/UNFILED.md` lists **67 migrations, 734,007 characters**, applied to the
database with no committed file. They are recoverable from `ottoq_schema_snapshots`
and the function catalog. Whether to spend the time recovering them is Chase's
call, not the build track's, and the drift check reports **INVESTIGATE** rather
than CLEAN until it is made.
