-- 0389  **G240, step 4: the calibrated booking window judged the way a dial is judged here -- a designed pair, one
--       seed and one world per pair, control and treatment differing only in the dial -- read on the share of charges
--       that outlast their booking, with the five KPIs as guardrails. 0520 is the instrument; this check reads it.**
--
--       Written on 2026-09-27 (from 07:55 UTC, 2:55 AM CT). Read-only, except §2, which registers one experiment.
--
--       Why a designed pair and not two live runs: a live run's cadence is the wall clock's (0.3-1.5 sim-minutes a tick,
--       G161), so two live runs of one seed differ in cadence as well as in the dial and cannot be paired. The dial pair
--       holds cadence, seed, scenario and sim start fixed and resets the world before each arm (0421), so the arms differ
--       only in `charge_window_calibration_id`. Its one cost: a coarse tick reads a charge's end late in both arms -- up to
--       6 minutes at the registered 6-minute tick (§2), against the ~0.5-minute ticks version 6 was fitted on -- so the
--       treatment's windows are about 3 minutes short on average and the experiment is, if anything, biased against it.

-- ══ §1 0520 AS APPLIED ══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0389 §1 — 0520 in the migration ledger ==='
SELECT m.version, md5(m.statements[1]) AS body_md5,
       (SELECT column_default FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'ottoq_dial_experiments' AND column_name = 'sim_min_per_tick') AS cadence_default
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'a_paired_experiment_can_judge_the_booking_window_at_a_charge_s_own_cadence';
-- READ (2026-09-27 08:17 UTC, 3:17 AM CT): version 20260927081719, body md5 12acbcb3b49e9af59a5f87a6953af2b9, the
--   file's body byte for byte; cadence default 30; forces_recert FALSE, and the canon stayed at its floor. Applied after
--   the 0518/0519 sweep (0387 §3) with no run and no rig live. V3 passed in the dry run and the apply: the arm metrics
--   on 4bc19d29 read exactly the ledger's 91 of 127 completed charges outlasting their booking; a harness run started
--   the way the pair now starts one, at time_scale 4, advanced 2 minutes in one tick; and a charge stopped on that run
--   42 minutes after a 30-minute booking was captured with the booking, invisible to the calibration's evidence reader,
--   and scored by the arm metrics as 1 of 1 outlasting by 12 minutes.

-- ══ §2 THE EXPERIMENT ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   PRE-REGISTERED before its first pair: `charge_window_calibration_id` 0 (control, the window as booked today) against
--   6 (treatment, the first kept fit), busy_day from 8:00 AM CT (2026-09-01 13:00 UTC) to 5:00 PM (the governor's ceiling
--   on an operator run), primary `charge_outlast_pct`, lower is better, looks at 6 and 12 pairs, alpha 0.05, minimum
--   effect 0.5%, guardrails the five KPIs at a 2% margin and alpha 0.20 -- the conventions of the three experiments
--   before it.
--   AMENDED BEFORE ITS FIRST PAIR, and the amendment is the design that runs: drafted at 2 sim-minutes a tick for 270
--   ticks, and refused at registration by `ottoq_dial_experiments_ticks` (12 to 96 ticks, a bound on a pair's wall time
--   that 0520 left as it was), so registered at 6 sim-minutes a tick for 90 ticks -- the same nine hours. The cost is
--   the one in the header, tripled: a charge's end is read up to 6 minutes late in both arms. Nothing else moved.
--   PREDICTED: (a) the treatment lowers `charge_outlast_pct` on every pair, from about 70% (61.3% DCFC and 81.5% L2 on
--   `4bc19d29`, 0386 §6) toward the 5-40% version 6 promises for days like the ones it saw (0386 §4); (b) the median
--   overrun of the charges that still outlast falls; (c) not predicted, read: the guardrails -- a longer window holds a
--   charger longer on the calendar, which could lower turns per point or lengthen the wait for a charger, and that
--   price is the question the experiment exists to answer.

\echo '=== 0389 §2 — the experiment as registered ==='
SELECT experiment_id, created_at, param_key, control_value, treatment_value, scenario, ticks, sim_start, sim_min_per_tick,
       primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
       guardrail_alpha, status
  FROM public.ottoq_dial_experiments WHERE param_key = 'charge_window_calibration_id' ORDER BY created_at;
