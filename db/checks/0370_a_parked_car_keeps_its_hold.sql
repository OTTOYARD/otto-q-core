-- 0370  **G228: a car parked in staging to wait for a charger keeps a live hold on its stall (0500).**
--
--       0368 §11 found the charge queue's cars parked in staging on 12-17-minute parking holds that lapsed into
--       overstays, so the calendar called 33-38 occupied stalls free. 0500 renews an active parking hold whose window has
--       run out while its car is still parked on it. §1 is the census to read on a live run, §2 the rolled-back probe
--       behind 0500, §3 the canon under it. §1 takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

-- ══ §1 THE CENSUS: CARS PARKED IN STAGING, AND WHETHER THE CALENDAR KNOWS ═══════════════════════════════════════════
--
--   A car is parked on a staging stall when both pointers agree. It is on the calendar when a held or active booking of
--   its own on that stall covers the run's clock. Read live: the stop relabels live bookings.

\echo '=== 0370 §1 — cars parked in staging by state, and how many a live booking of their own covers ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
p AS (
  SELECT v.id, v.current_state::text AS st, s.id AS stall
    FROM public.vehicles v
    JOIN public.stalls s ON s.id = v.current_stall_id AND s.current_vehicle_id = v.id
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'staging')
SELECT p.st, count(*) AS parked,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_stall_bookings b, r
          WHERE b.sim_run_id = r.run AND b.stall_id = p.stall AND b.vehicle_id = p.id
            AND b.state IN ('held','active') AND b.during @> r.t)) AS on_the_calendar
  FROM p GROUP BY 1 ORDER BY 2 DESC;
-- BEFORE 0500 (394e1e83, 0368 §11(b)): at sim 10:37 AM 42 cars at the gate, all parked in staging, 4 on the calendar
--   (38 on a lapsed temp hold, a mean 54 minutes past its window); at 11:50 AM 35, 2 on the calendar.
-- PREDICTED under 0500: every parked car on the calendar, except one whose renewal would have overlapped another
--   booking on its stall (then closed as before, and named by §1(b)).

\echo '=== 0370 §1(b) — parking holds closed as overstays while their car was still parked, and renewals ==='
SELECT b.purpose, b.state, COALESCE(b.release_reason, '-') AS reason, count(*) AS holds,
       round(avg(EXTRACT(EPOCH FROM (upper(b.during) - lower(b.during))) / 60)) AS avg_minutes
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = :'run' AND s.stall_type::text = 'staging' AND b.purpose IN ('temp_hold','perimeter_hold')
 GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- PREDICTED under 0500: temp holds that ran as long as their car waited (averages well past 17 minutes), and few
--   `done / window_elapsed_occupied`: those are holds whose car left inside the last renewal, or whose renewal would
--   have overlapped another booking.

