-- migration-version: 20261020225005
-- migration-name:    a_car_held_at_its_charger_is_passed_over_by_the_bay_doors
--
-- 0761  **A car held at its charger is passed over by the bay doors.** (G479, G472)
--       Decide sections (4b) and (5) read cars waiting in staging and send them to their next bay. The twin stages a
--       robotic charger's car in the tick its charge stops, while the car is still on the charger, so both doors read
--       cars that something at the charger still holds. Two things can hold such a car:
--         - the fast charger's cleaning arm, at work in its cabin (0758);
--         - the charge arm, still unlatching or retracting.
--       0758's hold, ottoq.ottoq_uplink_transfer_holds, was taught to section (4), the service flow's wash admission and
--       the bay calendar, and to neither of these doors. So 0760 alone does not keep the car the arm is cleaning: the
--       stall is kept, but (4b) still takes the car. This file teaches the hold to both doors. Under a dial, it also has
--       them pass over a car the charge arm holds, and puts the refusal's message on the record.
--
-- ══ §1 WHY, MEASURED (read-only, live run c6ec017d, 2026-10-20 5:28-5:39 PM CT, 22:28:38-22:39:12 UTC) ═══════════════════
--
--   Run c6ec017d: busy_day at the twin depot with the seven switches of db/checks/0459 on, including stall_cabin_robot.
--   CORRECTION to 0760 §1 and G479: the door that took car ca2624fc was decide section (4b), not the bay calendar.
--   Its events and decision rows, all sim times CT:
--     - 9:44:08: the charge ended on NASH-DCFC-STALL-08. In that second the car went charging_dcfc ->
--       charge_complete_holding -> staged_awaiting_service, still on the stall. The cleaning arm was in its cabin (its tidy
--       ran 9:39:28-9:45:16).
--     - 9:44:17: (4b) asked ottoq.ottoq_enact_space_assignment to move it to a wash bay for its deep clean. The charge
--       arm's interlock refused, because the demate's tether ran to 9:44:19.63. Decision row: hold_no_space, reason
--       exception, P0001.
--     - 9:45:01: the tether sweep freed its stall (0760's case).
--     - 9:45:13: (4b) seated it in NASH-WSH-01 (booking 6846f5b5: booked_by otto_q_enacted, source needs_card, no leg).
--   With 0760 the stall is kept, but nothing else changes. The tether has expired, and public.ottoq_arm_interlock_guard
--   lets every move through once the tether is past the clock. (4b) reads no hold. So (4b) would still have seated the
--   car at 9:45:13, three seconds before the arm was home, and the tidy would still have been thrown away.
--   0760 has had no case to show since its apply. The four arm cleans after 4:37 PM CT each finished before their charge.
--
--   G472, on the same run. Between 4:05 and 5:35 PM CT the server log holds 12 "ottoq_enact_space_assignment: FAILED"
--   lines, and every one is the charge arm's interlock (demate/unlatch or demate/retract):
--     - 11 came from (4b): 8 for a wash bay and 3 for a service bay. For 8 of those 11 cars, the charge had ended in
--       that very tick.
--     - 1 came from (5), service sequencing.
--   Each decision row reads exception and P0001 and nothing else. ottoq_enact_space_assignment's catch-all returns the
--   SQLSTATE and drops the message, so a safety interlock doing its job is filed as an engine exception.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Always on. (4b)'s candidates and (5)'s cursor pass over a car that ottoq.ottoq_uplink_transfer_holds holds:
--       either the cleaning arm of the stall it stands on is at work in it (0758), or an unfinished data transfer holds
--       it on its uplink stall (0695). Section (4) already passes over these cars. The hold is false for every car until
--       a dial raises such work (stall_cabin_robot, twin_data_offload; both default 0), so nothing changes at the
--       defaults. The car is read again next tick, and once the arm's work is done the doors and the sweep (0760) take
--       it as before.
--   (b) The dial bay_walkin_waits_for_the_arm (0 or 1, default 0, not agent-writable). With it on, (4b) and (5) also pass
--       over a car the charge arm still holds, as section (4) does (0011-TETHER). The test is
--       public.ottoq_vehicle_is_tethered at the tick's clock, which is the interlock's own test: a tether that runs past
--       the run's sim clock. And ottoq.ottoq_enact_space_assignment's catch-all puts the refusal's message beside its
--       SQLSTATE on whatever it returns, for every caller, so a refusal that still happens says why on the record.
--   Rule 9: passing a car over moves its next work one tick later. It skips, shortens or defers nothing. The car cannot
--   move while it is held anyway: the charge arm's interlock refuses, and for the cleaning arm a move throws its work
--   away.
--   Not changed: the interlock, the hold, the tether test, the sweep, section (4), the bay calendar, the service flow,
--   and the assignment's choice, booking and success path. Not built: G472's other half, which seats the car in the
--   tick the arm lets go instead of the one after.
--   Two more movers read staged cars without the hold. twin.ottoq_opportunistic_scan moves a car only to a charger, for
--   an approved top-off, and a car the arm is cleaning has just reached its target. ottoq.ottoq_place_unplaced_vehicles
--   moves only a car with no stall, and the hold asks about the stall a car stands on. So neither is changed.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   - P0: nothing in flight.
--   - P1: not already applied; 0758 and 0760 are applied; the dial is nowhere yet. Five bodies are the ones read
--     (prosrc md5): the decide fc843b9e, the assignment 8334b01a, the hold dfd5d9d7, the tether test 306c42af and the
--     interlock ac1e1c70.
--   - The pre-images go to ottoq_schema_snapshots as '0761_pre'.
--   - Each anchor matches exactly once.
--   - V1: each body less its insertions is its pre-image.
--   - V2: the dial is catalogued as declared and no parameter row sets it.
--   - V3: each door's insertion is run, as written, on the live tables, over every car and with the dial both off and
--     on. A wrong name or type in it would otherwise surface only when the decide next ran, and fail every tick.
--   Executed by tests/test_held_car_is_passed_over_sql.py on the scratch PostgreSQL
--   (tests/fixtures/held_car_passed_over_stub.sql: the assignment, the hold, the tether test, the interlock and the dial
--   reader as live, md5 asserted):
--     - the doors' two insertions, taken from this file, over every kind of car: the cleaning arm at work on its stall,
--       on another stall, or done; a data transfer pending; a live tether and an expired one; another run's visit; no
--       work at all; each with the dial off and on;
--     - the assignment's patch, run from this file, at the default and with the dial;
--     - an interlock refusal before the patch, after it at 0, and after it at 1, which carries the message;
--     - the reservation rolled back on refusal;
--     - an unheld car seated as before.
--   The decide's patch is proven on its live body by V1 at apply, as 0747's was. The decide is not loaded on the
--   scratch server.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE, and forces_dial_restart FALSE. At the defaults, which are every certification arm's, no atom
--   carries the cleaning arm's performer or a needs_uplink key, so the hold is false for every car. The dial reads 0, so
--   (4b)'s and (5)'s candidates and the assignment's returns are exactly what they were (V1). The research wing's
--   robocabin pair (0758 §2(f)) has its treatment arm on stall_cabin_robot 1. It meets (a) whenever a charge ends during
--   an arm's clean, so when testing resumes (CLAUDE.md rule 12) read its arms from before and after this file apart.
--
-- ROLLBACK: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0761_pre';
--   DELETE FROM public.ottoq_policy_params WHERE param_key = 'bay_walkin_waits_for_the_arm';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_walkin_waits_for_the_arm';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0761_a_car_held_at_its_charger_is_passed_over_by_the_bay_doors'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0761 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied, 0758 and 0760 applied, the dial nowhere, the five bodies as read ──
DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0761_a_car_held_at_its_charger_is_passed_over_by_the_bay_doors') THEN
    RAISE EXCEPTION '0761 P1: already applied';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges',
                      '0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go')) <> 2 THEN
    RAISE EXCEPTION '0761 P1: 0758 and 0760 are not both applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_walkin_waits_for_the_arm')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'bay_walkin_waits_for_the_arm') THEN
    RAISE EXCEPTION '0761 P1: the dial bay_walkin_waits_for_the_arm already exists';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)', 'fc843b9e0d50ec33325ef32ac296759a'),
      ('ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text)',
       '8334b01ae1fe40a3c67da111b93faee4'),
      ('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 'dfd5d9d7b68066b2e933f5056bcaaceb'),
      ('public.ottoq_vehicle_is_tethered(uuid,timestamp with time zone)', '306c42afd9c974881402fdfc579ecf15'),
      ('public.ottoq_arm_interlock_guard()', 'ac1e1c702521e4b2e0708ebef513071c')) AS t(fn, md5) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0761 P1: % is not the body read (md5 %)', r.fn, left(r.md5, 8);
    END IF;
  END LOOP;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0761_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_decide_tick(uuid)'::regprocedure,
                 'ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text)'::regprocedure);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_walkin_waits_for_the_arm',
        '0761 (G472): 1 = decide sections (4b) and (5) pass over a car the charge arm still holds (its tether runs past '
        'the tick''s clock, the arm interlock''s own test), as section (4) does, instead of asking to move it and filing '
        'the interlock''s refusal as an exception; and ottoq.ottoq_enact_space_assignment puts a refusal''s message beside '
        'its SQLSTATE. 0 = as before 0761. The cleaning arm''s and a data transfer''s hold apply at both doors whatever '
        'this reads.',
        0, 0, 1, 'public.ottoq_decide_tick (4b) and (5); ottoq.ottoq_enact_space_assignment', false);

