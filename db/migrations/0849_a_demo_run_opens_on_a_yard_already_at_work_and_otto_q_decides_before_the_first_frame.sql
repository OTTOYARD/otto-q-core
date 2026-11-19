-- migration-version: PENDING
-- migration-name:    0849_a_demo_run_opens_on_a_yard_already_at_work_and_otto_q_decides_before_the_first_frame
--
-- 0849  **A demo run opens on a yard already at work, and OTTO-Q decides before the first frame.**
--
-- WHY. Chase, 2026-11-18 (evening CT): "Should new run start with vehicles in place and then 'go' after several ticks?
-- Or take longer to plan upon start, but then renders with vehicles randomly throughout the yard at various stages,
-- etc?" The recommendation (docs/RUN_START.md, PR 289): the second, each car where its state says it is, chargers and
-- bays part-way through their work. Chase, 2026-11-19 (about 12:20 AM CT): "Yes, I want the run start as recommended.
-- Test first to make sure it functions correctly. And I don't mind if it takes longer to spin up the rendering when you
-- start a run if it requires a bit more time to to get everything ordered from a simulation standpoint. Just make sure
-- Otto-q begins solving and orchestrating immediately as soon as the world variables are selected and the twin
-- rendering loads."
--
-- §1 WHAT A RUN DID (run 368e1472, the last run, started 12:40 PM CT on 2026-11-18; read 2026-11-19 UTC).
--   - The start dealt every car a state and NO stall (twin.ottoq_sim_seed_fleet sets current_stall_id NULL and frees
--     every stall). 97 of 116 cars stood on the site with no stall in the twin's own record, so the renderer parked
--     each itself (TwinMotionDriver ledger.claimFirstFree): the renderer deciding world state.
--   - Nothing ticked until the next minute's metronome firing: public.ottoq_demo_metronome returns at once when no run
--     is live, so a run started between firings waits for the next one (started 18:40:49, first tick 18:41:00, up to
--     60 s). OTTO-Q's first decision came on the metronome's second tick (it decides on odd ticks), 14 s after start.
--   - That decision took the whole yard at once: 30 begin_charge, 3 enter_wash, 8 proceed_to_stall and 68 staging
--     holds in one tick (ottoq_vehicle_commands and ottoq_stall_bookings, booked at sim 14:02:13). The twin carried the
--     commands out on the next world tick: 30 cars left staging together for the 30 fast-charger posts, and every arm
--     mated at once.
--   - 43 of the 72 cars dealt 'staged_for_departure' went to awaiting service in that tick: the start writes a state
--     before the needs card has read the car (100% targets, 0539; due services).
--
-- §2 WHAT THIS DOES. Behind a new dial boot_mid_shift (default 0; 1 at the twin depot under Chase's decision above),
--   for runs started by an operator (run_by 'operator_demo': the twin app's Start, ottoq_start_demo_run):
--   (a) OTTO-Q DECIDES AT THE START CLOCK, before the yard is drawn: public.ottoq_boot_mid_shift runs the decide path
--       (public.ottoq_sim_decide_and_dispatch, OTTO-Q's own tick, unchanged) on the start's world, then OTTO-Q's own
--       placement (ottoq.ottoq_place_unplaced_vehicles, cap 200 instead of the tick's 60) so no car on the site is left
--       without a place it holds. Before the agentic arm, so this first decision holds no car for a proposer.
--   (b) THE TWIN CARRIES IT OUT AT ONCE, WITH THE WORK ALREADY UNDER WAY (twin.ottoq_sim_boot_head_start):
--       - OTTO-Q's commands are walked by the twin's own door (twin.ottoq_sim_confirm_commands, or the operator step
--         when twin_operator_door is on), at the start clock: cars stand where OTTO-Q put them; none drives there.
--       - each charge OTTO-Q started opens through the twin's own door (twin.ottoq_sim_start_charge_session) at a clock
--         a drawn head start before the start, and is played forward to the start by the twin's own arm and charge
--         steps (twin.ottoq_arm_advance_cycles, twin.ottoq_sim_advance_charge_sessions) in 2-minute steps. The head
--         start is drawn per car (seed, salt 'boot_head:'), at least 1 minute (the arm has latched) and at most 80% of
--         the charge's estimated minutes and boot_head_start_cap_min (default 30), so charges end one by one after the
--         start, not together.
--       - each bay seat OTTO-Q started is moved back by a drawn head start (salt 'boot_bay_head:'), at most 80% of its
--         own duration: its start (last_state_change, the snapshot's bay_seat.since) and its end (service_ends_at and
--         bay_need.ends_at, written together as the bay door writes them) move by the same amount, so the seat keeps
--         its full duration.
--   (c) THE FIRST TICK COMES AT ONCE. last_tick_at and next_tick_due_at are set as the boot ends; and with a new
--       global dial metronome_idle_poll (default 0; 1, same decision) the metronome no longer returns when nothing is
--       live: it looks again every half second until its budget is spent, committing before each sleep. A run started
--       between firings gets its first tick within about a second.
--   (d) LIVE PLAYBACK FROM THE FIRST INSTANT, for every operator start (not behind the dial): the payload gets
--       playback_mode 'live' and speed_x 1 if it has none. Both demo doors set live playback right after the start
--       returns (otto-twin-control's ottoq_set_playback, ottoq_start_demo_run); with (c) a tick can come before they
--       do, and in the payload's absence it would be a fixed-mode tick of tick_interval_seconds x time_scale, 30
--       sim-minutes on busy_day.
--
-- §3 THE RULES, CHECKED.
--   THE LAW. OTTO-Q decides every placement (its own decide path and placement function, unchanged). The twin only
--     carries the decisions out and owns the timing of work in the world, through its own doors. The renderer decides
--     nothing: every car it draws on the site has a stall in the twin's record at the first frame.
--   RULE 9. No charge is shortened: every session runs to the car's target (100%, 0539) from the moment it opened, and
--     the twin's charge step meters every minute of the head start. No service is shortened: a bay seat keeps its full
--     duration. A head start only says the work began before the run's clock did.
--   RULE 14. The first decision is the kernel's own neutral order. The head starts are drawn per car from the seed and
--     read no owner.
--   RULES 10 AND 12. Both dials switched on at the twin depot (the metronome's globally) under Chase's decision, and
--     checked here at apply (V3) and on one demo run after it (db/checks/0499). No pair, no sweep.
--
-- §4 WHAT THIS DOES NOT DO.
--   - The research wing's starts ('ab_harness': dial pairs, sweep arms) keep the old start; the certification and A/B
--     pairs start through twin.ottoq_sim_start_run and never reach this code. Moving them is the research wing's call.
--   - A charge's head start is metered on its session (energy_delivered_kwh) and not on the site meter, which starts at
--     the run's first tick. A run's site energy and peak readings begin at its start, as before.
--   - The start takes longer: about 2 s before, plus OTTO-Q's first decision (about 6.5 s on 368e1472's world) and the
--     head start. A start reached through the API runs under service_role's 20 s statement_timeout, so the boot step
--     skips itself (and says so on the run) when less than 12 s of that budget is left before it, and skips the head
--     start when less than 4 s is left after the decision.
--   - Gate arrivals: the seed's 'arrived_at_gate' cars are part of the start's world, and OTTO-Q seats some of them at
--     once. Cars still coming home arrive through the gate as before.
--
-- §5 PRECONDITIONS AND CHECKS. P0 nothing in flight, no run live (V3 starts a run). P1 the two bodies this file was
--   written against: md5(prosrc) public.ottoq_sim_run_scenario 7757325f1f616cee4a9dc3e145769837, public.ottoq_demo_metronome
--   38bd9fe4e6c09f0047ad608dc55c764a, and the doors it calls, as read 2026-11-19. P2 once. V1 each patched body with its
--   patch reversed is its pre-image. V2 each anchor matched once. V3 a real operator start of busy_day at the twin depot
--   with boot_mid_shift on, inside a block that is rolled back: the boot step ran; every car on the site but the gate's
--   holds a stall; OTTO-Q decided at the start clock; every charge opened before the start clock and none after it, at
--   the car's own target; every bay seat began before the start clock and ends after it; the run is in live playback.
--
-- §6 CLASSIFICATION. forces_recert FALSE: the certification and A/B pairs start through twin.ottoq_sim_start_run, which
--   this does not touch, and tick themselves, so the metronome change never reaches them. forces_dial_restart FALSE:
--   dial pairs and sweep arms start as 'ab_harness', outside the run_by gate, and are not metronome-driven while they run
--   in one transaction.
--
-- ROLLBACK: EXECUTE the `definition` of each row in ottoq_schema_snapshots WHERE label = '0849_pre'; DELETE FROM
--   ottoq_policy_params and ottoq_policy_param_catalog WHERE param_key IN ('boot_mid_shift', 'boot_head_start_cap_min',
--   'metronome_idle_poll'); the two new functions may stay (nothing calls them once the start is restored); DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0849_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0849 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0849 P0: a run is live. V3 starts a run at the twin depot, so apply between runs';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure)
       IS DISTINCT FROM '7757325f1f616cee4a9dc3e145769837' THEN
    RAISE EXCEPTION '0849 P1: public.ottoq_sim_run_scenario is not the body this file was written against';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_demo_metronome(integer)'::regprocedure)
       IS DISTINCT FROM '38bd9fe4e6c09f0047ad608dc55c764a' THEN
    RAISE EXCEPTION '0849 P1: public.ottoq_demo_metronome is not the body this file was written against';
  END IF;
  -- the doors the boot step calls, as read when it was written (their behaviour is what §2 relies on)
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure)
       IS DISTINCT FROM '7e0df6a857a19ef3b715a596e8a6d99e'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure)
       IS DISTINCT FROM 'f0b580e47658a7f51a62663095e07157'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure)
       IS DISTINCT FROM 'f5e511c6706a55ae8ccf556c982390f6'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamptz)'::regprocedure)
       IS DISTINCT FROM '405225263102691eeefdfa045170674a'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_arm_advance_cycles(uuid,timestamptz)'::regprocedure)
       IS DISTINCT FROM '4f216cbe1dbe089589245210f1397d1f' THEN
    RAISE EXCEPTION '0849 P1: a door the boot step calls is not the body this file was read against';
  END IF;
  IF to_regprocedure('ottoq.ottoq_place_unplaced_vehicles(uuid,uuid,timestamptz,integer)') IS NULL
     OR to_regprocedure('twin.ottoq_twin_operator_step(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_release_expired_tethers(timestamptz)') IS NULL
     OR to_regprocedure('public.ottoq_estimate_charge_minutes(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_try_timestamptz(text)') IS NULL THEN
    RAISE EXCEPTION '0849 P1: a function the boot step calls is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0849_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('boot_mid_shift', 'boot_head_start_cap_min', 'metronome_idle_poll'))
     OR to_regprocedure('public.ottoq_boot_mid_shift(uuid)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_sim_boot_head_start(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0849 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0849_pre', CASE WHEN p.prokind = 'p' THEN 'procedure' ELSE 'function' END, n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure,
                 'public.ottoq_demo_metronome(integer)'::regprocedure);

-- ── the dials ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('boot_mid_shift',
   '0849: 1 = a run started by an operator (run_by operator_demo) opens on a yard already at work: OTTO-Q decides at '
   'the start clock and places every car on the site, and the twin carries the decisions out at once, each charge and '
   'bay seat already under way by a drawn head start. 0 = the start deals states with no stall and OTTO-Q first '
   'decides on the metronome''s second tick.',
   0, 0, 1, 'public.ottoq_sim_run_scenario, public.ottoq_boot_mid_shift, twin.ottoq_sim_boot_head_start', false),
  ('boot_head_start_cap_min',
   '0849: the longest head start a charge may have at a mid-shift start, in sim-minutes. A charge''s head start is '
   'drawn per car up to the smaller of this and 80% of its estimated minutes, at least 1 minute.',
   30, 0, 120, 'twin.ottoq_sim_boot_head_start', false),
  ('metronome_idle_poll',
   '0849: 1 = with no run live the demo metronome looks again every half second until its budget is spent, so a run '
   'started between two firings gets its first tick within about a second. 0 = it returns at once and a new run waits '
   'for the next minute''s firing. Read at global scope.',
   0, 0, 1, 'public.ottoq_demo_metronome', false);

-- ── the twin's half: carry OTTO-Q's first decisions out at once, with the work already under way ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_boot_head_start(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
-- 0849. Called once, at a mid-shift start, after OTTO-Q has decided at the start clock (public.ottoq_boot_mid_shift).
-- Decides nothing: it walks OTTO-Q's commands through the twin's own door, and gives the work they started a head start
-- through the twin's own charge, arm and bay timing. Every draw is a pure function of the run's seed and the car.
DECLARE
  v_run        public.ottoq_sim_runs%ROWTYPE;
  v_t          timestamptz;
  v_seed       bigint;
  v_cap        numeric;
  v_step       constant interval := interval '2 minutes';
  v_door       boolean;
  v_walked     int := 0;
  v_door_out   jsonb;
  r            record;
  v_rate_mult  numeric;
  v_est        numeric;
  v_h          numeric;
  v_sess       uuid;
  v_opened     int := 0;
  v_not_opened int := 0;
  v_heads      numeric[] := '{}';
  v_tick       timestamptz;
  v_steps      int := 0;
  v_completed  int := 0;
  v_faulted    int := 0;
  v_c          int;
  v_f          int;
  v_bays       int := 0;
  v_bay_heads  numeric[] := '{}';
  v_dur        numeric;
  v_end        timestamptz;
  v_unplaced   int := 0;
BEGIN
  SELECT * INTO v_run FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found');
  END IF;
  v_t    := COALESCE(v_run.sim_clock_current, v_run.sim_clock_start);
  v_seed := COALESCE(v_run.random_seed, 42);
  v_cap  := GREATEST(0, COALESCE(public.ottoq_policy_get(p_sim_run_id, 'boot_head_start_cap_min', 30), 30));

  -- 1. OTTO-Q's commands, walked now: the cars stand where it put them, and none drives there
  v_door := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0), 0) >= 1;
  IF v_door THEN
    v_door_out := twin.ottoq_twin_operator_step(p_sim_run_id);
  ELSE
    v_walked := COALESCE(twin.ottoq_sim_confirm_commands(p_sim_run_id, v_t), 0);
  END IF;

  -- 2. every charge OTTO-Q started is already under way: opened at a drawn head start before the start clock
  v_rate_mult := GREATEST(0.2, COALESCE(public.ottoq_profile_rate_mult(p_sim_run_id, 'charge_time'), 1.0));
  FOR r IN
    SELECT v.id AS vid, v.current_stall_id AS sid, v.current_soc AS soc,
           COALESCE(v.target_soc, public.ottoq_default_target_soc()) AS tsoc,
           v.inlet_max_kw, v.battery_capacity_kwh AS pack_kwh,
           COALESCE((v.config->>'battery_soh_pct')::numeric, 95) AS soh,
           ch.max_kw AS charger_kw
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.current_stall_id
      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
       AND v.current_state IN ('charging_dcfc', 'charging_l2')
       AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions cs
                        WHERE cs.vehicle_id = v.id AND cs.status = 'active' AND cs.id_token LIKE 'TWIN-%')
     ORDER BY v.id
  LOOP
    v_est := COALESCE(public.ottoq_estimate_charge_minutes(r.soc, r.tsoc, r.charger_kw, r.inlet_max_kw, r.pack_kwh,
                                                            30, r.soh, v_rate_mult), 0);
    v_h := LEAST(v_cap, 0.8 * v_est) * twin.ottoq_sim_seeded_random(v_seed, 'boot_head:' || r.vid::text);
    v_h := round(GREATEST(LEAST(1, 0.5 * v_est), v_h), 1);
    BEGIN
      -- the clock this charge opens at is the clock its events carry (ottoq.ottoq_run_now() reads it)
      PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|'
                         || (v_t - make_interval(secs => (v_h * 60)::double precision))::text, true);
      v_sess := twin.ottoq_sim_start_charge_session(r.vid, r.sid, p_sim_run_id, r.tsoc,
                                                    v_t - make_interval(secs => (v_h * 60)::double precision));
      IF v_sess IS NULL THEN
        v_not_opened := v_not_opened + 1;   -- refused by the shield at charge_session_start; the first tick retries
      ELSE
        v_opened := v_opened + 1;
        v_heads  := v_heads || v_h;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_not_opened := v_not_opened + 1;     -- left for the twin's own reconcile at the first tick, with no head start
      RAISE WARNING '0849 boot head start: no session for % (% %); the first tick opens it', r.vid, SQLSTATE, SQLERRM;
    END;
  END LOOP;

  -- ... and played forward to the start clock by the twin's own arm and charge steps, as a tick plays them
  IF v_opened > 0 THEN
    SELECT min(cs.started_at) INTO v_tick
      FROM public.ocpp_sessions cs
     WHERE cs.sim_run_id = p_sim_run_id AND cs.status = 'active' AND cs.id_token LIKE 'TWIN-%';
    WHILE v_tick IS NOT NULL AND v_tick < v_t LOOP
      v_tick := LEAST(v_t, v_tick + v_step);
      PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_tick::text, true);
      PERFORM twin.ottoq_arm_advance_cycles(p_sim_run_id, v_tick);
      SELECT count(*) FILTER (WHERE a.out_action = 'completed'),
             count(*) FILTER (WHERE a.out_action LIKE 'faulted:%')
        INTO v_c, v_f
        FROM twin.ottoq_sim_advance_charge_sessions(p_sim_run_id, v_tick) a;
      v_completed := v_completed + COALESCE(v_c, 0);
      v_faulted   := v_faulted + COALESCE(v_f, 0);
      v_steps := v_steps + 1;
    END LOOP;
    BEGIN
      PERFORM public.ottoq_release_expired_tethers(v_t);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0849 boot head start: tether release: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  -- the start clock again, for everything after the head start
  PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_t::text, true);

  -- 3. every bay seat OTTO-Q started is already under way: moved back whole, so it keeps its full duration
  FOR r IN
    SELECT v.id AS vid, public.ottoq_try_timestamptz(v.config->>'service_ends_at') AS ends_at
      FROM public.vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
       AND v.current_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
       AND v.last_state_change = v_t
     ORDER BY v.id
  LOOP
    CONTINUE WHEN r.ends_at IS NULL OR r.ends_at <= v_t + interval '1 minute';
    v_dur := EXTRACT(EPOCH FROM (r.ends_at - v_t)) / 60.0;
    v_h   := round(LEAST(0.8 * v_dur, v_dur - 1) * twin.ottoq_sim_seeded_random(v_seed, 'boot_bay_head:' || r.vid::text), 1);
    CONTINUE WHEN v_h <= 0;
    v_end := r.ends_at - make_interval(secs => (v_h * 60)::double precision);
    UPDATE public.vehicles v
       SET last_state_change = v_t - make_interval(secs => (v_h * 60)::double precision),
           config = jsonb_set(
                      CASE WHEN jsonb_typeof(v.config->'bay_need') = 'object'
                           THEN jsonb_set(v.config, '{bay_need,ends_at}', to_jsonb(v_end::text))
                           ELSE v.config END,
                      '{service_ends_at}', to_jsonb(v_end::text))
     WHERE v.id = r.vid;
    v_bays := v_bays + 1;
    v_bay_heads := v_bay_heads || v_h;
  END LOOP;

  -- 4. what is left on the site with no place it holds (the gate is not the site)
  SELECT count(*) INTO v_unplaced
    FROM public.vehicles v
   WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous'
     AND v.current_state::text IN ('staged_for_departure', 'staged_awaiting_service', 'charge_complete_holding',
                                   'service_complete_holding')
     AND v.current_stall_id IS NULL;

  RETURN jsonb_build_object(
    'ok', true,
    'clock', v_t,
    'commands', CASE WHEN v_door THEN jsonb_build_object('door', 'twin_operator_step', 'result', v_door_out)
                     ELSE jsonb_build_object('door', 'confirm_commands', 'walked', v_walked) END,
    'charges', jsonb_build_object(
                 'opened', v_opened, 'not_opened', v_not_opened,
                 'head_start_min', CASE WHEN v_opened = 0 THEN NULL ELSE jsonb_build_object(
                     'min', (SELECT min(x) FROM unnest(v_heads) x), 'max', (SELECT max(x) FROM unnest(v_heads) x),
                     'mean', (SELECT round(avg(x), 1) FROM unnest(v_heads) x)) END,
                 'steps', v_steps, 'completed_before_start', v_completed, 'faulted_before_start', v_faulted),
    'bays', jsonb_build_object(
              'moved_back', v_bays,
              'head_start_min', CASE WHEN v_bays = 0 THEN NULL ELSE jsonb_build_object(
                  'min', (SELECT min(x) FROM unnest(v_bay_heads) x), 'max', (SELECT max(x) FROM unnest(v_bay_heads) x)) END),
    'on_site_without_a_stall', v_unplaced);
