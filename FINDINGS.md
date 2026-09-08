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
| **G12** | CI does not run the SQL. `verify.yml` runs four Python batteries; no migration or check has ever executed against a database in CI. Three of the four defects found in the queued migrations on 2026-09-08 were only visible against the live catalog. A file-only lint was tried as a cheaper substitute — flag `LIMIT 1` with no `ORDER BY` in a migration's own SQL — and **rejected**: on `0220` all five hits were the string `'LIMIT 1'` inside literals and error messages, and telling code from literal here needs a real plpgsql parser because the bodies are dollar-quoted. A noisy gate gets disabled, so the answer is the database, not a regex. | — | — | open |
| **G13** | Reserve CAS lets 96 double-seat attempts reach the unique index; Benchmark depot carries 64 orphan occupancies; the grant is keyed by run; seven 0129 leg cursors; per-seat subtransactions. | *not yet written up* | — | open |
| **G14** | Calibration priors sit outside the reproducibility key, and the weekly ingest refit them mid-round (round 19). | [0115](db/checks/0115_round_nineteen_the_priors_moved_under_the_engine.sql) | partial — `h_cal` now in the verdict | open |
| **G16** | **CONVICTED, and larger than the task line.** Arm B's boot writes are stamped with arm A's run id — `ottoq_sim_stop_and_reset` sets the transaction-local `ottoq.sim_run_id` GUC to the run it tears down and nothing re-points it before the next arm's fleet reset. Measured: arm A's run carries **exactly 116 more** `vehicle.state_changed` trigger events than arm B's, on the same pair. The larger half is arm A, where the GUC is not yet set at all: `ottoq_active_sim_run_id()` returns NULL, and the state-change trigger writes `data_source = CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END` — so the harness emits **~109 HMAC-signed events per pair labelled `production`**, 26,740 of them live in the current retention window. No round can fail on it: both arms exclude their own reset events from `h_evt` symmetrically, and arm B's contamination of arm A's run lands after arm A was hashed. Invisible to the verdict by construction. | [0131](db/checks/0131_the_certification_writes_twenty_six_thousand_production_labelled_events.sql) | two options costed in 0131 Q7: suppress the reset's events (hash-neutral) or re-point the run id (correct, moves every column's `h_evt`, forces_recert TRUE) | open |

## Open, but diagnosed this session

| # | Finding | Evidence | Fix | State |
|---|---|---|---|---|
| **G21** | The site load meter re-derives *which run is running* once per candidate charge-session row. `twin.ottoq_sim_compute_charger_load_kw` calls `ottoq_depot_running_run(p_depot_id)` on the right of its WHERE-clause run-scope comparison: **8,966,506 evaluations in one 12-tick pair, 108.8 s, 8,756 per call**, of a value constant for the call. The call sits opposite a Var (so it is a per-row filter expression) and the function carries a `SET` clause (so it is not inlinable). The whole meter is 195.4 s of the 700.7 s pair `0129` profiled — **28%**, and ~36% of the 537 s pair after 0222. Cross-checked from the other side: the self-times of everything that calls it sum to **197.3 s** against the meter statement's **195.4 s** — so after the fingerprint, the two largest self-times in the engine profile (`ottoq_l2_propose_stall_assignment` 124.9 s, `ottoq_eval_en_001_grid_capacity` 62.9 s) are this meter seen from its callers, and those callers have almost no cost of their own. Found by reading the `pg_stat_user_functions` half of the r25_g capture that 0129 never opened, and by ranking statements by **calls** rather than seconds. | [0130](db/checks/0130_the_load_meter_asks_which_run_is_running_nine_million_times.sql) | **0223 drafted** | fix written, not applied — waits for round 26 to finish |
| **G22** | The refusal reactor says `production` and hands you a sim run id. `ottoq.ottoq_react_to_refusals` hardcodes `p_data_source:='production'` at both escalation call sites while passing `p_sim_run_id:=p_sim_run_id` on the next line: **71,944 signed events across 494 sim runs** assert production provenance and carry a simulation run. It is the largest production-labelled event type in the database. Together with G16's 26,856 fleet-reset events, **98,800 of the 98,834 production-labelled rows in a 2.28M-row signed stream are the certification harness — the `production` half of the event stream is 99.97% harness.** | [0132](db/checks/0132_the_refusal_reactor_hardcodes_production_and_passes_a_sim_run_id.sql) | **[0224](db/migrations/0224_the_refusal_reactor_says_production_and_hands_you_a_sim_run_id.sql) drafted**, `forces_recert` FALSE *proven* rather than predicted — its P1 asserts against the live verdict function that `h_evt` never reads `data_source` | fix written, not applied — waits for round 26 |
| **G23** | The retention purge covers the event stream and barely touches the calendar. Lifetime insert/delete: `ottoq_events` 97% purged, `ottoq_rule_evaluations` 45%, **`ottoq_stall_bookings` 14%**, `ottoq_service_detail_records` 6%. The calendar is an **accumulation, not a rolling window** — it grows ~800 rows per certification pair, forever, and [0127](db/checks/0127_the_run_scope_predicate_that_no_index_can_read.sql) measured it at 53% of every disk block this database has ever read. Same shape as G19/G21 from the storage side: a fixed workload whose cost grows because the table it crosses grows. | [0133](db/checks/0133_two_clocks_the_batch_proof_and_the_live_request.sql) Q4 | two questions, and the first is not the build track's: (1) are a finished twin run's bookings evidence worth keeping? (2) if yes, the hot path must stop crossing them — 0221 did that for one function, 0130 Q9 proposes doing it broadly | open |
| **G25** | **Four enforced atoms are outside the canon comparison.** The pair enforces fourteen equalities; `ottoq_cert_matrix`'s `on_canon` — which feeds `consecutive_passes`, which feeds `green` — compares **nine**. `h_rule` (enforced 0205), `h_rcl` (0217), `h_sdr` (0219, this morning) and `endst` (0139) are not among them. Worse: `canon_rule` and `canon_rcl` are *returned as columns* — carried, printed, never judged, so a reader sees them beside `canon_cmd` with no way to know only one can break a streak. A change moving one of those four **identically on both arms** passes the pair, keeps `on_canon` true, advances the streak and leaves `green` true while the canon silently moves. Round 26 caught it only because two markdown files were diffed by hand. | [0134](db/checks/0134_four_enforced_atoms_are_outside_the_canon_comparison.sql) | extend the matrix to carry `c_sdr`/`c_endst` and to compare `c_rule`/`c_rcl`, using the 0199/0201 NULL-tolerant form so historical streaks do not retroactively break; not drafted yet because round 27 already judges 0223 and 0224 | open |
| **G24** | **There is no load test.** What is measured is a 34–40 day *lifetime* mean — 24–47 ms per request over 637,473 calls at ~5.6 calls/min — and the counters did not move across 75 idle seconds. That is evidence the code path is fast and none at all that the system is fast under concurrency. The attempt to settle the 8–20 s tail by differencing latency inside and outside a certification-pair window is recorded *as a failure*: at 5.6 calls/min a 19-minute window holds ~100 calls against a 19-second tail. | [0133](db/checks/0133_two_clocks_the_batch_proof_and_the_live_request.sql) | **approved by Chase, queued** — synthetic vehicle traffic at a stated rate through the RPC surface, p50/p95/p99, keyed by run ID like every other claim, run both with and without a pair in flight | open |
| **G26** | **Production and the proof harness share one database.** A pair holds the flagship depot in one transaction for 9–18 minutes, six pairs a round, several rounds a day, on the database the API serves. Leading candidate for G24's tail, and the structural reason G16 and G22 can put harness rows into the production-labelled event stream at all. | [0133](db/checks/0133_two_clocks_the_batch_proof_and_the_live_request.sql) Q3 | **approved by Chase, queued** — three options costed in the task; a separate project for the twin looks right and would close G12 as a side effect, but the choice is his | open |
| **G21b** | Second order, recorded and deliberately **not** chased: `ottoq_policy_get` is called **2,413,581 times per pair** for 105.9 s. Its call sites are spread over 65 functions and the dominant consumer has not been isolated. This task has already spent four wrong guesses on G19; the next step is an instrumented pair, not a hypothesis. | [0130](db/checks/0130_the_load_meter_asks_which_run_is_running_nine_million_times.sql) Q7 | — | open, uninvestigated |

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
| G17 | KPI-4's touch vocabulary was seven-eighths unsatisfiable — seven of its eight actor types were rejected by the `ottoq_events` CHECK — and it missed every real human actor the constraint does permit. | [0213](db/migrations/0213_kpi_four_counted_seven_actor_types_that_cannot_exist.sql) — vocabulary is now a table pinned to the live CHECK; 20 classified, 8 human, none uninsertable |
| G19 | The certification pair got ~2x slower in seven days on a fixed workload. `ottoq_boot_state_fingerprint` — the enforced `endst` atom — serialized and MD5'd **1,360,915 rows per call**, four calls per pair, to characterise **13**. | [0222](db/migrations/0222_the_fingerprint_hashed_a_million_rows_to_report_thirteen.sql) — the fingerprint measured **260.6 ms / 218.2 ms** against ~64,000 ms after; round 26 a and b landed **537 s and 533 s** against a 16-pair baseline of min 643 / mean 755. Evidence: [0129](db/checks/0129_the_fingerprint_hashes_five_million_rows_to_report_thirteen.sql), [0126](db/checks/0126_where_the_tick_actually_spends_its_time.sql), [0128](db/checks/0128_the_pair_reads_nine_gigabytes_and_seven_of_them_are_five_scans_of_one_table.sql) (conclusion superseded) |
| G20 | The second SDR emitter would bill a DCFC charge at the L2 tariff: `charge` is the one `svc_code` mapping to two operations and the lookup picked with an unordered `LIMIT 1`. Dormant since 2026-06-18, so nothing burned. | [0220](db/migrations/0220_the_schedule_task_emitter_asks_the_stall_what_kind_of_charge_it_was.sql) — the trigger asks `stalls.stall_type`, not the heap. Evidence: [0124](db/checks/0124_the_other_sdr_emitter_would_bill_a_dcfc_charge_at_the_l2_tariff.sql) |

---

## Not ours to close — founder actions

These are open, they are the highest-severity items on this page, and no
migration can close them.

| # | Finding | State |
|---|---|---|
| **S-01 / S-02** | A shared secret was committed to the repository. The **code half is fixed**: the literal is gone and the bridge fails closed rather than open, pinned by `ottoq-intelligence/tests/test_auth_fails_closed.py`. A committed secret stays compromised until it is **rotated**, which is an operator action on EC2 and in Supabase. | open — awaiting rotation |

Everything else in [`docs/MAGENTA_AUDIT.md`](docs/MAGENTA_AUDIT.md) — 85 of 87
findings — is closed, each `FIXED` naming the guard that fails without it.

## The other thing on this page that is not ours to close

`db/migrations/UNFILED.md` lists **67 migrations, 734,007 characters**, applied to the
database with no committed file. They are recoverable from `ottoq_schema_snapshots`
and the function catalog. Whether to spend the time recovering them is Chase's
call, not the build track's, and the drift check reports **INVESTIGATE** rather
than CLEAN until it is made.
