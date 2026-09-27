-- 0386  **G240, steps 1b and 2: a charge the run's stop cut short is information, not noise, and a booking window
--       fitted without it describes the short charges only. 0515 makes the ledger record what each charge was
--       stopping at and the booking window the calendar gave it; 0516 fits the window by a split-conformal upper
--       bound that counts the cut charges, exactly, under the censoring a run's stop is.**
--
--       Written on 2026-09-27 (06:00-06:40 UTC, 1:00-1:40 AM CT). Read-only; nothing here writes except where §4 says
--       a fit was taken, which inserts one immutable calibration version.
--
--       Method source: Candès, Lei & Ren, "Conformalized survival analysis", JRSSB 85(1):24-45, published
--       2023-01-28, doi:10.1093/jrsssb/qkac004, https://academic.oup.com/jrsssb/article/85/1/24/7008653 and
--       https://arxiv.org/abs/2103.09763 (read 2026-09-27): under Type I right-censoring -- every unit's censoring time
--       known -- conformal inference on min(T, c0) over the units whose censoring time is at least c0 has finite-sample
--       coverage with no assumption beyond i.i.d. data. A run's stop is exactly that: a clock every charge in the run
--       shares, set by the operator, not by the charge. 0516 mirrors their lower-bound construction for an upper bound
--       on the pace ratio. Charges within one run share a day and a fleet, so the leave-one-run-out read is the
--       empirical check of the i.i.d. part, as in 0385.

-- ══ §1 WHAT THE SIMPLE FIT HID ═════════════════════════════════════════════════════════════════════════════════

\echo '=== 0386 §1 — finished and cut charges on runs of two hours or more, by charger type and air band ==='
WITH led AS (
  SELECT l.*, max(l.ended_at) OVER (PARTITION BY l.sim_run_id) AS run_end,
         EXTRACT(epoch FROM max(l.ended_at) OVER (PARTITION BY l.sim_run_id) - min(l.started_at) OVER (PARTITION BY l.sim_run_id)) / 60 AS span_min
    FROM public.ottoq_charge_duration_ledger l
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.run_by = 'operator_demo' AND l.capture_version = 1)
SELECT charger_type, public.ottoq_charge_air_band(ambient_temp_c, '{5,15,25}') AS band,
       count(*) FILTER (WHERE stopped_reason = 'completed') AS finished,
       count(*) FILTER (WHERE stopped_reason = 'sim_reset') AS cut_by_the_stop
  FROM led WHERE span_min >= 120 AND charger_type IN ('dcfc','l2')
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 06:00 UTC, the ten operator runs in 0514's backfill that ran two hours or more):
--     dcfc  a 43 / 7    b 57 / 14    c 87 / 22    d 69 / 31
--     l2    a 40 / 36   b 51 / 48    c 126 / 89   d 50 / 107
--   L2 overall 267 finished against 280 cut; in the hottest band the cut outnumber the finished two to one, because the
--   hottest air is late in the morning and the stop comes at late morning.

\echo '=== 0386 §1(b) — among charges whose run gave them twice their nominal to finish: the pace ratio by nominal length ==='
-- (nominal to full charge for the selection, so that it does not depend on how the charge ended; 0516 §2(1))
WITH led AS (
  SELECT l.*, max(l.ended_at) OVER (PARTITION BY l.sim_run_id) AS run_end,
         EXTRACT(epoch FROM max(l.ended_at) OVER (PARTITION BY l.sim_run_id) - min(l.started_at) OVER (PARTITION BY l.sim_run_id)) / 60 AS span_min
    FROM public.ottoq_charge_duration_ledger l
   WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.run_by = 'operator_demo' AND l.capture_version = 1
     AND l.stopped_reason IN ('completed','sim_reset') AND l.charger_type IN ('dcfc','l2')),
p AS (
  SELECT led.*, CASE WHEN stopped_reason = 'completed' THEN nominal_min
                     ELSE public.ottoq_charge_minutes_between(soc_start, GREATEST(soc_start + 1, 100), charger_kw, vehicle_kw, battery_kwh) END AS n_i,
         EXTRACT(epoch FROM run_end - started_at) / 60 AS runway
    FROM led WHERE span_min >= 120),
