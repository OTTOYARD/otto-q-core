-- =====================================================================
-- 0181  The teardown recorded a return that never happened
-- =====================================================================
-- forces_recert = FALSE. Evidence for that classification is below, and
-- it is evidence, not caution.
--
-- WHAT WAS FOUND
-- ---------------------------------------------------------------------
-- Run cebe53e1 (grid fixture, sim window 2026-09-01 02:00 -> 05:00,
-- four dispatches). Its rows, read today:
--
--   trigger              scheduled_return_at    actual_return_at
--   wash_cadence         09-01 03:00:00         09-01 03:00:00   <- ok
--   surplus_to_demand    09-01 04:30:00         09-01 04:30:00   <- ok
--   overnight_prestage   09-01 05:30:00         09-03 21:55:54   <- ??
--   overnight_prestage   09-01 05:30:00         09-03 21:55:54   <- ??
--
-- 2026-09-03 21:55:54.346204 is not a sim clock. It is exactly
-- ottoq_sim_runs.started_at for that run - the transaction's now().
-- Both dispatches whose scheduled return fell PAST the run horizon
-- (05:30 > 05:00) were stamped with the wall clock and marked
-- 'completed'.
--
-- The writer is public.ottoq_sim_release_depot, the run finalizer:
--
--   UPDATE ottoq_vehicle_dispatches
--      SET status='completed',
--          actual_return_at = COALESCE(actual_return_at, now()),
--          return_trigger   = COALESCE(return_trigger, 'run_stopped')
--    WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');
--
-- TWO DEFECTS, AND THE FUNCTION ALREADY KNOWS BETTER
-- ---------------------------------------------------------------------
-- Six statements above it, the same finalizer closes itinerary legs and
-- gets both halves right:
--
--   UPDATE ottoq_itinerary_legs l
--      SET status = 'amended',                       <- NOT 'done'
--          actual_end_sim = COALESCE(l.actual_end_sim,
--            (SELECT COALESCE(r.sim_clock_current, now()) ...))   <- sim clock
--
-- with the comment: "it happened; it did not finish -- never 'done',
-- settlement is only for completed operations." The dispatch statement
-- violates both halves of its own neighbour's rule:
--
--   (a) THE STATUS LIE. A dispatch still 'active' when the run stopped
--       did not come home. Recording it 'completed' is a claim the run
--       has no evidence for. This is the horizon-artifact class -
--       0170 / 0172 / 0176 / 0178 - "a run may only be judged on what
--       it had time to do."
--
--   (b) THE WALL-CLOCK LEAK. now() is not the run's clock. The value
--       depends on WHEN THE RUN WAS EXECUTED, so it cannot regenerate
--       from a seed. Every other timestamp on the row is sim clock, and
--       every reader treats the column as sim clock.
--
-- twin.ottoq_sim_seed_fleet, doing the same job at the other end of the
-- run, already gets (a) right and says so in a comment - "superseded-run
-- leftovers never actually returned: abort, don't complete". The reseed
-- path was right and the teardown path was wrong. This migration makes
-- them agree.
--
-- WHY IT MATTERS: IT IS EATING A CANONICAL KPI
-- ---------------------------------------------------------------------
-- Of the five 2.9 KPIs, two read this column. Their behaviour differs
-- and both are wrong:
--
--   ottoq_kpi_asset_hours_available_per_day  (KPI 1) sums
--     COALESCE(actual_return_at, scheduled_return_at) - dispatched_at
--   with NO horizon gate. On cebe53e1 those two rows contribute
--   ~68.4 h each instead of ~4 h. A 3-hour sim window reports tens of
--   asset-hours, and the excess is a function of the calendar date the
--   run happened to execute on.
--
--   ottoq_kpi_p95_time_to_service  (KPI 5) gates
--     actual_return_at IS NOT NULL AND <= r.sim_clock_current
--   so the wall-clock rows silently VANISH from the denominator. Same
--   write, opposite failure.
--
-- Every other reader already gates on IS NOT NULL and most also bound to
-- the run window (workload_harness_metrics does it in eight places;
-- ottoq_score_run gates status='completed' AND actual_return_at IS NOT
-- NULL). Leaving the column NULL for a dispatch that never returned is
-- what all of them already expect. KPI 1 is the sole ungated reader and
-- is corrected separately in 0182 - a reader defect is not a writer
-- defect and they get separate lineage.
--
-- WHY THE DETERMINISM PAIR CANNOT SEE THIS, BY CONSTRUCTION
-- ---------------------------------------------------------------------
-- Worth stating plainly, because it is a limit of the instrument and not
-- of this defect alone. ottoq_determinism_pair runs BOTH arms in ONE
-- transaction. now() in Postgres is transaction start time. So arm A and
-- arm B are stamped with the IDENTICAL wall clock, and every hash that
-- covers the column agrees. A wall-clock leak inside the pair's own
-- transaction is invisible to the pair no matter which canon covers it.
-- Confirmed on the observed rows: cebe53e1 and 61af80b0 carry
-- started_at 2026-09-03 21:55:54.346204 to the microsecond - two arms,
-- one transaction. Only INTER-round comparison can catch this class.
--
-- WHY forces_recert = FALSE
-- ---------------------------------------------------------------------
-- Not an assumption. endst (ottoq_boot_state_fingerprint) DOES hash this
-- column: its `dp` CTE hashes whole dispatch rows for the run's own
-- vehicles, minus only dispatch_id / sim_run_id / created_at and the
-- correlation id. actual_return_at, status and return_trigger are all
-- inside that md5.
--
-- If the teardown write landed BEFORE endst was computed, endst would
-- carry a now() value and could not have reproduced across rounds hours
-- apart. Rounds 11 and 12 reproduced all four canons AND endst
-- byte-identically on all six columns. Therefore the teardown write
-- lands after the fingerprint, and moving it cannot move a canon.
--
-- PREDICTION, published before the round fires:
--   ALL SIX COLUMNS MUST REPRODUCE ROUND 12 EXACTLY. A moved hash is
--   0181's and is a defect to REVERT, not a canon to re-baseline.
--
-- Independently checkable after the round, and the point of the fix:
--   SELECT count(*) FROM ottoq_vehicle_dispatches
--    WHERE actual_return_at > (SELECT sim_clock_current FROM ottoq_sim_runs r
--                               WHERE r.sim_run_id = ottoq_vehicle_dispatches.sim_run_id);
--   must be 0 for every run created after this migration. It is 2 per
--   fixture pair arm today.
--
-- THE SECOND SITE: twin.ottoq_sim_seed_fleet, BOTH OVERLOADS
-- ---------------------------------------------------------------------
-- The reseed abort has the right status and the wrong clock, and one
-- more problem 0066 section 5 named and this closes:
--
--   UPDATE ottoq_vehicle_dispatches d ... FROM vehicles v
--    WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
--      AND d.status IN ('active','returning');
--
-- No sim-domain guard. The adjacent ocpp_sessions reset in the same
-- function is twin-only by token convention (id_token LIKE 'TWIN-%');
-- this one is not, so it would abort a PRODUCTION dispatch - a row with
-- sim_run_id IS NULL - for any vehicle homed at the depot.
--
-- Measured exposure TODAY: ottoq_vehicle_dispatches holds 66,754 rows,
-- of which 0 have sim_run_id IS NULL. There is no production dispatch in
-- the table, so the mechanism is real and its blast radius is currently
-- empty - the same standing as 0066 section 4, not a live defect. It is
-- fixed now because the vehicle and asset feeds that will write those
-- rows are the next thing to land, and a guard added before the first
-- real row is a guard; added after, it is an incident report.
-- =====================================================================