-- ══ §2 THE PROBE BEHIND 0500 (rolled back, old body then new) ═════════════════════════════════════════════════════
--
--   On the newest operator run (`394e1e83`, stopped at sim 16:52:11 UTC), at its clock, in one transaction that ends
--   in an exception. Three staging stalls are cleared and three parking holds planted, each `active` and each past its
--   window:
--     (a) car A parked on stall 1 by both pointers, its hold on stall 1 ended 25 minutes ago;
--     (b) car B parked on stall 2 by both pointers, its hold ended 25 minutes ago, and a third car holds stall 2 from
--         the clock on (`held`), so a renewal would overlap that hold;
--     (c) car B's older hold on stall 3, which it has left (neither pointer names it).
--   The closer, `ottoq.ottoq_release_expired_bookings(run, clock)`, runs on the old body, then 0500's patch is applied as
--   filed, then the closer runs on the new body. Run at 21:41 UTC (4:41 PM CT), a minute before the apply:
--     OLD  (a) done / window_elapsed_occupied, its window ending 16:27
--          (b) done / window_elapsed_occupied
--          (c) done / window_elapsed_occupied
--     NEW  (a) active, its window now ending 17:07 (the clock plus `staging_hold_renew_min`, 15)
--          (b) done / window_elapsed_occupied
--          (c) done / window_elapsed_occupied
--   So the old closer ended the hold of a car still parked on its stall. The new one keeps that hold for one more
--   renewal. It makes no renewal that would overlap another booking, and it still closes the hold of a car that has
--   left. (`window_elapsed_occupied` is the closer's name for an active booking that ran its full window. It does not
--   read either pointer, which is why it reads the same for (c).) The same three cases run inside 0500 as V3 and must
--   pass for it to apply.
--   0500 = 20260926214200 (4:42 PM CT), stored statement md5 56d2de1679e8960cb7b74d2b55702d69, equal to the file's
--   body; forces_recert TRUE (the closer runs in the certified tick, so bookings move on any arm where a car outstays
--   its parking hold).
--
--   The probe as run. The patch block between the two is 0500's `$patch$` verbatim, and the second probe is the first
--   with `$probe_new$` for `$probe_old$` and its last two lines (the `set_config` and the `END`) replaced as shown:
--   DO $probe_old$
--   DECLARE
--     v_run uuid; v_depot uuid; v_clk timestamptz; v_stall uuid; v_stall2 uuid; v_left uuid; v_car uuid; v_car2 uuid; v_out text;
--   BEGIN
--     SELECT r.sim_run_id, r.depot_id, r.sim_clock_current INTO v_run, v_depot, v_clk
--       FROM public.ottoq_sim_runs r
--      WHERE r.sim_clock_current IS NOT NULL AND r.depot_id IS NOT NULL AND r.validation_status IS NULL
--      ORDER BY r.started_at DESC LIMIT 1;
--     SELECT s.id INTO v_stall FROM public.stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection' ORDER BY s.id LIMIT 1;
--     SELECT s.id INTO v_stall2 FROM public.stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection' AND s.id <> v_stall
--      ORDER BY s.id LIMIT 1;
--     SELECT s.id INTO v_left FROM public.stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging' AND s.zone <> 'arrival_inspection'
--        AND s.id NOT IN (v_stall, v_stall2) ORDER BY s.id LIMIT 1;
--     SELECT v.id INTO v_car FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' ORDER BY v.id LIMIT 1;
--     SELECT v.id INTO v_car2 FROM public.vehicles v
--      WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id <> v_car ORDER BY v.id LIMIT 1;
--     BEGIN
--       DELETE FROM public.ottoq_stall_bookings b
--        WHERE b.sim_run_id = v_run AND (b.stall_id IN (v_stall, v_stall2, v_left) OR b.vehicle_id IN (v_car, v_car2));
--       UPDATE public.vehicles SET current_stall_id = NULL WHERE current_stall_id IN (v_stall, v_stall2, v_left);
--       UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL
--        WHERE id IN (v_stall, v_stall2, v_left) OR current_vehicle_id IN (v_car, v_car2);
--       UPDATE public.stalls SET current_vehicle_id = v_car WHERE id = v_stall;
--       UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = v_car;
--       UPDATE public.stalls SET current_vehicle_id = v_car2 WHERE id = v_stall2;
--       UPDATE public.vehicles SET current_stall_id = v_stall2 WHERE id = v_car2;
--       INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
--       VALUES (v_run, v_stall,  v_car,  'temp_hold', tstzrange(v_clk - interval '40 minutes', v_clk - interval '25 minutes', '[)'), 'active', 'otto_q'),
--              (v_run, v_stall2, v_car2, 'temp_hold', tstzrange(v_clk - interval '40 minutes', v_clk - interval '25 minutes', '[)'), 'active', 'otto_q'),
--              (v_run, v_left,   v_car2, 'temp_hold', tstzrange(v_clk - interval '60 minutes', v_clk - interval '45 minutes', '[)'), 'active', 'otto_q');
--       INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
--       SELECT v_run, v_stall2, v.id, 'temp_hold', tstzrange(v_clk, v_clk + interval '15 minutes', '[)'), 'held', 'otto_q'
--         FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.id NOT IN (v_car, v_car2)
--        ORDER BY v.id LIMIT 1;
--       PERFORM ottoq.ottoq_release_expired_bookings(v_run, v_clk);
--       SELECT format('parked car on %s: %s %s until %s | parked car whose renewal would overlap: %s %s | hold whose car left: %s %s',
--                     left(v_stall::text, 8), b1.state, COALESCE(b1.release_reason, '-'), to_char(upper(b1.during), 'HH24:MI'),
--                     b2.state, COALESCE(b2.release_reason, '-'), b3.state, COALESCE(b3.release_reason, '-'))
--         INTO v_out
--         FROM public.ottoq_stall_bookings b1, public.ottoq_stall_bookings b2, public.ottoq_stall_bookings b3
--        WHERE b1.sim_run_id = v_run AND b1.stall_id = v_stall AND b1.vehicle_id = v_car
--          AND b2.sim_run_id = v_run AND b2.stall_id = v_stall2 AND b2.vehicle_id = v_car2
--          AND b3.sim_run_id = v_run AND b3.stall_id = v_left AND b3.vehicle_id = v_car2;
--       RAISE EXCEPTION 'probe0500_pass_rolled_back';
--     EXCEPTION WHEN OTHERS THEN
--       IF SQLERRM <> 'probe0500_pass_rolled_back' THEN RAISE; END IF;
--     END;
--     PERFORM set_config('probe0500.old', format('run %s at %s (clock %s): %s', left(v_run::text, 8), v_clk, to_char(v_clk, 'HH24:MI'), v_out), true);
--   END $probe_old$;
--   -- $probe_new$ ends, after its inner block's END, with:
--     RAISE EXCEPTION E'PROBE0500\n OLD %\n NEW %', current_setting('probe0500.old'), v_out;
--   END $probe_new$;

-- ══ §3 THE CANON UNDER 0500 ════════════════════════════════════════════════════════════════════════════════════════
--
--   0500 forces recertification: the closer runs in the certified tick, so on any arm where a car outstays its parking
--   hold the renewal changes that booking's window, and with it the bookings digest. Which columns have such a car was
--   not predicted before the sweep. What must hold is that each column's two arms still agree.