-- ── (b) decide sections (4b) and (5): a held car is passed over ──
CREATE TEMP TABLE _0761_decide (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0761_decide VALUES
  -- 1: (4b)'s candidates
  (1,
   $o1$             AND v.current_state = 'staged_awaiting_service'
             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
        )
$o1$,
   $n1$             AND v.current_state = 'staged_awaiting_service'
             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
             -- 0761 (G479): a car its stall's cleaning arm is at work in, or an unfinished data transfer holds on its
             -- uplink stall, is passed over, as section (4) passes it over (0695, 0758). The twin stages a robotic
             -- charger's car in the tick its charge stops, still on the charger. False for every car while no dial
             -- raises such work.
             AND NOT ottoq.ottoq_uplink_transfer_holds(pk.vehicle_id, p_sim_run_id)
             -- 0761 (G472): and with bay_walkin_waits_for_the_arm, a car the charge arm still holds (the interlock's
             -- own test), as section (4) passes it over (0011-TETHER). Asked to move it, the interlock refuses and the
             -- refusal is filed as an exception; the car is read again next tick, once the arm lets go.
             AND NOT (public.ottoq_policy_get(p_sim_run_id, 'bay_walkin_waits_for_the_arm', 0) >= 0.5
                      AND public.ottoq_vehicle_is_tethered(pk.vehicle_id, v_clock))
        )
