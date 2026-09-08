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
| **G16** | Arm B's boot writes are stamped with arm A's run id: teardown pins the GUC and nothing re-points it. | *not yet written up* | — | open |

## Open, but diagnosed this session

| # | Finding | Evidence | Fix | State |
|---|---|---|---|---|
| **G21** | The site load meter re-derives *which run is running* once per candidate charge-session row. `twin.ottoq_sim_compute_charger_load_kw` calls `ottoq_depot_running_run(p_depot_id)` on the right of its WHERE-clause run-scope comparison: **8,966,506 evaluations in one 12-tick pair, 108.8 s, 8,756 per call**, of a value constant for the call. The call sits opposite a Var (so it is a per-row filter expression) and the function carries a `SET` clause (so it is not inlinable). The whole meter is 195.4 s of the 700.7 s pair `0129` profiled — **28%**, and ~36% of the 537 s pair after 0222. Found by reading the `pg_stat_user_functions` half of the r25_g capture that 0129 never opened, and by ranking statements by **calls** rather than seconds. | [0130](db/checks/0130_the_load_meter_asks_which_run_is_running_nine_million_times.sql) | **0223 drafted** | fix written, not applied — waits for round 26 to finish |
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