\echo '=== 0370 §3 — the canon under 0500: each column''s verdict, and which of its arm A digests moved from 0499''s ==='
WITH v AS (
  SELECT l.verdict_id, l.scenario || '/' || l.seed || '/' || l.ticks AS col, l.outcome, l.disagreeing_atoms,
         l.verdict->'arm_a' AS a, l.certified_at
    FROM public.ottoq_determinism_verdict_ledger l
   WHERE l.verdict_id BETWEEN 411 AND 419 OR l.certified_at > '2026-09-26 21:42:00+00'),
k(key) AS (VALUES ('fp'),('boot'),('endst'),('ticks'),('h_bkg'),('h_cal'),('h_cmd'),('h_dec'),('h_defr'),('h_evt'),
                  ('h_nrg'),('h_prop'),('h_rcl'),('h_rule'),('h_sdr'))
SELECT n.col, o.verdict_id AS under_0499, n.verdict_id AS under_0500, n.outcome, n.disagreeing_atoms,
       COALESCE(array_agg(k.key ORDER BY k.key) FILTER (WHERE o.a->k.key IS DISTINCT FROM n.a->k.key), '{}') AS moved
  FROM v n
  JOIN v o ON o.col = n.col AND o.verdict_id BETWEEN 411 AND 419
  CROSS JOIN k
 WHERE n.verdict_id > 419
 GROUP BY n.col, o.verdict_id, n.verdict_id, n.outcome, n.disagreeing_atoms
 ORDER BY n.verdict_id;
-- READ (22:13 UTC, 5:13 PM CT): the canon re-certified 9 of 9 under 0500, each column on its first attempt:
--     grid_smoke/239001/6    411 -> 420  passed  moved {}
--     grid_smoke/424242/6    412 -> 421  passed  moved {endst,h_bkg}
--     busy_day/171717/12     413 -> 422  passed  moved {endst,h_bkg,h_evt}
--     busy_day/314159/12     414 -> 423  passed  moved {endst,h_bkg,h_evt}
--     busy_day/424242/12     415 -> 424  passed  moved {endst,h_bkg,h_evt}
--     normal_day/171717/12   416 -> 425  passed  moved {endst,h_bkg,h_evt}
--     busy_day/171717/24     417 -> 426  passed  moved {endst,h_bkg,h_dec,h_evt}
--     busy_day/424242/24     418 -> 427  passed  moved {endst,h_bkg,h_evt,h_rule}
--     busy_day/171717/48     419 -> 428  passed  moved {endst,h_bkg,h_dec,h_evt}
--   Verdicts 420-428, pairs started 21:43-22:03 UTC (4:43-5:03 PM CT; `certified_at` is the pair's transaction start),
--   the last ending at 22:12.
--   No column moved commands, SDRs, energy, proposals, deferrals, recalls or calibration. What did move, read arm A
--   against arm A of the verdict under 0499:
--   * bookings, and the end state, which hashes the run's bookings with their windows: the renewed parking holds.
--   * events: a waiting car leaves its staging stall and another car takes it in the same tick, and the stall's
--     reservation now passes from one car to the other in one write instead of two (busy_day/171717/12: 4
--     `stall.state_changed` rows fewer, at 4 staging stalls; everything else in the diff is ids minted per run). The
--     tick runs the decide step, then `ottoq_release_unusable_reservations`, then the closer. The reclaimer's orphan
--     class (the holder is in another stall and has no live booking on this one) used to clear the departing car's
--     reservation, because its lapsed hold was already closed. Now the renewed hold is still live when the reclaimer
--     runs, and the closer ends it later in the same tick. Its other two classes do not apply: the reservation expires
--     at the clock, not before it, and a car going to a charger is not an unusable holder.
--   * decisions, on busy_day/171717/24 (and on the 48-tick column, not broken down): two more `amend_plan` at 13:00,
--     the flow contract re-timing (by 1800 s) the
--     plans of two cars that waited in staging on a renewed hold. Their stage legs used to close `done` when the hold
--     lapsed. Now they stay `planned` while the car stays, and read as late (G234: stage legs done 12 -> 8 on that
--     column and 12 -> 7 on busy_day/424242/24, skipped up by the same).
--   * rule evaluations, on busy_day/424242/24: every rule evaluated as often as before. 6 SM.003 evaluations (stall
--     state changes) land on different staging stalls, because placements that issue no command chose different
--     staging stalls once renewed holds were on the calendar: b19025e6 at 13:00 and 9be45c35 at 13:30 took 95a5bfe9
--     instead of 3bfa7361, and b2222222 took 3621b5a6 at 13:30.
--   What 0500 leaves (G195's staging half): nothing ends a renewed hold when its car leaves. The reclaimer's skip above
--   is one sign of it. On operator runs, which tick every 30 sim-seconds, a stall a waiting car has just left stays held
--   for up to one renewal (15 minutes). 0372 §2(b) measures it live.