s AS (
  SELECT p.*, CASE WHEN stopped_reason = 'completed' THEN LEAST(duration_min / n_i, 2.0) ELSE 2.0 END AS y,
         CASE WHEN n_i < 30 THEN '1:<30' WHEN n_i < 60 THEN '2:30-60' WHEN n_i < 120 THEN '3:60-120' ELSE '4:120+' END AS len
    FROM p WHERE n_i > 0)
SELECT charger_type, len, count(*) AS n_all, count(*) FILTER (WHERE runway / n_i >= 2.0) AS n_judged,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY y) FILTER (WHERE runway / n_i >= 2.0))::numeric, 3) AS median,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY y) FILTER (WHERE runway / n_i >= 2.0))::numeric, 3) AS p90
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 06:06 UTC; this read uses each finished charge's own span nominal for its length, a diagnostic):
--     dcfc  <30: 62 of 73 judged, median 1.083 p90 1.393   30-60: 57 of 111, 0.962 / 1.322   60-120: 63 of 144, 1.146 / 1.544
--     l2    <30: 47 of 48, 1.028 / 1.223   30-60: 70 of 73, 1.108 / 1.494   60-120: 48 of 93, 1.155 / 1.508
--           120+: 7 of 333, 1.183 / 1.682
--   Two facts. The pace ratio rises with length (L2's p90 from 1.22 to 1.68). And the long L2 charges -- 333 of the 547
--   -- are almost never judged on a three-hour run: 7 of them had twice their nominal left before the stop. A fit from
--   finished charges alone is therefore a fit to short charges, and its factor is optimistic for the long ones.

-- ══ §2 0515: WHAT THE LEDGER NOW RECORDS ═══════════════════════════════════════════════════════════════════════

\echo '=== 0386 §2 — 0515 in the migration ledger ==='
SELECT version, md5(statements[1]) AS body_md5 FROM supabase_migrations.schema_migrations
 WHERE name = 'the_ledger_records_what_the_charge_was_booked_for_and_aimed_at';
-- READ (2026-09-27 06:03 UTC): version 20260927060333, body md5 0d5f428c58ddcf0442d5b2a526e1249d, the file's body byte
--   for byte. Dry run and apply V3 passed: a stop with a booking captured as version 2 with its stop target, its visit,
--   the car's SoC and exactly the planted booking; one with no booking still captured; a certification arm writes
--   nothing; and a session with no run is captured. That last one is the hole 0515 closed on the way: 0514's capture
--   read the run's kind from a PL/pgSQL record that is never assigned when a session has no run, which raises inside
--   the capture and is swallowed by its own handler -- so a production charge, the kind with no run, would never have
--   been recorded. None had occurred yet (0385 §1(b)). The dry run was first written with records in the new blocks
--   too; reading into scalars removed the class. The existing 992 rows read capture_version 1, the new columns empty.

\echo '=== 0386 §2(b) — version-2 captures on the full-day validation run 4bc19d29 ==='
SELECT capture_version, stopped_reason, charger_type, count(*) AS n,
       count(*) FILTER (WHERE charge_target_soc IS NOT NULL) AS with_target,
       count(*) FILTER (WHERE booking_id IS NOT NULL) AS with_booking,
       count(*) FILTER (WHERE stopped_reason = 'completed' AND abs(soc_end - charge_target_soc) <= 1) AS ended_at_target,
       count(*) FILTER (WHERE booking_id IS NOT NULL AND ended_at > booked_to) AS outlasted_booking,
       round(avg(charge_target_soc - visit_target_soc) FILTER (WHERE visit_target_soc IS NOT NULL), 2) AS mean_target_gap
  FROM public.ottoq_charge_duration_ledger
 WHERE sim_run_id = '4bc19d29-790c-4cb0-9e2e-ae090a7da57b'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 06:16 UTC, twelve real minutes into the run, sim 9:28 AM): every row version 2 with every new column
--   filled. Completed: dcfc 9, l2 13, and all 22 ended at their stop target -- the column means what it says. Their
--   bookings: 4 of 9 DCFC and 7 of 13 L2 charges outlasted the window the calendar gave them, which is G240 read for the
--   first time from evidence that survives the run. The stop target sat above the visit's target by a mean 2.2 points
--   on DCFC and 0.8 on L2: the booking writer sizes to the visit's target, the twin stops at the car's (capped), and the
--   difference is part of what the calibration has to absorb.