$n1$),
  -- 2: (5)'s cursor
  (2,
   $o2$       AND v.current_state='staged_awaiting_service'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
$o2$,
   $n2$       AND v.current_state='staged_awaiting_service'
       -- 0761 (G479, G472): passed over while the cleaning arm or a data transfer holds the car, and with
       -- bay_walkin_waits_for_the_arm while the charge arm does, as in (4b) above.
       AND NOT ottoq.ottoq_uplink_transfer_holds(v.id, p_sim_run_id)
       AND NOT (public.ottoq_policy_get(p_sim_run_id, 'bay_walkin_waits_for_the_arm', 0) >= 0.5
                AND public.ottoq_vehicle_is_tethered(v.id, v_clock))
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
$n2$);

DO $patch_decide$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0761_decide ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0761: decide anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0761: the decide is not stored as patched';
  END IF;
END $patch_decide$;

-- ── (c) the assignment's catch-all: the refusal's message on the record ──
CREATE TEMP TABLE _0761_assign (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0761_assign VALUES
  (1,
   $o3$  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
$o3$,
   $n3$  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE)
         -- 0761 (G472): with bay_walkin_waits_for_the_arm, the refusal's message goes on the record beside its
         -- SQLSTATE. It reached only the server log before, so the arm interlock's refusal ("held by the arm at stall
         -- ... refusing to move it") read on the decision row as a bare P0001. The dial reader never raises.
         || CASE WHEN public.ottoq_policy_get(p_sim_run_id, 'bay_walkin_waits_for_the_arm', 0) >= 0.5
                 THEN jsonb_build_object('message', left(SQLERRM, 500)) ELSE '{}'::jsonb END;
$n3$);

