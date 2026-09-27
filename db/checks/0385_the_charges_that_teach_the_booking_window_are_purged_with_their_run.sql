-- 0385  **G240, step 1: every completed charge the booking window can be calibrated from lived in `ocpp_sessions`,
--       which is run-scoped engine data the demo-run purge deletes. The calibration's evidence was one purge from
--       gone, and a calibration that cannot be re-derived from its evidence is a claim on trust. 0514 moves it into an
--       append-only evidence ledger, and the ledger alone reproduces the G240 read to the last digit.**
--
--       Written on 2026-09-27 (05:20-05:40 UTC, 12:20-12:40 AM CT) around 0514's apply. Read-only; nothing here writes.
--
--       Why this comes before the fit. G240's read (a leave-one-run-out Mondrian split-conformal window, alpha 0.10,
--       charger type x air band, 91.3% coverage against the nominal window's 32.6% on 470 completed charges) was taken
--       from `ocpp_sessions`. The next `ottoq_start_demo_run` deletes prior runs' sessions (`ottoq_purge_prior_runs`
--       reads the run-scope registry and deletes every `class='engine'` table by run), and the nightly purge (cron 625)
--       is held off only because nothing else keeps these charges. A calibration fitted from rows that then vanish
--       cannot be checked by anyone after the fact -- the shape of 0231 (the cuOpt ledger) and 0329 (an archive that
--       moved under its verdicts). So the evidence is made durable first, and the fit (step 2) reads only the ledger.
--
--       Method source, as recorded in 0514's header: Angelopoulos & Bates, "A Gentle Introduction to Conformal
--       Prediction and Distribution-Free Uncertainty Quantification", arXiv:2107.07511 v6 (2022-12-07), §4.1
--       "Group-Balanced Conformal Prediction", Proposition 1, https://arxiv.org/abs/2107.07511 (read 2026-09-27):
--       per-group quantile at ceil((n_g+1)(1-alpha)) gives P(Y in C(X) | group) >= 1-alpha under exchangeability.
--       Charges within one run share a day and a fleet, so they are not exchangeable within a run; the leave-one-run-out
--       read below is the empirical check of that, not a proof.

-- ══ §1 THE EXPOSURE ═════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0385 §1 — how the run-scope registry classifies the sessions table and the new ledger ==='
SELECT table_schema || '.' || table_name || '.' || column_name AS col, class, left(note, 120) AS note
  FROM public.ottoq_run_scope_registry
 WHERE table_name IN ('ocpp_sessions', 'ottoq_charge_duration_ledger')
 ORDER BY 1;
-- READ (2026-09-27 05:29 UTC):
--     public.ocpp_sessions.sim_run_id                  engine    "run-scoped working data; must not outlive its run"
--     public.ottoq_charge_duration_ledger.sim_run_id   evidence  "0514 (G240 step 1): the durable record of stopped..."
--   Before 0514 only the first row existed. Every charge G240 was read from sat in a table the purge is built to empty.

\echo '=== 0385 §1(b) — stopped sessions surviving in ocpp_sessions, by the kind of run that wrote them ==='
SELECT COALESCE(r.run_by, '(no run)') AS run_by, count(*) AS stopped, count(DISTINCT os.sim_run_id) AS runs,
       count(*) FILTER (WHERE os.stopped_reason = 'completed') AS completed
  FROM public.ocpp_sessions os LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id
 WHERE os.stopped_reason IS NOT NULL
 GROUP BY 1 ORDER BY 2 DESC;
-- READ (2026-09-27 05:22 UTC, before the apply):
--     cert_harness     42,286 stopped over 550 runs (35,412 completed)
--     ab_harness        3,926 over 22 runs (3,624 completed)
--     operator_demo       888 over 10 runs (501 completed; nine finished runs and the live validation run caf85837)
--     production_live      17 over 1 run (all sim_reset)
--     (no run)              0
--   The ledger keeps the last two kinds only. Certification and A/B arms tick every 30 simulated minutes, so their
--   charges' lengths are quantised to the tick; an operator run advances about 0.6 simulated minutes a tick (the live
--   run's `payload.tick_minutes_actual` reads 0.603), which is fine enough to time a charge. A sweep would also add
--   thousands of rows a day.

-- ══ §2 0514 AS APPLIED ══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0385 §2 — 0514 in the migration ledger ==='
SELECT version, name, md5(statements[1]) AS body_md5
  FROM supabase_migrations.schema_migrations
 WHERE name = 'the_charges_that_teach_the_booking_window_are_purged_with_their_run';
-- READ (2026-09-27 05:28 UTC): version 20260927052757, body md5 2eea15ab13570f02a676b10cebfb11a9 -- the file's body
--   between BEGIN and COMMIT, byte for byte. The dry run passed at 05:26 UTC with the same body less P0; V3 passed in
--   both: a stop on an operator run captured once with the booking writer's nominal and the depot's air, a repeated
--   stop not written twice, the same stop on a certification arm not written at all, UPDATE and DELETE refused.
--   Two premises were corrected before the dry run: the booking writer's signature (it takes
--   (uuid,uuid,uuid,timestamptz,uuid,timestamptz,timestamptz,text,text), so P2 now finds it by name and checks the
--   four sizing inputs it reads), and V3's planted session (ocpp_sessions needs charge_point_id, a unique
--   transaction_id, evse_id and connector_id).