-- ══ §3 0516: THE FIT ═══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0386 §3 — 0516 in the migration ledger ==='
SELECT version, md5(statements[1]) AS body_md5 FROM supabase_migrations.schema_migrations
 WHERE name = 'the_booking_window_is_fitted_from_the_charges_with_the_run_s_stop_counted';
-- READ (2026-09-27 06:15 UTC): version 20260927061451, body md5 f962b0759d6a15515f06fd3abf5261d1, the file's body byte
--   for byte. No version is kept by the apply (0 rows): V3's fits roll back with it.
--   Two things the dry runs caught before the apply, both worth keeping:
--   (a) The first dry run failed V3 (b): six cells' factors covered fewer judged charges than their k. The factor was
--       `round(ys[k], 4)`, and rounding to four places can go DOWN, below the k-th score, so the k-th charge falls
--       outside its own window. A conformal bound is only as good as the order statistic it is; the factor is now
--       rounded UP, identically in the fit and in its leave-one-run-out read.
--   (b) A timing probe run before the dry run was executed as plain SQL, which commits: it created the band function,
--       the calibration table and its trigger, and the evidence reader outside any migration, the last with Supabase's
--       default EXECUTE grant to the browser keys, for about a minute (06:08-06:10 UTC). They were checked for
--       dependents and rows (none) and dropped at 06:10:05 UTC, and the migration then created them properly with
--       their grants revoked. Recorded because it is exactly the kind of exposure a migration's V1 exists to prevent:
--       measure inside a rolled-back transaction or not at all.
--   V3 PASSED on the ledger at 06:14 UTC (the nine finished runs and caf85837; the full-day run had not yet written a
--   judged charge): 192 judged charges; two fits of one evidence identical in every cell, run list and code md5; every
--   factor covering at least its k; the writer's lookup taking dcfc:c (n 35, factor 1.3173) at 20 C and nothing when no
--   cell is adequate; versions refusing UPDATE and DELETE. The cells of that fit, for the record:
--     dcfc  a 1.0832 (n 15)   b 1.1395 (25)   c 1.3173 (35)   d 1.7193 (24)   all 1.4132 (99)
--     l2    a 1.2208 (13)     b 1.1834 (14)   c 1.2169 (42)   d 1.9718 (24)   all 1.4998 (93)
--   no judged charge cut (n_cut 0 everywhere), and the judged charges' median nominal-to-full half the population's
--   (48.0 against 93.1 minutes on DCFC, 66.5 against 158.7 on L2).
--   Its leave-one-run-out coverage: 167 of 192 = 87.0% (DCFC 87.9%, L2 86.0%), below the 90% asked. The honest reading:
--   with min_group_n 30 only two band cells stand on their own, so most charges fall back to their charger type's
--   pooled factor, which under-covers the hot band and over-covers the mild ones; and a run's charges share a day,
--   which leave-one-run-out exposes and a pooled in-sample read would hide. 0385 §4's 91.3% was measured on finished
--   charges; this is the lower, truer number.

-- ══ §4 THE FIRST KEPT FIT, AFTER THE FULL-DAY RUN ══════════════════════════════════════════════════════════════
--
--   PREDICTED before the run ends: (a) the full-day run 4bc19d29 adds judged L2 charges with long nominals (a 12-hour
--   run gives a 3-hour charge started before 2 PM its runway), so l2:* and the L2 band cells gain n and the judged
--   median nominal moves toward the population's; (b) the l2 factors rise (§1(b): long charges run relatively longer);
--   (c) the leave-one-run-out coverage moves toward 90% as more band cells stand on their own.

\echo '=== 0386 §4 — the kept fit: its cells and its leave-one-run-out read ==='
SELECT calibration_id, fitted_at, evidence_through, n_judged, array_length(source_runs, 1) AS runs, loro,
       (SELECT jsonb_object_agg(k, jsonb_build_object('n', v -> 'n', 'factor', v -> 'factor', 'n_cut', v -> 'n_cut',
                                                      'med_nom_judged', v -> 'median_nominal_judged',
                                                      'med_nom_all', v -> 'median_nominal_all'))
          FROM jsonb_each(cells) c(k, v)) AS cells
  FROM public.ottoq_charge_window_calibration ORDER BY calibration_id;
