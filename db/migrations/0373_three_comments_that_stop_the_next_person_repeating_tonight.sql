-- migration-version: 20260920050351
-- ════════════════════════════════════════════════════════════════════════════
-- 0373  THREE COMMENTS THAT STOP THE NEXT PERSON REPEATING TONIGHT.
--
--       forces_recert FALSE — it changes no executable code. `prosrc` is
--       untouched for all three functions, so no engine or config hash moves.
-- ════════════════════════════════════════════════════════════════════════════
--
-- `scripts/coverage-guard.sql` (written tonight) now reports fifteen routines that
-- exist and have no live caller. Three of those rows are **correct and expected**,
-- and each one is a trap for whoever reads the list next:
--
--   * `public.ottoq_gc_stale_reservations` — G77's routine. Its clock defect was
--     fixed by 0360, so the warning in its own comment ("this would have cleared all
--     156") no longer applies, and someone reading that comment could reasonably
--     conclude it is now safe to schedule. It is safe AND redundant: 0367, 0369 and
--     0371 replaced what it was for, with three release classes, a production guard,
--     a calendar-backed exemption and an alarm it does not have. Scheduling it would
--     duplicate the reclaimer on a narrower predicate.
--   * `twin.ottoq_report_charger_fault` — zero callers anywhere, and that is right:
--     its `p_actor` defaults to `'depot_tech'` and `scenarios/mid_session_charger_fault.json`
--     lists it as one of three manual fault-injection forms. It is an OPERATOR entry
--     point. It has no comment at all today.
--   * `ottoq.ottoq_replan_after_charger_fault` — the only placement routine besides
--     `ottoq_l2_optimize_assignments` that checked charger health before 0372, and
--     reachable only from the operator path above, which is why the twin's own 18
--     charger faults on run `5b37ee46` never reached it (G88, `db/checks/0264`).
--
-- A comment is the cheapest possible fix for a list that will be read again, and the
-- alternative — deleting or scheduling any of the three — would be wrong in all
-- three cases.

-- ══ P0. ALL THREE EXIST WITH THE SIGNATURES THIS FILE NAMES ══════════════════
DO $p0$
DECLARE v_missing text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='ottoq_gc_stale_reservations'
                    AND pg_get_function_identity_arguments(p.oid) = '')
  THEN v_missing := v_missing || 'ottoq_gc_stale_reservations() '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='twin' AND p.proname='ottoq_report_charger_fault'
                    AND pg_get_function_identity_arguments(p.oid)
                        = 'p_charger_id uuid, p_actor text, p_fault_code text, p_note text')
  THEN v_missing := v_missing || 'twin.ottoq_report_charger_fault(4 args) '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='ottoq' AND p.proname='ottoq_replan_after_charger_fault')
  THEN v_missing := v_missing || 'ottoq_replan_after_charger_fault '; END IF;
  IF v_missing <> '' THEN
    RAISE EXCEPTION 'P0: signature mismatch, refusing to comment on something else: %', v_missing;
  END IF;
  --: and the claim the comments rest on: none of the three is on the live path
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.active
              AND (position('ottoq_gc_stale_reservations' in j.command) > 0
                OR position('ottoq_report_charger_fault' in j.command) > 0)) THEN
    RAISE EXCEPTION 'P0: one of these IS scheduled; the comments would be wrong';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ THE COMMENTS ════════════════════════════════════════════════════════════

COMMENT ON FUNCTION public.ottoq_gc_stale_reservations() IS
'SUPERSEDED — DO NOT SCHEDULE. Clears stall reservations that are expired or '
'orphaned. 0360 fixed G77: the expiry arm compared reservation_expires_at -- a '
'SIM-clock column -- against now(), which is WALL. Measured on run f14d5620, wall ran '
'4h46m ahead of the sim clock, so of 156 reserved stalls 127 were live against sim and '
'0 against wall: this function would have cleared ALL 156. That defect is fixed, so '
'the danger is gone -- and 0373 records that the ROUTINE is now redundant rather than '
'merely safe. public.ottoq_release_unusable_reservations (0367 / 0369 / 0371) replaced '
'it: three release classes (unusable holder, sim expiry, unbacked orphan), a '
'production guard, an exemption for calendar-backed forward plans, first-true buckets '
'that sum to released, and an ottoq.reservation_reclaim_blocked alarm -- none of which '
'this function has. It is called from ottoq_sim_decide_and_dispatch above the policy '
'branch, so every arm of an A/B gets the same world. Scheduling THIS function would '
'duplicate that on a narrower predicate. Kept, not dropped, because nothing in this '
'repo is deleted (C4 step 5).';

COMMENT ON FUNCTION twin.ottoq_report_charger_fault(uuid, text, text, text) IS
'OPERATOR ENTRY POINT — no in-database caller BY DESIGN, and coverage-guard.sql will '
'list it forever. p_actor defaults to depot_tech: this models a HUMAN confirming a '
'charger fault, and scenarios/mid_session_charger_fault.json names it as one of three '
'live fault-injection forms alongside the cert arm''s fault_chargers=N and '
'otto-twin-control POST inject_fault. It records the world fact and delegates the '
'decision to ottoq.ottoq_replan_after_charger_fault, which is the right split. '
'CONSEQUENCE WORTH KNOWING (G88, db/checks/0264): the twin''s OWN charger faults do '
'not come through here -- they are written by ottoq_sim_advance_tick_world and '
'twin.ottoq_sim_stop_charge_session -- so the charger-aware replan below never ran for '
'the 18 faults on run 5b37ee46. 0372 closed the resulting exposure by making '
'ottoq_stall_free_between charger-aware for every caller.';

COMMENT ON FUNCTION ottoq.ottoq_replan_after_charger_fault(uuid, uuid, uuid, text, uuid, text, timestamptz) IS
'OTTO-Q decision half of the charger-fault path: where does a displaced vehicle go. '
'Extracted from ottoq_report_charger_fault so the twin keeps only the world fact. '
'REACHABLE ONLY FROM THAT OPERATOR ENTRY POINT (0373) -- so it does not run for the '
'twin''s own charger faults, which is G88. Until 0372 it was one of only two placement '
'routines that checked c2.station_state = ''Available'' before offering a stall; the '
'other is ottoq_l2_optimize_assignments. It also goes through '
'ottoq_indepot_reassignment_guard and falls back to temp-staging so a displaced '
'vehicle is never stranded, which the generic stranded-undercharge sweep does not do. '
'If the fault path is ever wired to the twin''s own faults, THIS is the routine to '
'wire it to.';

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE (n.nspname, p.proname) IN (('public','ottoq_gc_stale_reservations'),
                                    ('twin','ottoq_report_charger_fault'),
                                    ('ottoq','ottoq_replan_after_charger_fault'))
     AND obj_description(p.oid, 'pg_proc') IS NOT NULL
     AND (position('SUPERSEDED'            in obj_description(p.oid,'pg_proc')) > 0
       OR position('OPERATOR ENTRY POINT'  in obj_description(p.oid,'pg_proc')) > 0
       OR position('REACHABLE ONLY'        in obj_description(p.oid,'pg_proc')) > 0);
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'P9: expected 3 commented functions, found %', v_n;
  END IF;
  RAISE NOTICE 'P9 ok: three comments in place, no executable code touched';
END $p9$;