\echo '=== 0385 §2(b) — what the backfill holds ==='
SELECT source_kind, COALESCE(run_by, '(none)') AS run_by, charger_type, stopped_reason, count(*) AS n,
       count(*) FILTER (WHERE nominal_min IS NOT NULL) AS with_nominal,
       count(*) FILTER (WHERE depot_air_c IS NOT NULL) AS with_depot_air
  FROM public.ottoq_charge_duration_ledger
 WHERE source_kind = 'backfill'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, n DESC;
-- READ (2026-09-27 05:28 UTC): 915 rows, every stopped session on those runs (V2 asserted the equality at apply).
--     operator_demo dcfc completed 248, sim_reset 67, faults 23, all with the depot's air
--     operator_demo l2   completed 261, sim_reset 252, faults 44, orphan sweep 3
--     production_live l2 sim_reset 17
--   Every completed charge carries a nominal. The 339 cancelled rows (sim_reset, orphan sweep) carry none by design:
--   their soc_end is never written, because the stop paths that cancel a session do not read the car. They are kept:
--   a charge cut short by a reset is a censored observation, and the fit decides what to do with it, not the capture.
--   Every stall on the twin depot has its connector kW recorded (dcfc 350, l2 19.2), so the booking writer's default of
--   50 kW never applies here, and the ledger's nominal is the writer's own figure for the same span.

-- ══ §3 THE CAPTURE, LIVE ════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0385 §3 — charges captured by the trigger on the live run, against the sessions it stopped ==='
SELECT (SELECT count(*) FROM public.ocpp_sessions
         WHERE sim_run_id = 'caf85837-8681-4afe-9744-03eecd796737' AND stopped_reason IS NOT NULL) AS stopped_on_run,
       count(*)                                                                      AS in_ledger,
       count(*) FILTER (WHERE source_kind = 'capture')                               AS captured,
       count(*) FILTER (WHERE source_kind = 'capture' AND abs(ambient_temp_c - depot_air_c) <= 0.05) AS capture_same_air
  FROM public.ottoq_charge_duration_ledger
 WHERE sim_run_id = 'caf85837-8681-4afe-9744-03eecd796737';
-- READ (2026-09-27 05:30:51 UTC, 10:23 AM on the run's clock): 50 stopped on the run, 50 in the ledger -- 45 by the
--   backfill, 5 by the trigger in the three minutes after the apply, all 5 at the depot's air, and the 3 of them that
--   completed each with the booking writer's nominal. Nothing on the run was missed and nothing was written twice.
-- READ again after the operator stopped the run (05:43 UTC; stopped 05:37:07 at sim 11:13 AM): 98 sessions on the run,
--   all 98 stopped, all 98 in the ledger -- 45 backfilled and 53 captured. Of the 53: 14 completed, each with its
--   nominal; 35 `sim_reset`, the sessions the stop itself cancelled (`ottoq_sim_release_depot`), which is how a charge
--   still running at the stop reaches the ledger as a censored observation; 4 faults. All 53 at the depot's air. The
--   ledger holds 968 rows.

-- ══ §4 THE LEDGER ALONE REPRODUCES THE G240 READ ════════════════════════════════════════════════════════════════
--
-- The test that matters for evidence: can the claim be re-derived from the durable rows, with nothing from the
-- purgeable table? Leave one run out; for each held-out run and group (charger type x air band), the centre is the
-- median log(actual / nominal) of the OTHER runs' charges in the group, and the margin is the
-- ceil((n+1)(0.90))-th smallest (log ratio - centre) among them; a held-out charge is covered when its log ratio is
-- at most centre + margin. "factor" is exp(centre + margin), the multiple of the nominal the window would book.
-- Bands on `ambient_temp_c`, the air the charge's physics ran in (see §4(b)).

\echo '=== 0385 §4 — leave-one-run-out conformal coverage, computed from the ledger only ==='
WITH c AS (
  SELECT l.sim_run_id, l.charger_type, ln(l.duration_min / l.nominal_min) AS lr,
         CASE WHEN l.ambient_temp_c < 5 THEN 'a' WHEN l.ambient_temp_c < 15 THEN 'b'
              WHEN l.ambient_temp_c < 25 THEN 'c' ELSE 'd' END AS band
    FROM public.ottoq_charge_duration_ledger l
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id AND r.status = 'completed'
   WHERE l.run_by = 'operator_demo' AND l.stopped_reason = 'completed'
     AND l.depot_id = '11111111-1111-1111-1111-111111111111'
     AND l.nominal_min > 0 AND l.duration_min > 0),
runs AS (SELECT DISTINCT sim_run_id FROM c),
fit AS (
  SELECT h.sim_run_id AS held, c.charger_type, c.band, count(*) AS n,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY c.lr) AS centre,
         array_agg(c.lr ORDER BY c.lr) AS lrs
    FROM runs h JOIN c ON c.sim_run_id <> h.sim_run_id
   GROUP BY 1, 2, 3),