-- READ (2026-09-27 07:33 UTC, 2:33 AM CT). The full-day run did not reach 8 PM: the run governor stopped it at 07:12 UTC
--   at its 540 sim-minute ceiling ("run_governor: reached the 540 sim-minute ceiling"), sim 8:00 AM - 5:02 PM, 1,035
--   ticks, its stop captured as 39 cut charges (9 DCFC, 30 L2) beside 128 completed and 22 faulted. The fit, version 6,
--   `ottoq_fit_charge_window_calibration(twin, 0.10, 2.0, 30, 120, '{5,15,25}', NULL, note)`, evidence through 07:12:00
--   UTC, 11 runs, 311 judged charges (192 before):
--     l2    a 1.2208 (13)   b 1.1834 (14)   c 1.3611 (73)   d 1.7469 (51)   all 1.5748 (151)
--     dcfc  a 1.0832 (15)   b 1.1395 (25)   c 1.4010 (48)   d 1.6036 (72)   all 1.5066 (160)
--   no judged charge cut (n_cut 0 everywhere); judged median nominal 73.2 minutes on L2 (population 153.0), 48.8 on DCFC
--   (84.6). Leave-one-run-out: 253 of 311 = 81.35% (DCFC 83.1%, L2 79.5%). Code md5s: fit 875440a0, evidence 54674fcf,
--   band e8cf9910, charge model 14a1e1ab.
--   (a) HELD, modestly: judged L2 charges 93 -> 151, and two L2 band cells now stand on their own (c 42 -> 73, d 24 ->
--   51); the judged median nominal moved only 66.5 -> 73.2 against a population of 153, because a charge is judged when
--   the run gave it twice its nominal and a 3-hour charge needs 6 hours of runway: at 9 hours, only the morning's long
--   charges qualify. (b) PARTLY: l2:* rose 1.4998 -> 1.5748 and l2:c 1.2169 -> 1.3611, but l2:d fell 1.9718 -> 1.7469 --
--   its first 24 charges were the hottest of the mornings, the full day added 27 more ordinary band-d charges; dcfc:*
--   rose 1.4132 -> 1.5066. (c) FAILED: coverage fell to 81.35%, not toward 90%, and it splits cleanly by the held-out run
--   (replicated outside the fit, 253 of 311 exactly): the full day held out is covered 70 of 119 = 58.8% (L2 31 of 58),
--   the ten morning runs 183 of 192 = 95.3%. The mornings never saw a hot afternoon. Every full-day L2 charge from 9 AM
--   on started in air of 25.8 C or more and paced 1.36 to 1.61 on average by start hour (9 AM 1.355, noon 1.609), where
--   the mornings' L2 charges, 80 of 93 started at 8 AM in 16 C air, paced 1.11. Held out, the full day is fitted by
--   factors learned from mild mornings, and its hot band-d L2 cell had fewer than 30 charges without it, so it fell back
--   to the pooled l2:* factor of the mornings. That is covariate shift, which a conformal bound does not promise
--   against: the guarantee is for a charge exchangeable with the ones it was fitted on, and a full day is not
--   exchangeable with a morning. What the kept fit has that the held-out read did not: the hot cells now stand on their
--   own (l2:d 51, dcfc:d 72), so a full day like this one is inside what version 6 has seen. The honest statement is two
--   numbers: 95.3% for a day like the ones it learned from, 58.8% for a kind of day it had never seen.

-- ══ §5 0517: THE BOOKING WRITER BEHIND A DIAL ══════════════════════════════════════════════════════════════════