DO $patch_assign$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text)'::regprocedure);
  FOR p IN SELECT * FROM _0761_assign ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0761: assignment anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0761: the assignment is not stored as patched';
  END IF;
END $patch_assign$;

-- ── V1: each body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0761_decide ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'fc843b9e0d50ec33325ef32ac296759a' THEN
    RAISE EXCEPTION '0761 V1: the decide less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid,text)'::regprocedure;
  FOR p IN SELECT * FROM _0761_assign ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '8334b01ae1fe40a3c67da111b93faee4' THEN
    RAISE EXCEPTION '0761 V1: the assignment less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the dial, as declared, and set nowhere ──
DO $v2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_walkin_waits_for_the_arm' AND default_value = 0 AND min_value = 0
                    AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'bay_walkin_waits_for_the_arm') THEN
    RAISE EXCEPTION '0761 V2: the dial is not catalogued as declared, or a parameter row sets it';
  END IF;
END $v2$;

-- ── V3: each door's insertion, as written, runs on the live tables over every car. Each anchor's new text is its old
--    text with the insertion placed before the anchor's last line, so the insertion is what lies between the two. It
--    runs as the WHERE of a query over every car, once as written (the dial reads 0 here, V2) and once with the dial's
--    read replaced by 1, so the charge arm's test runs too. Nothing is written. ──
DO $v3$
DECLARE p record; v_tail text; v_head text; v_ins text; v_run uuid; v_clock timestamptz; n int; v_pass text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  v_clock := COALESCE(v_clock, now());
  FOR p IN SELECT * FROM _0761_decide ORDER BY seq LOOP
    v_tail := reverse(split_part(reverse(rtrim(p.c_old, E'\n')), E'\n', 1)) || E'\n';   -- the anchor's last line
    v_head := left(p.c_old, length(p.c_old) - length(v_tail));
    v_ins := substr(p.c_new, length(v_head) + 1, length(p.c_new) - length(v_head) - length(v_tail));
    IF v_head || v_ins || v_tail IS DISTINCT FROM p.c_new THEN
      RAISE EXCEPTION '0761 V3: insertion % is not placed before its anchor''s last line', p.seq;
    END IF;
    FOREACH v_pass IN ARRAY ARRAY['as_written', 'dial_on'] LOOP
      EXECUTE format(
        'SELECT count(*) FROM (SELECT v.id, v.id AS vehicle_id FROM public.vehicles v) %s
           CROSS JOIN (SELECT %L::uuid AS p_sim_run_id, %L::timestamptz AS v_clock) z
          WHERE true %s',
        CASE p.seq WHEN 1 THEN 'pk' ELSE 'v' END, v_run, v_clock,
        CASE v_pass WHEN 'as_written' THEN v_ins
             ELSE replace(v_ins, $d$public.ottoq_policy_get(p_sim_run_id, 'bay_walkin_waits_for_the_arm', 0)$d$, '1') END)
        INTO n;
      IF n IS NULL THEN
        RAISE EXCEPTION '0761 V3: insertion % did not run (%)', p.seq, v_pass;
      END IF;
    END LOOP;
  END LOOP;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0761_a_car_held_at_its_charger_is_passed_over_by_the_bay_doors', false, false,
        'G479, G472. Decide sections (4b) and (5) pass over a car the cleaning arm or a data transfer holds '
        '(ottoq.ottoq_uplink_transfer_holds, as section (4) does), and under the dial bay_walkin_waits_for_the_arm a '
        'car the charge arm still holds; with the dial, ottoq.ottoq_enact_space_assignment''s catch-all returns the '
        'refusal''s message beside its SQLSTATE. Live run c6ec017d: (4b), not the bay calendar, seated ca2624fc in '
        'NASH-WSH-01 three seconds before its stall''s cleaning arm was home, and 12 of 12 exception refusals were the '
        'charge arm''s interlock. At the defaults no car is held and the dial reads 0 (V1).',
        now());

COMMIT;