DO $do$
DECLARE
  v_src text; v_n int; v_p record;
  -- ---- site 1: the run finalizer -----------------------------------
  v_rel_anchor CONSTANT text :=
'  UPDATE ottoq_vehicle_dispatches
     SET status=''completed'',
         actual_return_at = COALESCE(actual_return_at, now()),
         return_trigger   = COALESCE(return_trigger, ''run_stopped'')
   WHERE sim_run_id = p_sim_run_id AND status IN (''active'',''returning'');';
  v_rel_fixed CONSTANT text :=
'  /* 0181: a dispatch still out when the run stopped did NOT come home.
     Same rule the leg close above already follows - it happened, it did
     not finish, so it is never recorded as the thing that finishes.
     status ''aborted'' is the table''s own non-completed terminal and is
     what twin.ottoq_sim_seed_fleet already uses for exactly this case.
     actual_return_at is left ALONE: previously now() was coalesced in,
     which is (a) not the run''s clock, so the row could not regenerate
     from a seed, and (b) a return the run never observed. NULL is the
     honest value and is what every reader but ottoq_kpi_asset_hours_
     available_per_day already gates on. return_trigger still names the
     cause. Horizon-artifact class: 0170 / 0172 / 0176 / 0178. */
  UPDATE ottoq_vehicle_dispatches
     SET status=''aborted'',
         return_trigger   = COALESCE(return_trigger, ''run_stopped'')
   WHERE sim_run_id = p_sim_run_id AND status IN (''active'',''returning'');';
  -- ---- site 2: the reseed abort, both overloads ---------------------
  v_seed_anchor CONSTANT text :=
'  UPDATE ottoq_vehicle_dispatches d
     SET status = ''aborted'',
         actual_return_at = COALESCE(actual_return_at, NOW()),
         return_trigger = COALESCE(return_trigger, ''run_reseed_abort'')
    FROM vehicles v
   WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
     AND d.status IN (''active'',''returning'');';
  v_seed_fixed CONSTANT text :=