q AS (
  SELECT f.*, (SELECT s FROM (SELECT x - f.centre AS s FROM unnest(f.lrs) x ORDER BY 1) z
                OFFSET LEAST(f.n, ceil((f.n + 1) * 0.90)::int) - 1 LIMIT 1) AS margin
    FROM fit f),
test AS (
  SELECT c.charger_type, c.band, c.lr, q.centre + q.margin AS log_factor
    FROM c JOIN q ON q.held = c.sim_run_id AND q.charger_type = c.charger_type AND q.band = c.band)
SELECT COALESCE(charger_type, 'all') AS charger, COALESCE(band, '*') AS band, count(*) AS n,
       round(avg((lr <= log_factor)::int), 3) AS loro_cov,
       round(exp(percentile_cont(0.5) WITHIN GROUP (ORDER BY log_factor))::numeric, 2) AS factor,
       round(avg((lr <= 0)::int), 3) AS nominal_cov
  FROM test
 GROUP BY ROLLUP (charger_type, band)
 ORDER BY charger_type NULLS LAST, band NULLS LAST;
-- READ (2026-09-27 05:30 UTC), on the nine finished operator runs (the live run is excluded by status):
--     dcfc a  43  0.930  1.22  0.512        l2 a  40  0.925  1.22  0.250
--     dcfc b  57  0.912  1.13  0.632        l2 b  51  0.922  1.15  0.569
--     dcfc c  74  0.905  1.35  0.378        l2 c  99  0.899  1.32  0.141
--     dcfc d  57  0.912  1.72  0.193        l2 d  49  0.918  1.84  0.061
--     dcfc   231  0.913  1.35  0.420        l2   239  0.912  1.32  0.234
--     all    470  0.913  1.32  0.326
--   Identical, row for row and digit for digit, to the read taken from ocpp_sessions at 03:5x UTC. So the ledger
--   carries everything the fit needs, and G240's claim is now re-derivable after the purge. The coverage says what
--   G240 said: the nominal window holds a third of the charges; the group windows hold 90-93% in every group, at a
--   cost of booking 1.13x to 1.84x the nominal, the most in the hottest band.

\echo '=== 0385 §4(b) — the air the charge ran in against the depot''s air, before and after 0510 ==='
SELECT (l.sim_run_id = 'caf85837-8681-4afe-9744-03eecd796737') AS after_0510, count(*) AS n,
       count(*) FILTER (WHERE abs(l.ambient_temp_c - l.depot_air_c) <= 0.05) AS same_air,
       round(avg(abs(l.ambient_temp_c - l.depot_air_c)), 2) AS mean_abs_gap_c,
       round(max(abs(l.ambient_temp_c - l.depot_air_c)), 2) AS max_gap_c
  FROM public.ottoq_charge_duration_ledger l
 WHERE l.run_by = 'operator_demo'
 GROUP BY 1 ORDER BY 1;
-- READ (2026-09-27 05:31 UTC):
--     before 0510 (nine runs)   853 charges, 2 at the depot's air, mean gap 13.81 C, max 49.70 C
--     after 0510  (caf85837)     49 charges, 49 at the depot's air, gap 0.00
--   Before 0510 each charge drew its own air from the whole year (G241), and that draw set the battery's temperature
--   and so the charge's pace. So the G240 read is banded on the right variable for learning how air stretches a charge
--   -- the air the physics used -- and that is why §4 bands on ambient_temp_c, not depot_air_c. From 0510 on the two are
--   the same number, and it is one the booking writer can read when it books (`twin.ottoq_sim_site_ambient_c`). What
--   this changes for step 2: before 0510 the bands were filled by a whole-year draw (-13 to +38 C in one morning), and
--   after it they fill with September's air, so the cold bands will stop growing. A calibration fitted today leans on
--   pre-0510 charges for bands a and b; each version records the runs it read, so a later refit can drop them.

-- ══ §5 WHAT THIS DOES NOT DO ════════════════════════════════════════════════════════════════════════════════════
--
--   Nothing reads the ledger yet: no booking changes, no certified atom moves (0514 is forces_recert FALSE, and a
--   certification arm's stop returns at the trigger's first lookup). Step 2 fits a versioned calibration from it
--   (`ottoq_charge_window_calibration`, one row per fit, with alpha, the groups' n / centre / margin and the runs read),
--   and step 3 puts the booking writer behind a dial naming one version, so a refit is a dial change the canon
--   recertifies. The A/B needs a fine-tick dial pair (`ottoq_dial_pair` fixes time_scale 60 and 30-minute ticks today).