-- READ (2026-09-27 08:55 UTC): experiment 143a11c7-6740-4624-b747-e145f3533e60, registered 08:33:33 UTC (3:33 AM CT),
--   `charge_window_calibration_id` 0 against 6, busy_day, 90 ticks from 2026-09-01 13:00 UTC at 6 sim-minutes a tick,
--   primary `charge_outlast_pct` lower, looks 6 and 12, alpha 0.05, guardrail margin 2% at alpha 0.20, minimum effect
--   0.5%, active, 0 pairs. The dial runner was opened for the night at the same minute. Its first pair on this engine
--   will be on 0521's (`db/checks/0390`): the runner's 3:40 AM fire went to the older energy experiment 82c5568b, the
--   tie on pair count going to the older, and 0521 was applied between that pair and the next, so every pair this
--   experiment counts was run on one engine.

-- ══ §3 THE PAIRS ════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0389 §3 — each pair: the window measure and the KPIs, control against treatment ==='
SELECT l.pair_id, l.seed, l.ran_at, l.complete, l.world_identical, l.both_paid_shield, l.differs, round(l.wall_s) AS wall_s,
       l.metrics_a->>'charge_outlast_pct' AS outlast_a, l.metrics_b->>'charge_outlast_pct' AS outlast_b,
       l.metrics_a->>'charge_outlast_pct_dcfc' AS dcfc_a, l.metrics_b->>'charge_outlast_pct_dcfc' AS dcfc_b,
       l.metrics_a->>'charge_outlast_pct_l2' AS l2_a, l.metrics_b->>'charge_outlast_pct_l2' AS l2_b,
       l.metrics_a->>'charges_completed_booked' AS n_a, l.metrics_b->>'charges_completed_booked' AS n_b,
       l.metrics_a->>'charge_overrun_p50_min' AS over_a, l.metrics_b->>'charge_overrun_p50_min' AS over_b,
       l.metrics_a->>'p95_time_to_service_min' AS p95_a, l.metrics_b->>'p95_time_to_service_min' AS p95_b,
       l.metrics_a->>'service_point_turns_per_point_per_day' AS turns_a, l.metrics_b->>'service_point_turns_per_point_per_day' AS turns_b
  FROM public.ottoq_dial_pair_ledger l
  JOIN public.ottoq_dial_experiments e ON e.experiment_id = l.experiment_id
 WHERE e.param_key = 'charge_window_calibration_id'
 ORDER BY l.pair_id;
-- READ (2026-09-27 10:09 UTC, 5:09 AM CT), the first pair, on 0521's engine f03cf4ee:
--     pair 76, seed 20516641458992974, 4:40 AM CT, 1,081 s wall; complete, world identical, both arms paid the shield
--                             control (0)   treatment (6)
--     charge_outlast_pct         72.55         29.41
--       DCFC                     65.71         31.43
--       L2                       87.50         25.00
--     charges judged                51            51
--     median overrun, minutes     44.0           4.0
--     p95 time to service, min    54.0          39.6
--     turns per point per day     1.74          1.64
--   One pair is one pair, and the verdict is the sign test's at 6 (§3(b)). What it shows so far: (a) as predicted, the
--   calibrated window cuts the share of charges that outlast their booking, from 73% to 29% on this seed -- inside the
--   5-40% version 6 promised -- and hardest on L2 (88% to 25%), where the booked window was furthest off; (b) as
--   predicted, the charges that still outlast do so by a median of 4 minutes, not 44; (c) the guardrails, read and not
--   predicted: time to service improved by 27%, and turns per point fell 5.7% -- a longer window holds a charger longer
--   on the calendar, which is the price §2 named, and past the 2% margin on this one pair. Whether that holds across
--   seeds is what the guardrail test at alpha 0.20 is for.

\echo '=== 0389 §3(b) — the verdict ==='
SELECT public.ottoq_dial_experiment_verdict(e.experiment_id) AS verdict
  FROM public.ottoq_dial_experiments e WHERE e.param_key = 'charge_window_calibration_id' ORDER BY e.created_at DESC LIMIT 1;
-- READ (2026-09-27 10:09 UTC): `collecting` -- 1 of the 6 counted pairs the first look needs, 0 invalid, 0 on a stale
--   engine, no safety flag (0 pairs with more unserved returns). The window closes at 6 AM CT. The runner alternates the
--   two active experiments by pair count on this engine, and this one's pair takes 18 minutes of wall time to the energy
--   experiment's 10, so the night can give it three pairs at most; the first look waits for the next dial window, and
--   holds only if no forces_recert migration lands before it (a new engine counts from zero).