\echo '=== 0386 §5 — 0517 in the migration ledger, the dial, and who sets it ==='
SELECT m.version, md5(m.statements[1]) AS body_md5,
       (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_window_calibration_id') AS dial_default,
       (SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'charge_window_calibration_id') AS scopes_setting_it
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'a_calibrated_charge_window_behind_a_dial';
-- READ (2026-09-27 06:22 UTC): version 20260927062217, body md5 82dfa7487b61996528c966ac1c7a1995, the file's body byte
--   for byte; the dial defaults to 0 and no scope sets it, so every run -- the live one and every certified arm --
--   books exactly as before. Writer body after: 746d1492017931b4cbf17a66d22a2015; `0517_pre` snapshot 1.
--   V3 passed in the dry run and the apply, on the newest finished operator run, four, eight and twelve hours past its
--   end (the migration's own V3 comment says "four and eight"; case (c) is at twelve):
--   with the dial at 0 a charge booking for a car below 60% on an L2 was 229 minutes -- the old window, nominal to the
--   visit's target (the default 85, the run's visits being closed); with the dial naming a version fitted inside the
--   test it was 480 minutes: nominal 324.3 to the car's own stop target, times the L2 charger-type factor 1.4998, clamped
--   at 480; a dial naming no version booked the old 229. The gap between 229 and 324.3 is the target mismatch the
--   calibration was measured without (§2(b)): this car charges to where it stops, not to 85.
--   What is not done: the dial is off. Turning it on is a paired experiment at the operator's tick -- two live runs of
--   one seed, dial 0 against a named version -- read on the share of charges that outlast their booking (0515 records
--   it durably), the wait for a charger, and the refusals.

-- ══ §6 THE WINDOW AS BOOKED TODAY: HOW MANY CHARGES OUTLAST THEIR BOOKING ════════════════════════════════════════
--
--   The measure a paired experiment on the dial is judged by (0520 makes it an arm metric). Read from the ledger's
--   version-2 captures, which record each charge's booking as it stood at the stop: the calendar itself cannot answer
--   this afterwards, because a booking's end is moved after its charge stops (§6(b)).

\echo '=== 0386 §6 — completed charges with a booking, and how many outlasted it, by run and charger type (dial 0) ==='
SELECT left(l.sim_run_id::text, 8) AS run, l.charger_type,
       count(*) AS completed_booked,
       count(*) FILTER (WHERE l.ended_at > l.booked_to) AS outlasted,
       round(100.0 * count(*) FILTER (WHERE l.ended_at > l.booked_to) / NULLIF(count(*), 0), 1) AS pct_outlasted,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM l.ended_at - l.booked_to) / 60)
              FILTER (WHERE l.ended_at > l.booked_to))::numeric, 1) AS p50_overrun_min
  FROM public.ottoq_charge_duration_ledger l
 WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.capture_version = 2 AND l.run_by = 'operator_demo'
   AND l.stopped_reason = 'completed' AND l.booked_to IS NOT NULL
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 07:45 UTC; 4bc19d29 is the one operator run captured at version 2, 0515 having applied at 06:03):
--     dcfc  62 completed with a booking  38 outlasted it  61.3%  median overrun 21.4 minutes
--     l2    65                           53              81.5%                49.8
--   With the window as booked today, most charges outlast the booking the calendar holds for them: a charger the
--   calendar says is free is, more often than not, still charging. This is the number a paired experiment on the dial
--   is judged by (0520): the version-6 factors, read leave-one-run-out, say 58.8-95.3% of charges would fit.

\echo '=== 0386 §6(b) — a charge''s booking, at its stop and now ==='
SELECT l.stopped_reason, count(*) AS charges,
       count(*) FILTER (WHERE upper(b.during) = l.booked_to) AS booking_end_unchanged,
       count(*) FILTER (WHERE upper(b.during) = l.ended_at AND l.ended_at <> l.booked_to) AS moved_to_the_stop,
       count(*) FILTER (WHERE upper(b.during) <> l.booked_to AND upper(b.during) <> l.ended_at) AS moved_elsewhere
  FROM public.ottoq_charge_duration_ledger l
  JOIN public.ottoq_stall_bookings b ON b.booking_id = l.booking_id
 WHERE l.sim_run_id = '4bc19d29-790c-4cb0-9e2e-ae090a7da57b'
 GROUP BY 1 ORDER BY 2 DESC;
-- READ (2026-09-27 07:45 UTC): of 127 completed charges, 91 bookings still end where they did at the stop, 12 now end at
--   the stop and 24 somewhere else; every charge the run's stop cut (38 with a booking) and every faulted one kept or took the stop's
--   end. So 36 of 127 completed charges' bookings moved after the fact: read at the end of a run, the calendar would
--   report some of those charges as fitting their windows. The outlast measure has to come from the stop-time capture,
--   which is why 0520 reads the ledger and not the calendar.