'  /* 0181: two corrections to a statement whose STATUS was always right.
     (1) sim-domain guard. 0066 section 5: this had no twin guard while
     the ocpp reset beside it is twin-only by token convention, so a
     depot reseed would abort a PRODUCTION dispatch (sim_run_id IS NULL)
     for any vehicle homed here. 0 such rows exist today, so this is a
     guard placed before the exposure, not after it.
     (2) actual_return_at left alone - NOW() is a wall clock on a column
     every reader treats as sim clock, and an aborted dispatch has no
     return to timestamp. */
  UPDATE ottoq_vehicle_dispatches d
     SET status = ''aborted'',
         return_trigger = COALESCE(return_trigger, ''run_reseed_abort'')
    FROM vehicles v
   WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
     AND d.sim_run_id IS NOT NULL
     AND d.status IN (''active'',''returning'');';
BEGIN
  -- ═══════ site 1 ═══════
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  IF v_src IS NULL THEN RAISE EXCEPTION '0181: ottoq_sim_release_depot not found'; END IF;

  IF position('0181: a dispatch still out' in v_src) > 0 THEN
    RAISE NOTICE '0181: release_depot already applied';
  ELSE
    v_n := (length(v_src) - length(replace(v_src, v_rel_anchor, ''))) / length(v_rel_anchor);
    IF v_n <> 1 THEN RAISE EXCEPTION '0181: release_depot anchor occurs % times, expected 1', v_n; END IF;
    EXECUTE replace(v_src, v_rel_anchor, v_rel_fixed);
    RAISE NOTICE '0181: run finalizer no longer records a return it did not observe';
  END IF;

  -- ═══════ site 2: every overload ═══════
  FOR v_p IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='twin' AND p.proname='ottoq_sim_seed_fleet'
     ORDER BY 2
  LOOP
    v_src := pg_get_functiondef(v_p.oid);
    IF position('0181: two corrections' in v_src) > 0 THEN
      RAISE NOTICE '0181: seed_fleet(%) already applied', v_p.args;
      CONTINUE;
    END IF;
    v_n := (length(v_src) - length(replace(v_src, v_seed_anchor, ''))) / length(v_seed_anchor);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0181: seed_fleet(%) anchor occurs % times, expected 1', v_p.args, v_n;
    END IF;
    EXECUTE replace(v_src, v_seed_anchor, v_seed_fixed);
    RAISE NOTICE '0181: seed_fleet(%) scoped to the sim domain, clock leak removed', v_p.args;
  END LOOP;

  -- ═══════ both overloads must have been reached ═══════
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_seed_fleet'
     AND position('0181: two corrections' in pg_get_functiondef(p.oid)) > 0;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0181: % of 2 seed_fleet overloads carry the fix', v_n;
  END IF;
END
$do$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_teardown_recorded_a_return_that_never_happened', false,
        'public.ottoq_sim_release_depot marked every dispatch still active/returning at teardown status=completed with actual_return_at=COALESCE(actual_return_at, now()). Two defects: a status the run has no evidence for (horizon-artifact class 0170/0172/0176/0178) and a wall clock on a column every reader treats as sim clock. Measured on run cebe53e1: a 3-hour sim window (02:00-05:00) produced two dispatches stamped 2026-09-03 21:55:54.346204, exactly ottoq_sim_runs.started_at. ottoq_kpi_asset_hours_available_per_day (KPI 1) has no horizon gate and booked ~68.4 h per affected dispatch instead of ~4 h, an error that is a function of the calendar date the run executed on; ottoq_kpi_p95_time_to_service (KPI 5) gates <= sim_clock_current and silently dropped the same rows. The finalizer already closes itinerary legs correctly six statements above (status amended, never done; actual_end_sim from sim_clock_current) and twin.ottoq_sim_seed_fleet already uses status aborted for the same case, so the fix makes the teardown agree with its own neighbours: status aborted, actual_return_at left NULL, return_trigger kept. Same migration closes 0066 section 5 at both seed_fleet overloads - the reseed abort had no sim-domain guard and would have aborted a production dispatch (sim_run_id IS NULL); 0 of 66754 rows are production today, so this is a guard placed before the exposure the vehicle and asset feeds will create, not after it. forces_recert=false on evidence: endst hashes this column (boot_state_fingerprint dp CTE hashes whole dispatch rows) yet reproduced byte-identically across rounds 11 and 12 hours apart, which is only possible if the teardown write lands after the fingerprint. Prediction published before the round: all six columns must reproduce round 12 exactly. Also documented: ottoq_determinism_pair runs both arms in ONE transaction, so now() is identical across arms and a wall-clock leak inside that transaction is invisible to the pair by construction, whatever canon covers it - only inter-round comparison can catch this class.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