END
$fn$;

-- ── the whole step: OTTO-Q decides at the start clock, then the twin's head start, then the first tick at once ──
CREATE OR REPLACE FUNCTION public.ottoq_boot_mid_shift(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
-- 0849. Called by public.ottoq_sim_run_scenario for an operator start with boot_mid_shift on, before the agentic arm.
DECLARE
  v_t0      timestamptz := clock_timestamp();
  v_run     public.ottoq_sim_runs%ROWTYPE;
  v_limit_s numeric;
  v_left_s  numeric;
  v_enacted int;
  v_built   int;
  v_placed  jsonb;
  v_twin    jsonb;
  v_out     jsonb;
BEGIN
  SELECT * INTO v_run FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found');
  END IF;

  -- The budget. A start reached through the API runs under its role's statement_timeout (service_role: 20 s), which
  -- cancels the whole start and cannot be caught; the step stands down while there is still time to finish without it.
  SELECT NULLIF(s.setting::numeric, 0) / 1000.0 INTO v_limit_s FROM pg_settings s WHERE s.name = 'statement_timeout';
  v_left_s := v_limit_s - EXTRACT(EPOCH FROM (clock_timestamp() - statement_timestamp()));
  IF v_left_s IS NOT NULL AND v_left_s < 12 THEN
    v_out := jsonb_build_object('ok', false, 'skipped', 'time_budget', 'seconds_left', round(v_left_s, 1));
    UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('boot_mid_shift', v_out)
     WHERE sim_run_id = p_sim_run_id;
    RETURN v_out;
  END IF;

  -- 1. OTTO-Q decides at the start clock, on the start's world: its own tick, unchanged. The run and its clock are
  --    published for the transaction as the world tick publishes them (0204: ottoq.ottoq_run_now() reads them), so
  --    nothing in the decision falls back to the wall clock. A tick's length is read by the decide path's per-tick
  --    rates; the world tick writes it, and no world tick has run yet, so it is given the length of a first live tick
  --    (a minute) instead of the fixed-mode fallback (30 minutes on busy_day).
  PERFORM set_config('ottoq.sim_run_id', p_sim_run_id::text, true);
  PERFORM set_config('ottoq.sim_clock',
                     p_sim_run_id::text || '|' || COALESCE(v_run.sim_clock_current, v_run.sim_clock_start)::text, true);
  UPDATE public.ottoq_sim_runs
     SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('tick_minutes_actual', 1.0)
   WHERE sim_run_id = p_sim_run_id AND NOT (COALESCE(payload, '{}'::jsonb) ? 'tick_minutes_actual');
  SELECT d.out_dispatched, d.out_charge_assigned INTO v_enacted, v_built
    FROM public.ottoq_sim_decide_and_dispatch(p_sim_run_id) d;
  --    and places every car still on the site with no place it holds (its tick caps this at 60 cars)
  v_placed := ottoq.ottoq_place_unplaced_vehicles(p_sim_run_id, v_run.depot_id,
                                                  COALESCE(v_run.sim_clock_current, v_run.sim_clock_start), 200);

  -- 2. the twin carries it out at once, with the work already under way
  v_left_s := v_limit_s - EXTRACT(EPOCH FROM (clock_timestamp() - statement_timestamp()));
  IF v_left_s IS NOT NULL AND v_left_s < 4 THEN
    v_twin := jsonb_build_object('ok', false, 'skipped', 'time_budget', 'seconds_left', round(v_left_s, 1));
  ELSE
    v_twin := twin.ottoq_sim_boot_head_start(p_sim_run_id);
  END IF;

  -- 3. the first tick is due the moment the start commits, and plays the world from here
  UPDATE public.ottoq_sim_runs
     SET last_tick_at = clock_timestamp(), next_tick_due_at = clock_timestamp()
   WHERE sim_run_id = p_sim_run_id;

  v_out := jsonb_build_object(
    'ok', true,
    'decide', jsonb_build_object('enacted', v_enacted, 'requests_built', v_built),
    'placed', v_placed,
    'twin', v_twin,
    'ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000));
  UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('boot_mid_shift', v_out)
   WHERE sim_run_id = p_sim_run_id;
  RETURN v_out;
END
$fn$;

-- ── the patches ──
CREATE TEMP TABLE _0849_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0849_patch VALUES
(1, 'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)'::regprocedure,
$o$  -- 0323: ARM THE AGENTIC LAYER ON THE WAY IN. Across 1,147 runs nothing$o$,
$n$  -- ═══ 0849: AN OPERATOR'S RUN OPENS ON A YARD ALREADY AT WORK, AND OTTO-Q DECIDES BEFORE THE FIRST FRAME ═══
  -- Chase, 2026-11-19: "Just make sure Otto-q begins solving and orchestrating immediately as soon as the world
  -- variables are selected and the twin rendering loads."
  -- (1) Live playback from the first instant. Both demo doors set it right after this returns; a tick taken before
  --     they do would otherwise be a fixed-mode tick (tick_interval_seconds x time_scale, 30 sim-minutes on busy_day),
  --     and with metronome_idle_poll on one can come within a second.
  -- (2) Behind boot_mid_shift: OTTO-Q's first decision at the start clock, then the twin carries it out at once with
  --     the work already under way (public.ottoq_boot_mid_shift). Before the arm below, so the first decision holds no
  --     car for a proposer. A failure leaves the run as it started before 0849, with the reason on the row.
  IF COALESCE(p_run_by, '') = 'operator_demo' THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload, '{}'::jsonb)
                   || jsonb_build_object('playback_mode', COALESCE(payload->>'playback_mode', 'live'),
                                         'speed_x', COALESCE((payload->>'speed_x')::numeric, 1.0))
     WHERE sim_run_id = v_sim_run_id;
    IF COALESCE(ottoq_policy_get(v_sim_run_id, 'boot_mid_shift', 0), 0) >= 1 THEN
      BEGIN
        PERFORM public.ottoq_boot_mid_shift(v_sim_run_id);
      EXCEPTION WHEN OTHERS THEN
        UPDATE ottoq_sim_runs
           SET payload = COALESCE(payload, '{}'::jsonb)
                       || jsonb_build_object('boot_mid_shift', jsonb_build_object('ok', false, 'error', SQLERRM))
         WHERE sim_run_id = v_sim_run_id;
      END;
    END IF;
  END IF;

  -- 0323: ARM THE AGENTIC LAYER ON THE WAY IN. Across 1,147 runs nothing$n$),
(2, 'public.ottoq_demo_metronome(integer)'::regprocedure,
$o$    EXIT WHEN NOT v_any;
$o$,
$n$    -- 0849: A RUN STARTED BETWEEN TWO FIRINGS GETS ITS FIRST TICK WITHIN A SECOND. With nothing live this returned at
    -- once, so a new run waited for the next minute's firing (11 s on 368e1472, up to 60). With metronome_idle_poll at 1
    -- (global) it looks again every half second until its budget is spent, committing before each sleep, so an idle
    -- metronome holds no snapshot and no lock.
    IF NOT v_any THEN
      EXIT WHEN COALESCE(ottoq_policy_get(NULL::uuid, 'metronome_idle_poll', 0), 0) < 1
             OR EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
      COMMIT;
      PERFORM pg_sleep(0.5);
      CONTINUE;
    END IF;
$n$);

DO $patch$
DECLARE
  p record; v_def text; n int; f regprocedure;
BEGIN
  FOR p IN SELECT * FROM _0849_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0849 V2: anchor % matches % times, not 1', p.seq, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0849: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
  FOR f IN SELECT DISTINCT fn FROM _0849_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0849_patch WHERE fn = f ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0849_pre' AND s.object_name = (SELECT proname FROM pg_proc WHERE oid = f)) THEN
      RAISE EXCEPTION '0849 V1: % with its patch reversed is not its pre-image', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V3: a real operator start, with boot_mid_shift on, inside a block that is rolled back ──
CREATE TEMP TABLE _0849_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot   constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t0      timestamptz := clock_timestamp();
  v_run     uuid;
  v_t       timestamptz;
  v_boot    jsonb;
  v_mode    text;
  v_res     jsonb;
  v_site    int; v_unplaced int; v_nobook int;
  v_chg     int; v_before int; v_after int; v_low_target int;
  v_inbay   int; v_bay_ok int; v_bay_bad int;
  v_dec     int;
  v_ms      numeric;
BEGIN
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('depot', c_depot, 'boot_mid_shift', 1, '0849 self-test', now());
    v_run := public.ottoq_sim_run_scenario('busy_day', 849, 'operator_demo', NULL);
    v_ms := round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000);
    SELECT r.sim_clock_start, r.payload->'boot_mid_shift', r.payload->>'playback_mode' INTO v_t, v_boot, v_mode
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF NOT COALESCE((v_boot->>'ok')::boolean, false) OR NOT COALESCE((v_boot->'twin'->>'ok')::boolean, false) THEN
      RAISE EXCEPTION '0849 V3: the boot step did not run whole: %', v_boot;
    END IF;

    -- every car on the site but the gate's holds a stall, and a live booking for that stall
    SELECT count(*),
           count(*) FILTER (WHERE v.current_stall_id IS NULL),
           count(*) FILTER (WHERE v.current_stall_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM public.ottoq_stall_bookings b
                WHERE b.sim_run_id = v_run AND b.vehicle_id = v.id AND b.stall_id = v.current_stall_id
                  AND b.state IN ('held', 'active')))
      INTO v_site, v_unplaced, v_nobook
      FROM public.vehicles v
     WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
       AND v.current_state::text IN ('staged_for_departure', 'staged_awaiting_service', 'charge_complete_holding',
                                     'service_complete_holding', 'charging_dcfc', 'charging_l2',
                                     'in_wash_bay', 'in_detail_bay', 'in_service_bay');
    IF v_unplaced > 0 THEN
      RAISE EXCEPTION '0849 V3: % of % cars on the site hold no stall at the first frame', v_unplaced, v_site;
    END IF;

    -- OTTO-Q decided at the start clock
    SELECT count(*) INTO v_dec FROM public.ottoq_decisions d WHERE d.sim_run_id = v_run AND d.sim_clock = v_t;
    IF v_dec = 0 THEN
      RAISE EXCEPTION '0849 V3: no decision at the start clock';
    END IF;

    -- every charge opened before the start clock and none after it, to the car's own target (rule 9)
    SELECT count(*),
           count(*) FILTER (WHERE cs.started_at < v_t),
           count(*) FILTER (WHERE cs.started_at > v_t),
           count(*) FILTER (WHERE v.target_soc IS DISTINCT FROM public.ottoq_effective_target_soc_at(v.id, v_t))
      INTO v_chg, v_before, v_after, v_low_target
      FROM public.vehicles v
      JOIN public.ocpp_sessions cs ON cs.vehicle_id = v.id AND cs.status = 'active' AND cs.sim_run_id = v_run
     WHERE v.home_depot_id = c_depot AND v.current_state IN ('charging_dcfc', 'charging_l2');
    IF v_chg = 0 OR v_before = 0 OR v_after > 0 OR v_low_target > 0 THEN
      RAISE EXCEPTION '0849 V3: charges at the first frame: % active, % opened before the start, % after it, % below the car''s own target',
        v_chg, v_before, v_after, v_low_target;
    END IF;

    -- every bay seat began before the start clock and ends after it, its two timers in step
    SELECT count(*),
           count(*) FILTER (WHERE v.last_state_change < v_t
                              AND public.ottoq_try_timestamptz(v.config->>'service_ends_at') > v_t),
           count(*) FILTER (WHERE jsonb_typeof(v.config->'bay_need') = 'object'
                              AND v.config->'bay_need'->>'ends_at' IS DISTINCT FROM v.config->>'service_ends_at')
      INTO v_inbay, v_bay_ok, v_bay_bad
      FROM public.vehicles v
     WHERE v.home_depot_id = c_depot AND v.current_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay');
    IF v_bay_bad > 0 OR v_bay_ok < COALESCE((v_boot->'twin'->'bays'->>'moved_back')::int, 0) THEN
      RAISE EXCEPTION '0849 V3: bay seats at the first frame: % in a bay, % under way, % with timers out of step',
        v_inbay, v_bay_ok, v_bay_bad;
    END IF;

    IF v_mode IS DISTINCT FROM 'live' THEN
      RAISE EXCEPTION '0849 V3: the run is not in live playback (%)', v_mode;
    END IF;

    v_res := jsonb_build_object(
      'ran', true, 'start_ms', v_ms, 'boot_ms', v_boot->'ms',
      'decide', v_boot->'decide', 'placed', v_boot->'placed',
      'cars_on_site', v_site, 'without_a_stall', v_unplaced, 'stall_without_a_live_booking', v_nobook,
      'decisions_at_start_clock', v_dec,
      'charges', jsonb_build_object('active', v_chg, 'opened_before_start', v_before, 'opened_after_start', v_after,
                                    'head_start_min', v_boot->'twin'->'charges'->'head_start_min',
                                    'completed_before_start', v_boot->'twin'->'charges'->'completed_before_start',
                                    'faulted_before_start', v_boot->'twin'->'charges'->'faulted_before_start'),
      'bays', jsonb_build_object('in_a_bay', v_inbay, 'under_way', v_bay_ok,
                                 'head_start_min', v_boot->'twin'->'bays'->'head_start_min'),
      'playback_mode', v_mode);
    RAISE EXCEPTION USING ERRCODE = 'P0849', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0849' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused'))
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0849 self-test') THEN
    RAISE EXCEPTION '0849 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0849_selftest VALUES (v_res);
END $v3$;

-- ── on at the twin depot, and the metronome's poll globally (rule 12) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'boot_mid_shift', 1, 'Chase (delegated to Claude Code: 0849)', now()),
       ('global', '00000000-0000-0000-0000-000000000000', 'metronome_idle_poll', 1, 'Chase (delegated to Claude Code: 0849)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0849_a_demo_run_opens_on_a_yard_already_at_work_and_otto_q_decides_before_the_first_frame',
        false, false,
        'Operator starts (run_by operator_demo) only, behind boot_mid_shift (default 0, 1 at the twin depot): OTTO-Q '
        'decides at the start clock and places every car on the site; the twin walks its commands at once and gives '
        'each charge and bay seat a drawn head start. Every operator start opens in live playback. metronome_idle_poll '
        '(default 0, 1 globally): the demo metronome polls while nothing is live. Pairs start through '
        'twin.ottoq_sim_start_run and tick themselves; ab_harness starts are outside the gate. V3 self-test at apply '
        '(rolled back): ' || COALESCE((SELECT result::text FROM _0849_selftest LIMIT 1), 'no result'),
        now());

COMMIT;
