-- migration-version: 20261004112442
-- migration-name:    an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back
--
-- 0605  **An owner's agent sets what its own cars need, and the run's end puts it back.** A vehicle owner's own agent
--       (Chase's Hermes, for the 36 Teslas of Tesla Robotaxi TN at the twin depot) can now ask OTTO-Q, in plain words
--       or as a structured call, about its cars, and can change four things about them that are the owner's to
--       decide: how full they charge, which extra services they get (now, on their next return, or on every return),
--       and when they may leave at the earliest. Each change is checked against the owner's contract and OTTO-Q's
--       own rules, applied by the engine at its next tick, shown in OrchestrAV, answered with a receipt and a link,
--       undoable, and lifted when the demo run ends so the next run starts at baseline.
--
--       Three authorities, never crossed (Chase, 2026-10-02: "think of us as an agentic property manager and adjuster
--       for our assets"; "all vehicle movement is strictly handled by the vertical vehicle technology stack"):
--         the OWNER decides WHAT its cars need       -- through its agent, inside its contract;
--         OTTO-Q decides WHEN and WHERE              -- sequencing, stalls, bays, chargers, staging;
--         the AV stack decides HOW the car MOVES     -- nothing here moves a car or names a stall.
--
-- ══ §1 WHAT WAS MISSING (measured 2026-10-03 00:45-01:40 UTC, 7:45-8:40 PM CT, read-only) ══════════════════════════
--
--   (a) THE OWNER'S SLOT WAS RESERVED AND EMPTY. public.ottoq_effective_target_soc_at (0539) is the one answer to how
--       full a car charges, and its own comment reserves the place: "A per-vehicle limit an owner sets from an app,
--       verified and confirmed ... is read here when it exists, and no caller changes." Nothing could set one. Its 13
--       callers (decide tick, departure test, derive, charge plan, boot draw, dispatchers, service flow) read it.
--   (b) 0559's agent door had a kind for exactly this, `adjustment`, and routed it to `approved_no_engine_door`:
--       recorded, and nothing in the engine changed. 0559 is committed and not applied; this file extends it.
--   (c) CLAUDE.md rule 9 already names the owner as the only one who may lower a charge target ("A lower limit is only
--       ever the owner's, set verified and confirmed and read at that one function. The engine never writes one"), and
--       rule 10 keeps OTTO-Q from changing its own rules. An owner's setting is neither an experiment nor a dial.
--   (d) The four contracts on file carry min_charge_target_pct 80 and max_charge_target_pct 100, and no blocked or
--       required services. So an owner's charge limit is 80-100%, from the contract, not from this file.
--   (e) Tesla Robotaxi TN has 36 cars at the twin depot: Tesla-AV-041 ... Tesla-AV-070 (Model Y, av ids
--       twin-sim-041 ... 070) and Tesla-RT-001 ... RT-006 (RT-001-004 Cybercab, RT-005-006 Model Y). THE SAME NAMES
--       EXIST AGAIN at other depots (Tesla-AV-041 twice, Tesla-RT-006 twice, and four GRID-0169-SMOKE-AV cars at the
--       fixture depot), so a name is resolved only inside the token's depot scope -- 0559's own rule (home or current
--       depot) -- before it is matched. There is no "Tesla 98": a request naming it is refused with the fleet's names.
--   (f) Every owner-relevant engine read has one place to hook, measured:
--         how full          public.ottoq_effective_target_soc_at                (0539, the one answer)
--         may it leave      public.ottoq_departure_clear                        (0543, every exit, incl. the
--                                                                               ottoq_refuse_unfinished_departure trigger)
--         what it needs     ottoq_visit_needs.atoms, written by three inserters (derive, add_fault_repair, rider sweep)
--                           and rewritten by ~20 tick functions with read-modify-write of the whole array
--       That last fact decides the architecture. A door that wrote a visit's atoms from outside the tick would race
--       ottoq_start_concurrent_atoms (SELECT atoms; ...; UPDATE SET atoms = v_new) and lose the owner's service to a
--       lost update. So the agent's door writes only owner tables; the TICK applies them (the rider-flag precedent,
--       ottoq.ottoq_rider_flag_indepot_sweep), and a BEFORE INSERT trigger puts standing orders on each new visit.
--   (g) Every test-day runner refuses to start while any run is running or paused (dial runner, dial pair, sweep arm,
--       sweep runner, recert runner, all measured), and the twin depot's live runs are `operator_demo`. So an owner
--       setting -- which this file allows only on a live operator_demo run -- can never be in force while a
--       certification, dial or sweep arm runs.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   A CAPABILITY: `owner_settings`, only for a principal bound to one fleet operator (a CHECK on 0559's table). Chase's
--   token: kind personal, fleet Tesla Robotaxi TN, capabilities read + note + owner_settings. 0559's capabilities CHECK
--   already admits it (all three files were written before any was applied), so this file only ADDs the fleet check
--   and drops nothing.
--
--   TWO TABLES
--     ottoq_owner_commands   EVIDENCE. Every owner command, previews and refusals included: who, which tool, the
--                            arguments, the cars resolved, each car's before -> after, the plain-English summary, the
--                            plan hash, the link, the idempotency key. Append-only (a trigger), except that a later
--                            undo or the run's end is recorded once. No FK to ottoq_sim_runs (0340): it outlives the run.
--     ottoq_owner_settings   ENGINE (run-scoped working data). What is in force on the live run: a charge limit, a
--                            hold, or a service order, per car. FK to ottoq_sim_runs without CASCADE (registry check
--                            (c)); ottoq_purge_prior_runs clears it with its run.
--
--   THE ENGINE HOOKS (each inert without an owner row, which no certification or dial arm can have -- §6)
--     ottoq_effective_target_soc_at   LEAST(fleet default, contract ceiling, the owner's limit on the run in scope).
--     ottoq_departure_clear           and not held by its owner past the clock, and no owner service order still
--                                     waiting for its tick (an order placed mid-tick holds the car one tick, at most
--                                     one sim hour, so it cannot slip out before the service is on its visit).
--     ottoq_sim_advance_tick_world    one line before the visit-atom step: ottoq.ottoq_owner_orders_tick, which
--                                     re-targets cars whose limit changed (vehicles.target_soc, the open visit's
--                                     target and its charge atom: the twin's charge advance re-reads target_soc every
--                                     tick, so a car charging past a new 90% stops at the next tick), attaches or
--                                     removes owner service atoms on open visits, closes holds whose time has come and
--                                     orders that are done, and writes one summary event per tick that changed
--                                     something.
--     BEFORE INSERT on ottoq_visit_needs   a new visit (any of the three inserters, upserts included) carries the
--                                     owner's standing orders from its first row, so the itinerary planned for it
--                                     already has the bay leg.
--     AFTER UPDATE OF status on ottoq_sim_runs   the run's end LIFTS every owner setting, puts the cars that carried
--                                     a limit back to their target with none, and stamps lifted_at on the commands.
--
--   THE TOOLS, inside 0559's one dispatcher (service_role only; scope, rate limit and ledger unchanged)
--     reads (capability read)          my_fleet, my_vehicle, my_settings; my_commands (any token, its own)
--     commands (capability owner_settings), every one with mode preview | apply, expect_plan_hash, idempotency_key:
--       set_charge_limit {vehicles, percent}        80-100 per the owner's contract; 100 (the ceiling) = clear
--       clear_charge_limit {vehicles}
--       request_service {vehicles, service, when}   when = now (this visit, or the next if out) | next_return |
--                                                   every_return (include_current_visit, default true)
--       cancel_service {vehicles, service?}         withdraws the OWNER's orders; never a service OTTO-Q found needed
--       hold_vehicle {vehicles, until | for_minutes}  "not before": at most 24 sim hours, never past the run
--       release_hold {vehicles}
--       undo_command {command_id}                   reverts what a command set and restores what it replaced
--     `vehicles` is "all" or names: "Tesla-AV-045", "AV-45", "45", "twin-sim-045", "RT-3", or the uuid.
--     A preview answers with its plan_hash and a ready-to-send confirm that applies exactly the plan shown: the plan hash
--     covers the cars and each one's before -> after, never telemetry, and a hold's confirm names the absolute time it
--     resolved to, so "for 90 minutes" previewed at 7:00 still means 8:30 when confirmed at 7:30. The same
--     idempotency_key replays the first receipt; the same key with a different command is refused (422,
--     idempotency_key_reused) rather than answered with the first command's receipt.
--     Services an owner may request (11): exterior_wash, interior_deep_clean, interior_tidy, interior_inspection,
--     sensor_clean, sensor_calibration, software_update, remote_diagnostics, mechanical_pm, cosmetic_repair,
--     item_retrieval. Not requestable: charge (the limit is the owner's lever), readiness_check (OTTO-Q's gate),
--     triage_check (OTTO-Q's judgement of uncertain needs), fault_repair (raised by a fault), perimeter_walkaround
--     (the depot's own night round).
--
-- ══ §3 THE SAFETY ENVELOPE (every line is enforced here, not in a prompt) ══════════════════════════════════════════
--
--   * Scope: the token's fleet at the token's depot (the twin depot, rule 8). A car outside it reads as not found.
--   * Only while an operator_demo run is live, and only on that run (rule 10's line between production and research
--     does not move; a demo run is the twin).
--   * Charge: only lower or restore, and only within the owner's contract [min_charge_target_pct,
--     max_charge_target_pct]; a hard floor of 50 in the table besides. The depot never lowers a target (rule 9): the
--     owner does, here, verified (the contract) and confirmed (an explicit apply, optionally bound to a previewed plan
--     hash).
--   * Services: an owner may ADD work, never remove work OTTO-Q found the car to need (rule 9: "NO CAR LEAVES WITH A
--     SERVICE STILL NEEDED, EVER"). Cancelling removes only the owner's own atoms that have not started; a service in
--     progress finishes. A service the contract blocks is refused.
--   * Holds: "not before" only. A hold can delay a departure, never cause one; a held car that is ready waits in
--     staging (0543's recheck leaves a finished car where it is parked), and no charger is kept for it.
--   * No movement, no stall, no booking, no session, no command: the agent side writes ottoq_agent_* and ottoq_owner_*
--     tables only (V5). The engine side changes the car's NEEDS (target, atoms) and nothing else; the decide path,
--     unchanged, disposes.
--   * Everything is reversible: undo_command, cancel/clear/release, and the run's end.
--
-- ══ §4 WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════════════════════════
--
--   * No persistence across runs. Chase, 2026-10-02: accepted adjustments "should automatically reset when I stop the
--     current simulation run and reset the entire twin simulation". A saved per-owner profile is the later step.
--   * No ready-by deadline or priority. Moving one owner's car ahead of another owner's is a contract entitlement
--     question across tenants, not an owner setting; named, not built.
--   * No charger-type preference (e.g. "L2 for battery health"). It needs a decide-path hook; named, not built.
--   * No push notification to the agent ("tell me when it is ready"). It needs the agent's webhook and a signing
--     secret; designed in PERSONAL_AGENT.md, not built.
--   * No ottoq_events row from the agent's door: only the tick writes one, when the engine applies owner settings.
--   * No grant to anon or authenticated here. OrchestrAV's read of an owner's settings is 0606, a separate exposure
--     decision, as 0560 was for requests.
--
-- ══ §5 THE ONE THING THAT MUST BE TRUE FOR "AFTER CHARGING" ═════════════════════════════════════════════════════════
--
--   "Send Tesla 98 to a service bay immediately after charging": ottoq_plan_visit_itinerary already plans every bay
--   leg after the charge leg (a fault repair alone goes first, 0558), the legs run in seq order, and a car whose bay
--   atom was added after its itinerary was planned is caught by 0543's departure recheck and routed to the bay before
--   it can leave. So "after charging" is the engine's order, not a hint this file adds; mechanical_pm is the service
--   bay's own service (about 40 min).
--
-- ══ §6 forces_recert TRUE, forces_dial_restart TRUE ════════════════════════════════════════════════════════════════
--
--   Every hook is guarded by an EXISTS over ottoq_owner_settings, and no certification, dial or sweep arm can hold a
--   row there (the only writer is the agent dispatcher, which refuses any run but a live operator_demo, and no arm can
--   start while one is live, §1(g)). V2 measures it on the live catalog: every twin-depot car's effective target and
--   departure verdict on the latest run is computed before and after this file in the same transaction, and must be
--   identical. Classified TRUE anyway: three tick-path bodies change, and a migration cannot run a pair to prove the
--   tick unchanged. Under-classifying would carry certifications silently; over-classifying costs one recert round.
--
-- ══ §7 VALIDATED ON A SCRATCH CLUSTER ═══════════════════════════════════════════════════════════════════════════════
--
--   tests/fixtures/owner_agent_stub_engine.sql loads after 0559's stub and adds the six engine functions this file
--   replaces or patches, each byte-identical to the live catalog (md5 asserted by the test), with the tables they
--   read. tests/test_owner_agent_sql.py applies 0559, 0560, 0605 and 0606 and drives every tool, the tick step, the
--   visit trigger, the departure test, the run's end and the grants (50 tests). tests/owner_agent.test.mjs drives the
--   gateway's owner tools, REST, MCP and POST /v1/ask over the same SQL end to end. Both skip where no scratch server
--   exists; CI's executed-gateway step runs them.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0605 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0559 applied as written; the six bodies this file replaces are the ones it was written against ──
DO $premises$
DECLARE
  v_src  text;
  v_bad  text;
  v_need text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back') THEN
    RAISE EXCEPTION '0605 P1: already applied';
  END IF;
  IF to_regclass('public.ottoq_agent_principals') IS NULL OR to_regclass('public.ottoq_agent_call_ledger') IS NULL THEN
    RAISE EXCEPTION '0605 P1: 0559 (the agent gateway) is not applied; apply it first';
  END IF;
  -- 0559's table admits the capability, so §1 adds a CHECK and drops none
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                  WHERE c.conrelid = 'public.ottoq_agent_principals'::regclass
                    AND c.conname = 'ottoq_agent_principals_capabilities_check'
                    AND pg_get_constraintdef(c.oid) LIKE '%''owner_settings''%') THEN
    RAISE EXCEPTION '0605 P1: 0559''s capabilities CHECK does not admit owner_settings; apply 0559 as merged with this file';
  END IF;
  -- md5(prosrc), measured: 0559's three bodies as 0559 writes them; the three engine bodies on the live catalog
  -- 2026-10-03 ~01:00 UTC
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)',                                   'd81491ad77a17d0ef3af08e96567043b'),
      ('public.ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)',       '28372bb4045c85434793fa2e0f21609f'),
      ('public.ottoq_agent_read_whoami(public.ottoq_agent_principals)',                         'd098e1d77fb3123693bc7c516892b5f2'),
      ('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)',                   '85a933ee641c32c02da3487b091581c9'),
      ('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)',               '759448f46b88779dd4d8a9d426d865c1'),
      ('public.ottoq_sim_advance_tick_world(uuid)',                                              '0929252a9b60a2cbd5457727c78c0358')) x(f, want)
   WHERE to_regprocedure(f) IS NULL
      OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(f)) IS DISTINCT FROM want;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0605 P1: not the body this file was written against (re-measure before applying): %', v_bad;
  END IF;
  -- the world step's anchor, exactly once
  v_src := (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);
  IF (length(v_src) - length(replace(v_src, '  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);', '')))
     / length('  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);') <> 1 THEN
    RAISE EXCEPTION '0605 P1: the world step''s visit-atom line does not occur exactly once';
  END IF;
  -- the run's end, as the close-needs trigger reads it (the lift trigger fires on the same transition)
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_sim_runs'::regclass AND t.tgname = 'ottoq_sim_runs_close_needs'
                    AND pg_get_triggerdef(t.oid) LIKE '%(old.status = ANY (ARRAY[''initializing''::text, ''running''::text, ''paused''::text]))%'
                    AND pg_get_triggerdef(t.oid) LIKE '%(new.status = ANY (ARRAY[''completed''::text, ''failed''::text, ''aborted''::text]))%') THEN
    RAISE EXCEPTION '0605 P1: ottoq_sim_runs_close_needs no longer fires on running/paused -> completed/failed/aborted';
  END IF;
  -- what the engine side reads and writes
  FOREACH v_need IN ARRAY ARRAY['vehicles.target_soc', 'vehicles.current_soc', 'vehicles.current_state',
      'vehicles.av_api_vehicle_id', 'vehicles.display_name', 'vehicles.current_stall_id', 'vehicles.config',
      'ottoq_visit_needs.atoms', 'ottoq_visit_needs.target_soc', 'ottoq_visit_needs.arrived_at', 'ottoq_visit_needs.visit_key',
      'service_cadence_policy.display_name', 'service_cadence_policy.lane', 'service_cadence_policy.est_min_default',
      'ottoq_fleet_operator_slas.min_charge_target_pct', 'ottoq_fleet_operator_slas.max_charge_target_pct',
      'ottoq_fleet_operator_slas.blocked_services', 'ottoq_vehicle_dispatches.dispatched_at',
      'ottoq_itinerary_legs.planned_end_sim', 'ottoq_sim_runs.sim_clock_end', 'ottoq_sim_runs.run_by'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns c
                    WHERE c.table_schema = 'public' AND c.table_name = split_part(v_need, '.', 1)
                      AND c.column_name = split_part(v_need, '.', 2)) THEN
      RAISE EXCEPTION '0605 P1: % is missing', v_need;
    END IF;
  END LOOP;
  IF (SELECT data_type FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'vehicles' AND column_name = 'target_soc') <> 'integer' THEN
    RAISE EXCEPTION '0605 P1: vehicles.target_soc is no longer an integer';
  END IF;
  -- every service an owner may request is one the engine can complete (else ottoq_atoms_guard would demote it)
  SELECT string_agg(s, ', ') INTO v_bad
    FROM unnest(ARRAY['exterior_wash','interior_deep_clean','interior_tidy','interior_inspection','sensor_clean',
                      'sensor_calibration','software_update','remote_diagnostics','mechanical_pm','cosmetic_repair',
                      'item_retrieval']) s
   WHERE NOT ottoq.ottoq_atom_retirable(s)
      OR NOT EXISTS (SELECT 1 FROM public.service_cadence_policy c WHERE c.svc = s AND c.is_active);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0605 P1: owner-requestable service(s) the engine cannot complete or does not declare: %', v_bad;
  END IF;
  IF to_regprocedure('ottoq.ottoq_svc_to_stall_type(text,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)') IS NULL
     OR to_regclass('public.ottoq_event_types_catalog') IS NULL
     OR to_regclass('public.ottoq_schema_snapshots') IS NULL THEN
    RAISE EXCEPTION '0605 P1: a function or table this file calls is missing';
  END IF;
END $premises$;

-- ── P2: nothing this file creates exists yet, and the registry guard is clean before it is touched ──
DO $fresh$
DECLARE v_block int; v_fn text;
BEGIN
  IF to_regclass('public.ottoq_owner_commands') IS NOT NULL OR to_regclass('public.ottoq_owner_settings') IS NOT NULL THEN
    RAISE EXCEPTION '0605 P2: an ottoq_owner_* table already exists';
  END IF;
  SELECT string_agg(n.nspname || '.' || p.proname, ', ') INTO v_fn
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq')
     AND (p.proname LIKE 'ottoq\_owner\_%'
          OR p.proname IN ('ottoq_tg_owner_orders_on_new_visit', 'ottoq_tg_lift_owner_settings_on_terminal'));
  IF v_fn IS NOT NULL THEN
    RAISE EXCEPTION '0605 P2: function(s) this file creates already exist: %', v_fn;
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0605 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $fresh$;

-- ── the rollback snapshot of the six bodies this file replaces ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0605_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)'::regprocedure,
                 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)'::regprocedure,
                 'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure,
                 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);

-- ── the inertness baseline (V2): every twin-depot car's target and departure verdict on the latest run, BEFORE ──
CREATE TEMP TABLE m0605_before ON COMMIT DROP AS
SELECT v.id AS vehicle_id,
       public.ottoq_effective_target_soc_at(v.id, COALESCE(r.sim_clock_current, now())) AS target,
       public.ottoq_departure_clear(v.id, r.sim_run_id, COALESCE(r.sim_clock_current, now()), true) AS clear_full,
       public.ottoq_departure_clear(v.id, r.sim_run_id, COALESCE(r.sim_clock_current, now()), false) AS clear_recheck
  FROM public.vehicles v
  LEFT JOIN LATERAL (SELECT x.sim_run_id, x.sim_clock_current FROM public.ottoq_sim_runs x
                      WHERE x.depot_id = '11111111-1111-1111-1111-111111111111'
                      ORDER BY x.started_at DESC LIMIT 1) r ON true
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
    OR v.current_depot_id = '11111111-1111-1111-1111-111111111111';

-- ══ 1. the capability ═══════════════════════════════════════════════════════════════════════════════════════════════
--: 0559's capabilities CHECK already admits owner_settings (P1 asserts it). An owner's settings are for its own cars,
--: so the capability needs a fleet.
ALTER TABLE public.ottoq_agent_principals ADD CONSTRAINT ottoq_agent_principals_owner_scope_check CHECK (
  NOT ('owner_settings' = ANY (capabilities)) OR fleet_operator_id IS NOT NULL);

-- ══ 2. the tables ═══════════════════════════════════════════════════════════════════════════════════════════════════

CREATE TABLE public.ottoq_owner_commands (
  command_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  principal_id         uuid NOT NULL REFERENCES public.ottoq_agent_principals(principal_id),
  --: frozen at the command, so history reads right after a revocation
  principal_name       text NOT NULL,
  fleet_operator_id    uuid NOT NULL,
  depot_id             uuid NOT NULL,
  --: Durable historical key. NO FOREIGN KEY, deliberately (0340, as 0559's requests): the run may be purged; this
  --: row must not be.
  sim_run_id           uuid,
  --: that run's SIM clock at the command. SIM domain: never compared with now().
  sim_clock            timestamptz,
  tool                 text NOT NULL,
  mode                 text NOT NULL,
  outcome              text NOT NULL,
  args                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  --: [{id, name}] the cars the command resolved to, in the order asked
  vehicles             jsonb NOT NULL DEFAULT '[]'::jsonb,
  --: per car: before -> after and what happens now, in plain words
  effects              jsonb NOT NULL DEFAULT '[]'::jsonb,
  refusal              jsonb,
  summary              text NOT NULL,
  plan_hash            text,
  link                 text,
  idempotency_key      text,
  undoes_command_id    uuid REFERENCES public.ottoq_owner_commands(command_id),
  --: the only columns that ever change, each once, from NULL: a later undo, or the run's end
  undone_by_command_id uuid REFERENCES public.ottoq_owner_commands(command_id),
  undone_at            timestamptz,
  lifted_at            timestamptz,
  lifted_reason        text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_owner_commands_tool_check CHECK (tool IN ('set_charge_limit', 'clear_charge_limit', 'request_service',
    'cancel_service', 'hold_vehicle', 'release_hold', 'undo_command')),
  CONSTRAINT ottoq_owner_commands_mode_outcome_check CHECK (
       (mode = 'preview' AND outcome IN ('previewed', 'refused'))
    OR (mode = 'apply'   AND outcome IN ('applied', 'no_change', 'refused'))),
  CONSTRAINT ottoq_owner_commands_refusal_check CHECK ((outcome = 'refused') = (refusal IS NOT NULL)),
  CONSTRAINT ottoq_owner_commands_summary_check CHECK (char_length(summary) BETWEEN 1 AND 6000),
  CONSTRAINT ottoq_owner_commands_args_check CHECK (jsonb_typeof(args) = 'object' AND octet_length(args::text) <= 8000),
  CONSTRAINT ottoq_owner_commands_vehicles_check CHECK (jsonb_typeof(vehicles) = 'array'),
  CONSTRAINT ottoq_owner_commands_effects_check CHECK (jsonb_typeof(effects) = 'array'),
  CONSTRAINT ottoq_owner_commands_idempotency_check CHECK (
    idempotency_key IS NULL OR (mode = 'apply' AND idempotency_key ~ '^[A-Za-z0-9._:-]{1,100}$')),
  CONSTRAINT ottoq_owner_commands_undo_check CHECK (undoes_command_id IS NULL OR tool = 'undo_command'),
  CONSTRAINT ottoq_owner_commands_undone_check CHECK ((undone_at IS NULL) = (undone_by_command_id IS NULL)),
  CONSTRAINT ottoq_owner_commands_lifted_check CHECK ((lifted_at IS NULL) = (lifted_reason IS NULL))
);

COMMENT ON TABLE public.ottoq_owner_commands IS
'0605. Every command an owner''s agent sent about its own cars -- previews and refusals included: the principal, the tool, the arguments, the cars resolved, each car''s before -> after, the plain-English summary, the plan hash and the OrchestrAV link. EVIDENCE: append-only by trigger, except that a later undo (undone_*) or the run''s end (lifted_*) is recorded once. No FK to ottoq_sim_runs (0340): a command outlives the run it applied to. sim_clock is SIM time; created_at is real time.';

CREATE UNIQUE INDEX ottoq_owner_commands_idempotency_idx
  ON public.ottoq_owner_commands (principal_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX ottoq_owner_commands_principal_idx ON public.ottoq_owner_commands (principal_id, created_at DESC);
CREATE INDEX ottoq_owner_commands_operator_idx ON public.ottoq_owner_commands (fleet_operator_id, depot_id, created_at DESC);
CREATE INDEX ottoq_owner_commands_run_idx ON public.ottoq_owner_commands (sim_run_id) WHERE sim_run_id IS NOT NULL;

CREATE TABLE public.ottoq_owner_settings (
  setting_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  --: run-scoped working data (class engine): ottoq_purge_prior_runs clears it with its run. NOT CASCADE: registry
  --: check (c) refuses a cascading FK to the run table.
  sim_run_id            uuid NOT NULL REFERENCES public.ottoq_sim_runs(sim_run_id),
  depot_id              uuid NOT NULL,
  fleet_operator_id     uuid NOT NULL,
  vehicle_id            uuid NOT NULL,
  kind                  text NOT NULL,
  charge_limit_pct      numeric,
  --: SIM time: the earliest the car may leave
  hold_until_sim        timestamptz,
  service               text,
  service_when          text,
  include_current_visit boolean,
  command_id            uuid NOT NULL REFERENCES public.ottoq_owner_commands(command_id),
  --: what this setting replaced, so an undo can restore it
  replaces_setting_id   uuid REFERENCES public.ottoq_owner_settings(setting_id) ON DELETE SET NULL,
  status                text NOT NULL DEFAULT 'active',
  set_at                timestamptz NOT NULL DEFAULT now(),
  set_at_sim            timestamptz NOT NULL,
  closed_at             timestamptz,
  closed_at_sim         timestamptz,
  closed_reason         text,
  closed_by_command_id  uuid REFERENCES public.ottoq_owner_commands(command_id),
  --: the tick's work list: a setting made, replaced, withdrawn or lifted is reconciled into the car's charge target and
  --: its visit at the next tick, then cleared
  pending_reconcile     boolean NOT NULL DEFAULT true,
  applied               jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ottoq_owner_settings_kind_check CHECK (kind IN ('charge_limit', 'hold', 'service')),
  CONSTRAINT ottoq_owner_settings_status_check CHECK (status IN ('active', 'replaced', 'withdrawn', 'fulfilled', 'lifted')),
  CONSTRAINT ottoq_owner_settings_charge_limit_check CHECK (kind <> 'charge_limit'
    OR (charge_limit_pct BETWEEN 50 AND 100 AND hold_until_sim IS NULL AND service IS NULL AND service_when IS NULL)),
  CONSTRAINT ottoq_owner_settings_hold_check CHECK (kind <> 'hold'
    OR (hold_until_sim IS NOT NULL AND charge_limit_pct IS NULL AND service IS NULL AND service_when IS NULL)),
  CONSTRAINT ottoq_owner_settings_service_check CHECK (kind <> 'service'
    OR (service IS NOT NULL AND service_when IN ('now', 'next_return', 'every_return')
        AND charge_limit_pct IS NULL AND hold_until_sim IS NULL)),
  CONSTRAINT ottoq_owner_settings_closed_check CHECK ((status = 'active') = (closed_at IS NULL)),
  CONSTRAINT ottoq_owner_settings_applied_check CHECK (jsonb_typeof(applied) = 'object')
);

COMMENT ON TABLE public.ottoq_owner_settings IS
'0605. What an owner''s agent has set for its own cars on the live demo run: a charge limit (read by ottoq_effective_target_soc_at), a hold (read by ottoq_departure_clear) or a service order (put on the car''s visits by ottoq.ottoq_owner_orders_tick and the ottoq_visit_needs insert trigger). Run-scoped engine data: lifted when its run ends (ottoq_sim_runs_lift_owner_settings), cleared by ottoq_purge_prior_runs. One active limit, one active hold, and one active order per service, per car. The commands that made them are in ottoq_owner_commands.';

CREATE UNIQUE INDEX ottoq_owner_settings_one_limit_idx
  ON public.ottoq_owner_settings (sim_run_id, vehicle_id) WHERE kind = 'charge_limit' AND status = 'active';
CREATE UNIQUE INDEX ottoq_owner_settings_one_hold_idx
  ON public.ottoq_owner_settings (sim_run_id, vehicle_id) WHERE kind = 'hold' AND status = 'active';
CREATE UNIQUE INDEX ottoq_owner_settings_one_service_idx
  ON public.ottoq_owner_settings (sim_run_id, vehicle_id, service) WHERE kind = 'service' AND status = 'active';
--: the hot read: the engine's hooks ask "does this car have an active owner setting" first, and nearly always "no"
CREATE INDEX ottoq_owner_settings_vehicle_active_idx ON public.ottoq_owner_settings (vehicle_id, kind) WHERE status = 'active';
CREATE INDEX ottoq_owner_settings_tick_idx ON public.ottoq_owner_settings (sim_run_id) WHERE status = 'active' OR pending_reconcile;
CREATE INDEX ottoq_owner_settings_command_idx ON public.ottoq_owner_settings (command_id);
CREATE INDEX ottoq_owner_settings_replaces_idx ON public.ottoq_owner_settings (replaces_setting_id) WHERE replaces_setting_id IS NOT NULL;

-- ══ 3. the guard: a ledger that can be edited proves nothing ════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_commands_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'ottoq_owner_commands keeps every command: DELETE refused' USING ERRCODE = '42501';
  END IF;
  --: what was commanded, and what OTTO-Q answered, are immutable
  IF (NEW.command_id, NEW.principal_id, NEW.principal_name, NEW.fleet_operator_id, NEW.depot_id, NEW.sim_run_id,
      NEW.sim_clock, NEW.tool, NEW.mode, NEW.outcome, NEW.args, NEW.vehicles, NEW.effects, NEW.refusal, NEW.summary,
      NEW.plan_hash, NEW.link, NEW.idempotency_key, NEW.undoes_command_id, NEW.created_at)
     IS DISTINCT FROM
     (OLD.command_id, OLD.principal_id, OLD.principal_name, OLD.fleet_operator_id, OLD.depot_id, OLD.sim_run_id,
      OLD.sim_clock, OLD.tool, OLD.mode, OLD.outcome, OLD.args, OLD.vehicles, OLD.effects, OLD.refusal, OLD.summary,
      OLD.plan_hash, OLD.link, OLD.idempotency_key, OLD.undoes_command_id, OLD.created_at) THEN
    RAISE EXCEPTION 'owner command %: what was commanded and answered is immutable', OLD.command_id USING ERRCODE = '42501';
  END IF;
  --: an undo and a lift are each recorded once
  IF (OLD.undone_at IS NOT NULL AND (NEW.undone_at IS DISTINCT FROM OLD.undone_at
                                     OR NEW.undone_by_command_id IS DISTINCT FROM OLD.undone_by_command_id))
     OR (OLD.lifted_at IS NOT NULL AND (NEW.lifted_at IS DISTINCT FROM OLD.lifted_at
                                        OR NEW.lifted_reason IS DISTINCT FROM OLD.lifted_reason)) THEN
    RAISE EXCEPTION 'owner command %: an undo or a lift is recorded once', OLD.command_id USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_owner_commands_guard_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_owner_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_owner_commands_guard();
CREATE TRIGGER ottoq_owner_commands_no_truncate_trg
  BEFORE TRUNCATE ON public.ottoq_owner_commands
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_agent_no_truncate();

-- ══ 4. register the run-scoped columns ══════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
  ('public', 'ottoq_owner_settings', 'sim_run_id', 'engine',
   '0605: what an owner''s agent set for its cars on one demo run. Run-scoped working data: lifted at the run''s end by ottoq_sim_runs_lift_owner_settings, cleared by ottoq_purge_prior_runs. FK to ottoq_sim_runs, not CASCADE (check (c)); no DELETE guard (check (d)).'),
  ('public', 'ottoq_owner_commands', 'sim_run_id', 'evidence',
   '0605: the run an owner''s command applied to. Evidence, not engine: what an owner asked and what OTTO-Q answered must survive ottoq_purge_prior_runs. Deliberately NO foreign key to ottoq_sim_runs (0340, as 0559''s requests).');

-- ══ 5. the engine's reads ═══════════════════════════════════════════════════════════════════════════════════════════

-- The owner's active charge limit for a car on the run in scope, or NULL. Called by ottoq_effective_target_soc_at only
-- when the car has an active limit at all (one index probe; nearly always no). The run in scope is the one the engine
-- pins (ottoq.sim_run_id: a tick, a pair arm, a stop), 'none' is no run, and with nothing pinned it is a live run
-- (running or paused) -- the cockpit reads. Unlike ottoq.ottoq_active_sim_run_id() this caches nothing: a function
-- this file adds to the effective target must not change what a later call in the same transaction resolves.
CREATE OR REPLACE FUNCTION public.ottoq_owner_charge_limit(p_vehicle_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_guc text := NULLIF(current_setting('ottoq.sim_run_id', true), '');
  v     numeric;
BEGIN
  IF v_guc = 'none' THEN
    RETURN NULL;
  END IF;
  SELECT o.charge_limit_pct INTO v
    FROM public.ottoq_owner_settings o
   WHERE o.vehicle_id = p_vehicle_id AND o.kind = 'charge_limit' AND o.status = 'active'
     AND CASE WHEN v_guc IS NOT NULL THEN o.sim_run_id::text = v_guc
              ELSE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                            WHERE r.sim_run_id = o.sim_run_id AND r.status IN ('running', 'paused')) END
   ORDER BY o.set_at DESC, o.setting_id
   LIMIT 1;
  RETURN v;
END $fn$;

-- Whether a car's owner keeps it at the depot past this clock, or has an order still waiting for its tick. SECURITY
-- DEFINER because ottoq_departure_clear is SECURITY INVOKER and executable by anon, authenticated and service_role:
-- the owner table grants none of them anything.
CREATE OR REPLACE FUNCTION public.ottoq_owner_departure_blocked(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamptz)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT p_sim_run_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.ottoq_owner_settings o
     WHERE o.vehicle_id = p_vehicle_id AND o.sim_run_id = p_sim_run_id AND o.status = 'active'
       AND (   (o.kind = 'hold' AND o.hold_until_sim > p_clock)
            -- an order placed after this tick began holds the car for the tick that puts it on the visit; bounded
            -- to one sim hour, so a tick step that kept failing could not keep a car forever
            OR (o.kind = 'service' AND o.pending_reconcile AND o.service_when <> 'next_return'
                AND o.set_at_sim > p_clock - interval '60 minutes')))
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0539 (Chase 2026-09-27, CLAUDE.md rule 9): HOW FULL THIS CAR CHARGES, AND IT IS THE OWNER'S ANSWER. The fleet
  -- default (public.ottoq_default_target_soc(), 100) under the owner's contract ceiling
  -- (ottoq_fleet_operator_slas.max_charge_target_pct, 100 in all four contracts). Nothing the depot decides enters it.
  -- A per-vehicle limit an owner sets from an app, verified and confirmed ("that would permanently save to their
  -- vehicle settings, and OTTO-Q would acknowledge that"), is read here when it exists, and no caller changes.
  -- This read vehicles.target_soc first, the engine's own stamp of the car's last plan and not the owner's; then the
  -- contract's PREFERRED deployment SoC (90), the bar for leaving and not a charge target; then 90. It had no caller.
  -- 0605 (Chase 2026-10-02): AND THIS IS WHERE THE OWNER'S LIMIT IS READ, as 0539 reserved. An owner's agent sets it
  -- (public.ottoq_owner_settings, kind charge_limit), verified against the contract's [min, max] and confirmed by an
  -- explicit apply; it lasts until its run ends. Only a car with an active limit pays for the lookup, and the lookup
  -- is matched to the run in scope (public.ottoq_owner_charge_limit). p_as_of picks the contract version only.
  SELECT LEAST(
    public.ottoq_default_target_soc(),
    COALESCE((SELECT s.max_charge_target_pct FROM ottoq_fleet_operator_slas s
               WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
                 AND s.effective_from <= p_as_of
                 AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
               ORDER BY s.version DESC LIMIT 1), 100),
    CASE WHEN EXISTS (SELECT 1 FROM public.ottoq_owner_settings o
                       WHERE o.vehicle_id = v.id AND o.kind = 'charge_limit' AND o.status = 'active')
         THEN public.ottoq_owner_charge_limit(v.id) END)
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_departure_clear(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_need_readiness boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0543 (CLAUDE.md rule 9, Chase 2026-09-27): a car leaves only when nothing it needs is left. Its charge is at its
  -- effective target - 1 (G244's one rule), and no service on its open visit is open or in progress. With
  -- p_need_readiness the readiness check must be done too (the dispatchers). Without it (the recheck) the readiness
  -- check is left to the staging it is done in. A car with no SoC on record is not clear.
  -- 0555 (G290): and it carries no vehicle fault that has not been repaired. The fault lives in config.exception, which
  -- neither the charge nor the card shows, so Waymo-AV-011 left with a steering/brake fault on 0410's run.
  -- 0605 (Chase 2026-10-02): and its owner has not asked OTTO-Q to keep it until later on this run (a hold is "not
  -- before" and can only delay a departure), and no owner service order placed this tick is still waiting to be put on
  -- its visit. A finished car that is held fails here and nowhere else, so 0543's recheck leaves it parked in staging.
  SELECT COALESCE(v.current_soc >= public.ottoq_effective_target_soc_at(v.id, p_clock) - 1, false)
     AND NOT public.ottoq_vehicle_fault_open(v.config)
     AND NOT EXISTS (
           SELECT 1
             FROM public.ottoq_visit_needs vn
             CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
            WHERE vn.vehicle_id = v.id
              AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              AND vn.status IN ('open', 'in_progress')
              AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')
              AND (p_need_readiness OR a->>'svc' <> 'readiness_check'))
     AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id;
$function$;

-- ══ 6. the engine applies them: the atoms, the visit trigger, the tick step, the run's end ══════════════════════════

-- Whether a standing order applies to the visit a car has now (or is opening). 'now' and 'every_return' with the
-- current visit included: yes while active. 'next_return' (and 'every_return' without the current visit): only once the
-- car has LEFT after the order -- a dispatch on this run dated at or after it -- because a visit re-derived while the
-- car never left also carries a later arrived_at, and is not a return.
CREATE OR REPLACE FUNCTION ottoq.ottoq_owner_order_applies(p_s public.ottoq_owner_settings)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT p_s.status = 'active' AND p_s.kind = 'service'
     AND (p_s.service_when = 'now'
          OR (p_s.service_when = 'every_return' AND COALESCE(p_s.include_current_visit, true))
          OR EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                      WHERE d.vehicle_id = p_s.vehicle_id AND d.sim_run_id = p_s.sim_run_id
                        AND d.dispatched_at >= p_s.set_at_sim))
$fn$;

-- The atom an owner's order adds, shaped exactly as derive shapes the same service (lane -> concurrency and bay, the
-- catalog's minutes, the resolver's stall type), tagged with the order. carryover_eligible false: it is done on this
-- visit or the car does not leave.
CREATE OR REPLACE FUNCTION ottoq.ottoq_owner_service_atom(p_s public.ottoq_owner_settings, p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE v_lane text; v_min numeric; v_name text;
BEGIN
  SELECT c.lane, c.est_min_default, c.display_name INTO v_lane, v_min, v_name
    FROM public.service_cadence_policy c WHERE c.svc = p_s.service AND c.is_active LIMIT 1;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'svc', p_s.service, 'must_do', true, 'deferrable', false,
    'est_min', COALESCE(v_min, 10),
    'concurrency', CASE v_lane WHEN 'cabin' THEN 'cabin' WHEN 'exterior' THEN 'exterior' WHEN 'digital' THEN 'digital'
                               WHEN 'wash_bay' THEN 'bay' WHEN 'detail' THEN 'bay' WHEN 'service_bay' THEN 'bay' END,
    'requires_bay', CASE v_lane WHEN 'wash_bay' THEN 'wash_bay' WHEN 'detail' THEN 'detail'
                                WHEN 'service_bay' THEN 'service_bay' END,
    'stall_type_required', ottoq.ottoq_svc_to_stall_type(p_s.service, p_depot_id),
    'slot', CASE WHEN p_s.service = 'sensor_calibration' THEN 'dedicated_service' END,
    'carryover_eligible', false, 'confirm_required', false,
    'owner_requested', true, 'owner_added', true,
    'owner_setting_ids', jsonb_build_array(p_s.setting_id::text),
    'owner_command_id', p_s.command_id::text,
    'why', format('Requested by the car''s owner through its agent: %s, %s.', COALESCE(v_name, p_s.service),
                  CASE p_s.service_when WHEN 'now' THEN 'on this visit' WHEN 'next_return' THEN 'on its next return'
                                        ELSE 'on every return' END)));
END $fn$;

-- Put an order on a visit's atoms: unchanged if the order is already there; if the visit already has that service
-- (OTTO-Q found it needed, or did it already this visit) the order is noted on it and nothing is added -- the owner
-- asked for work the car is getting anyway; otherwise the order's atom is appended. must_do and deferrable of an atom
-- OTTO-Q wrote are never touched: under 0543 every open atom holds the car whatever its flags.
CREATE OR REPLACE FUNCTION ottoq.ottoq_owner_merge_atom(p_atoms jsonb, p_s public.ottoq_owner_settings, p_depot_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_atoms jsonb := CASE WHEN jsonb_typeof(p_atoms) = 'array' THEN p_atoms ELSE '[]'::jsonb END;
  v_id    text  := p_s.setting_id::text;
  v_out   jsonb := '[]'::jsonb;
  v_a     jsonb;
  v_found boolean := false;
BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
              WHERE jsonb_typeof(a -> 'owner_setting_ids') = 'array' AND (a -> 'owner_setting_ids') @> jsonb_build_array(v_id)) THEN
    RETURN v_atoms;
  END IF;
  FOR v_a IN SELECT a FROM jsonb_array_elements(v_atoms) WITH ORDINALITY t(a, o) ORDER BY o LOOP
    IF NOT v_found AND v_a ->> 'svc' = p_s.service AND COALESCE(v_a ->> 'status', 'pending') <> 'cancelled' THEN
      v_a := v_a || jsonb_build_object(
        'owner_requested', true,
        'owner_setting_ids', CASE WHEN jsonb_typeof(v_a -> 'owner_setting_ids') = 'array' THEN v_a -> 'owner_setting_ids'
                                  ELSE '[]'::jsonb END || jsonb_build_array(v_id));
      v_found := true;
    END IF;
    v_out := v_out || jsonb_build_array(v_a);
  END LOOP;
  IF v_found THEN
    RETURN v_out;
  END IF;
  RETURN v_atoms || jsonb_build_array(ottoq.ottoq_owner_service_atom(p_s, p_depot_id));
END $fn$;

-- Take an order off a visit's atoms: an atom the owner added for this order alone that has not started is removed;
-- anything else keeps its work and only loses the order's tag. A started service finishes (rule 9).
CREATE OR REPLACE FUNCTION ottoq.ottoq_owner_unmerge_atoms(p_atoms jsonb, p_setting_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT COALESCE(jsonb_agg(q.atom ORDER BY q.o), '[]'::jsonb)
    FROM (SELECT t.o,
                 CASE WHEN NOT t.tagged THEN t.a
                      WHEN jsonb_array_length((t.a -> 'owner_setting_ids') - p_setting_id::text) > 0
                        THEN t.a || jsonb_build_object('owner_setting_ids', (t.a -> 'owner_setting_ids') - p_setting_id::text)
                      --: no order left on it: the atom is as OTTO-Q wrote it (or, for a started owner atom, keeps only
                      --: owner_added and owner_command_id as its provenance)
                      ELSE t.a - 'owner_setting_ids' - 'owner_requested'
                 END AS atom,
                 (t.tagged AND jsonb_array_length((t.a -> 'owner_setting_ids') - p_setting_id::text) = 0
                  AND COALESCE((t.a ->> 'owner_added')::boolean, false)
                  AND COALESCE(t.a ->> 'status', 'pending') = 'pending') AS drop_it
            FROM (SELECT x.a, x.o,
                         (jsonb_typeof(x.a -> 'owner_setting_ids') = 'array'
                          AND (x.a -> 'owner_setting_ids') @> jsonb_build_array(p_setting_id::text)) AS tagged
                    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_atoms) = 'array' THEN p_atoms ELSE '[]'::jsonb END)
                         WITH ORDINALITY x(a, o)) t) q
   WHERE NOT q.drop_it
$fn$;

-- A new visit carries the owner's standing orders from its first row, whichever of the three inserters opens it
-- (derive, ottoq_add_fault_repair, the rider sweep), upserts included (EXCLUDED carries what this sets). Inert without
-- an active order for the car on the run: one index probe.
CREATE OR REPLACE FUNCTION public.ottoq_tg_owner_orders_on_new_visit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE r public.ottoq_owner_settings;
BEGIN
  IF NEW.sim_run_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.ottoq_owner_settings s
        WHERE s.vehicle_id = NEW.vehicle_id AND s.kind = 'service' AND s.status = 'active'
          AND s.sim_run_id = NEW.sim_run_id) THEN
    RETURN NEW;
  END IF;
  BEGIN
    FOR r IN SELECT * FROM public.ottoq_owner_settings s
              WHERE s.vehicle_id = NEW.vehicle_id AND s.kind = 'service' AND s.status = 'active'
                AND s.sim_run_id = NEW.sim_run_id
              ORDER BY s.set_at, s.setting_id LOOP
      IF ottoq.ottoq_owner_order_applies(r) THEN
        NEW.atoms := ottoq.ottoq_owner_merge_atom(NEW.atoms, r, COALESCE(NEW.depot_id, r.depot_id));
      END IF;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    --: a visit is never refused for an owner's order; the tick step puts any missed order on it at the next tick
    RAISE WARNING 'owner orders on a new visit for %: % %', NEW.vehicle_id, SQLSTATE, SQLERRM;
  END;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_visit_needs_owner_orders_trg
  BEFORE INSERT ON public.ottoq_visit_needs
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_tg_owner_orders_on_new_visit();

-- THE TICK STEP. Called from public.ottoq_sim_advance_tick_world before the visit-atom step, so a new limit binds the
-- charge that advances this tick and an in-place service starts this tick. Inert without owner settings on the run:
-- one index probe, no write, no event, no call -- which is every certification, dial and sweep arm (§6).
CREATE OR REPLACE FUNCTION ottoq.ottoq_owner_orders_tick(p_sim_run_id uuid, p_clock timestamptz)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  r          record;
  s          public.ottoq_owner_settings;
  v_depot    uuid;
  v_tgt      numeric;
  v_n        int;
  v_visit    record;
  v_new      jsonb;
  v_state    text;
  v_targets  int := 0;
  v_attached int := 0;
  v_removed  int := 0;
  v_closed   int := 0;
  v_cars     jsonb := '[]'::jsonb;
BEGIN
  IF p_sim_run_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.ottoq_owner_settings x
        WHERE x.sim_run_id = p_sim_run_id AND (x.status = 'active' OR x.pending_reconcile)) THEN
    RETURN 0;
  END IF;
  SELECT depot_id INTO v_depot FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;

  -- (1) charge limits made, replaced, withdrawn or undone: the car's target, its open visit's target and its charge
  -- atom go to the effective target (the one answer, 0539). The twin's charge advance re-reads vehicles.target_soc
  -- every tick, so a charge already past a new, lower limit stops in the advance that follows this step.
  FOR r IN SELECT DISTINCT x.vehicle_id FROM public.ottoq_owner_settings x
            WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'charge_limit' AND x.pending_reconcile
            ORDER BY x.vehicle_id LOOP
    v_tgt := public.ottoq_effective_target_soc_at(r.vehicle_id, p_clock);
    CONTINUE WHEN v_tgt IS NULL;
    UPDATE public.vehicles v SET target_soc = round(v_tgt)::int
     WHERE v.id = r.vehicle_id AND v.target_soc IS DISTINCT FROM round(v_tgt)::int;
    UPDATE public.ottoq_visit_needs vn
       SET target_soc = v_tgt,
           atoms = (SELECT COALESCE(jsonb_agg(CASE WHEN a ->> 'svc' = 'charge'
                                                    AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')
                                                   THEN a || jsonb_build_object('target_soc', v_tgt)
                                                   ELSE a END ORDER BY o), '[]'::jsonb)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY t(a, o))
     WHERE vn.vehicle_id = r.vehicle_id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
       AND (vn.target_soc IS DISTINCT FROM v_tgt
            OR EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                        WHERE a ->> 'svc' = 'charge' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')
                          AND (a ->> 'target_soc') IS DISTINCT FROM v_tgt::text));
    v_targets := v_targets + 1;
    v_cars := v_cars || jsonb_build_array(jsonb_build_object('vehicle_id', r.vehicle_id, 'target_soc', v_tgt));
  END LOOP;
  UPDATE public.ottoq_owner_settings x
     SET pending_reconcile = false, applied = x.applied || jsonb_build_object('reconciled_at_sim', p_clock)
   WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'charge_limit' AND x.pending_reconcile;

  -- (2) holds: read by the departure test as they stand; one whose time has come is closed
  UPDATE public.ottoq_owner_settings x
     SET status = 'fulfilled', closed_at = now(), closed_at_sim = p_clock, closed_reason = 'the hold time was reached',
         pending_reconcile = false
   WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'hold' AND x.status = 'active' AND x.hold_until_sim <= p_clock;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;
  UPDATE public.ottoq_owner_settings x
     SET pending_reconcile = false, applied = x.applied || jsonb_build_object('reconciled_at_sim', p_clock)
   WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'hold' AND x.pending_reconcile;

  -- (3a) service orders withdrawn, replaced, undone or lifted: off the open visits
  FOR s IN SELECT * FROM public.ottoq_owner_settings x
            WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'service' AND x.status <> 'active' AND x.pending_reconcile
            ORDER BY x.vehicle_id, x.set_at, x.setting_id LOOP
    UPDATE public.ottoq_visit_needs vn
       SET atoms = ottoq.ottoq_owner_unmerge_atoms(vn.atoms, s.setting_id)
     WHERE vn.vehicle_id = s.vehicle_id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE jsonb_typeof(a -> 'owner_setting_ids') = 'array'
                      AND (a -> 'owner_setting_ids') @> jsonb_build_array(s.setting_id::text));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_removed := v_removed + v_n;
    UPDATE public.ottoq_owner_settings x SET pending_reconcile = false WHERE x.setting_id = s.setting_id;
  END LOOP;

  -- (3b) one-shot orders whose service is done on any visit of this run: fulfilled
  UPDATE public.ottoq_owner_settings x
     SET status = 'fulfilled', closed_at = now(), closed_at_sim = p_clock, closed_reason = 'the service was done',
         pending_reconcile = false
   WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'service' AND x.status = 'active'
     AND x.service_when IN ('now', 'next_return')
     AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                  WHERE vn.vehicle_id = x.vehicle_id AND vn.sim_run_id = p_sim_run_id
                    AND jsonb_typeof(a -> 'owner_setting_ids') = 'array'
                    AND (a -> 'owner_setting_ids') @> jsonb_build_array(x.setting_id::text)
                    AND a ->> 'status' = 'done');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + v_n;

  -- (3c) active orders onto the car's open visit, when they apply to it. Converges: an order a re-derive dropped is
  -- put back, and one already there is left alone.
  FOR s IN SELECT * FROM public.ottoq_owner_settings x
            WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'service' AND x.status = 'active'
            ORDER BY x.vehicle_id, x.set_at, x.setting_id LOOP
    SELECT vn.visit_id, vn.atoms INTO v_visit
      FROM public.ottoq_visit_needs vn
     WHERE vn.vehicle_id = s.vehicle_id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
     ORDER BY vn.created_at DESC, vn.visit_key DESC
     LIMIT 1;
    IF v_visit.visit_id IS NOT NULL AND ottoq.ottoq_owner_order_applies(s) THEN
      v_new := ottoq.ottoq_owner_merge_atom(v_visit.atoms, s, COALESCE(v_depot, s.depot_id));
      IF v_new IS DISTINCT FROM v_visit.atoms THEN
        UPDATE public.ottoq_visit_needs vn SET atoms = v_new WHERE vn.visit_id = v_visit.visit_id;
        v_attached := v_attached + 1;
        v_cars := v_cars || jsonb_build_array(jsonb_build_object('vehicle_id', s.vehicle_id, 'service', s.service));
        -- a car holding at the depot gets the bay leg planned now; the planner refuses to re-plan an itinerary that
        -- still has planned legs, and 0543's departure recheck routes the car in any case before it can leave
        SELECT v.current_state::text INTO v_state FROM public.vehicles v WHERE v.id = s.vehicle_id;
        IF v_state IN ('staged_for_departure', 'charge_complete_holding', 'service_complete_holding',
                       'staged_awaiting_service') THEN
          BEGIN
            PERFORM public.ottoq_plan_visit_itinerary(p_sim_run_id, s.vehicle_id, p_clock);
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'owner order replan failed for %: % %', s.vehicle_id, SQLSTATE, SQLERRM;
          END;
        END IF;
      END IF;
      UPDATE public.ottoq_owner_settings x
         SET applied = x.applied || jsonb_build_object('visit_id', v_visit.visit_id, 'reconciled_at_sim', p_clock)
       WHERE x.setting_id = s.setting_id AND (x.applied ->> 'visit_id') IS DISTINCT FROM v_visit.visit_id::text;
    END IF;
    v_visit := NULL;
  END LOOP;
  UPDATE public.ottoq_owner_settings x SET pending_reconcile = false
   WHERE x.sim_run_id = p_sim_run_id AND x.kind = 'service' AND x.pending_reconcile;

  -- ONE summary event per tick that changed something (the rider sweep's discipline: event writes are the tick's
  -- known cost driver, 0012)
  IF v_targets + v_attached + v_removed + v_closed > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'owner_settings',
        p_event_type := 'ottoq.owner_settings_applied',
        p_entity_type := 'depot', p_entity_id := v_depot, p_depot_id := v_depot,
        p_payload := jsonb_build_object('retargeted', v_targets, 'orders_attached', v_attached,
                                        'orders_removed', v_removed, 'closed', v_closed, 'sim_clock', p_clock,
                                        'cars', v_cars,
                                        'doctrine', 'the owner decides what its cars need; OTTO-Q decides when and where'),
        p_severity := 'info', p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'owner settings summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  RETURN v_targets + v_attached + v_removed + v_closed;
EXCEPTION WHEN OTHERS THEN
  --: the tick goes on. Every setting this step did not reconcile stays pending and is retried next tick; a car with
  --: an order still pending waits at most one sim hour for it (public.ottoq_owner_departure_blocked).
  RAISE WARNING 'ottoq_owner_orders_tick FAILED SAFELY on run %: % %', p_sim_run_id, SQLSTATE, SQLERRM;
  RETURN 0;
END $fn$;

-- THE RUN'S END PUTS IT BACK. On the same transition that closes the run's needs (ottoq_sim_runs_close_needs), every
-- owner setting on the run is lifted, the cars that carried a limit go back to their target with none, and the commands
-- that made them say so. Never refuses the stop: a lift that failed leaves settings that no read applies (their run is
-- no longer live), and the next run's purge clears them.
CREATE OR REPLACE FUNCTION public.ottoq_tg_lift_owner_settings_on_terminal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE v_cars uuid[]; v_cmds uuid[]; v_clock timestamptz := COALESCE(NEW.sim_clock_current, now());
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s WHERE s.sim_run_id = NEW.sim_run_id AND s.status = 'active') THEN
    RETURN NULL;
  END IF;
  BEGIN
    WITH lifted AS (
      UPDATE public.ottoq_owner_settings s
         SET status = 'lifted', closed_at = now(), closed_at_sim = NEW.sim_clock_current,
             closed_reason = 'the run ended (' || NEW.status || ')', pending_reconcile = false
       WHERE s.sim_run_id = NEW.sim_run_id AND s.status = 'active'
      RETURNING s.vehicle_id, s.kind, s.command_id)
    SELECT array_agg(DISTINCT l.vehicle_id) FILTER (WHERE l.kind = 'charge_limit'), array_agg(DISTINCT l.command_id)
      INTO v_cars, v_cmds
      FROM lifted l;
    UPDATE public.vehicles v
       SET target_soc = round(public.ottoq_effective_target_soc_at(v.id, v_clock))::int
     WHERE v.id = ANY (COALESCE(v_cars, ARRAY[]::uuid[]))
       AND v.target_soc IS DISTINCT FROM round(public.ottoq_effective_target_soc_at(v.id, v_clock))::int;
    UPDATE public.ottoq_owner_commands c
       SET lifted_at = now(), lifted_reason = 'the run ended (' || NEW.status || ')'
     WHERE c.command_id = ANY (COALESCE(v_cmds, ARRAY[]::uuid[])) AND c.lifted_at IS NULL;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'lifting owner settings at the end of run % failed: % %', NEW.sim_run_id, SQLSTATE, SQLERRM;
  END;
  RETURN NULL;
END $fn$;

CREATE TRIGGER ottoq_sim_runs_lift_owner_settings
  AFTER UPDATE OF status ON public.ottoq_sim_runs
  FOR EACH ROW
  WHEN ((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text]))
        AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text])))
  EXECUTE FUNCTION public.ottoq_tg_lift_owner_settings_on_terminal();

-- ── the world step: one line, before the visit-atom step ──
DO $patch$
DECLARE
  c_anchor constant text := '  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);';
  c_step   constant text := $s$
  -- 0605: WHAT AN OWNER'S AGENT SET FOR ITS OWN CARS, applied at the tick (charge targets, service orders, holds),
  -- before the visit atoms advance and the charges advance. Inert on a run no owner touched: one index probe.
  PERFORM ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock);
$s$;
BEGIN
  EXECUTE replace(pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure),
                  c_anchor, c_step || c_anchor);
  PERFORM set_config('ottoq.m0605_step', c_step, true);   -- for V1, this transaction only
END $patch$;

-- ══ 7. the agent side: small helpers (internal: reachable only through ottoq_agent_call) ════════════════════════════

-- The OrchestrAV link every receipt carries: the run, the owner, the Fleet tab, and the command to highlight.
CREATE OR REPLACE FUNCTION public.ottoq_owner_app_link(p_sim_run_id uuid, p_fleet_operator_id uuid, p_command_id uuid)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT 'https://ottoyard-orchestra-av.lovable.app/?source=agent'
         || CASE WHEN p_sim_run_id IS NULL THEN '' ELSE '&run=' || p_sim_run_id::text END
         || '&owner=' || p_fleet_operator_id::text || '&tab=fleet'
         || CASE WHEN p_command_id IS NULL THEN '' ELSE '&command=' || p_command_id::text END
$fn$;

-- A time as the depot reads it: Nashville local time (CLAUDE.md rule 7). p_sim marks a SIM clock ("9:40 PM sim time"),
-- otherwise real time ("8:02 PM CT"); p_with_day adds the day.
CREATE OR REPLACE FUNCTION public.ottoq_owner_clock(p_ts timestamptz, p_sim boolean, p_with_day boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT CASE WHEN p_ts IS NULL THEN NULL ELSE
    to_char(p_ts AT TIME ZONE 'America/Chicago', 'FMHH12:MI AM')
    || CASE WHEN p_with_day THEN to_char(p_ts AT TIME ZONE 'America/Chicago', ' "on" Dy FMMon FMDD') ELSE '' END
    || CASE WHEN p_sim THEN ' sim time' ELSE ' CT' END END
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_state_phrase(p_state text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT CASE p_state
    WHEN 'offline'                  THEN 'parked and offline'
    WHEN 'deployed'                 THEN 'out on the road'
    WHEN 'en_route_to_depot'        THEN 'on its way back to the depot'
    WHEN 'arrived_at_gate'          THEN 'at the depot gate'
    WHEN 'staged_awaiting_service'  THEN 'parked in staging, waiting for its next step'
    WHEN 'charging_dcfc'            THEN 'fast-charging'
    WHEN 'charging_l2'              THEN 'charging on a Level 2 charger'
    WHEN 'charge_complete_holding'  THEN 'done charging, waiting for its next step'
    WHEN 'in_wash_bay'              THEN 'in the wash bay'
    WHEN 'in_detail_bay'            THEN 'in the detail bay'
    WHEN 'in_service_bay'           THEN 'in the service bay'
    WHEN 'service_complete_holding' THEN 'done with its service, waiting for its next step'
    WHEN 'staged_for_departure'     THEN 'staged to leave'
    WHEN 'en_route_to_deployment'   THEN 'leaving for work'
    WHEN 'emergency_staged'         THEN 'held for an emergency'
    WHEN 'tow_requested'            THEN 'waiting for a tow'
    WHEN 'out_of_service'           THEN 'out of service'
    ELSE COALESCE(replace(p_state, '_', ' '), 'in an unknown state') END
$fn$;

-- A catalog name inside a sentence: "Exterior wash" -> "exterior wash", "Mechanical PM" -> "mechanical PM".
CREATE OR REPLACE FUNCTION public.ottoq_owner_lc(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT lower(left(p_text, 1)) || substr(p_text, 2)
$fn$;

-- Where a car is, in one of seven groups an owner asks about.
CREATE OR REPLACE FUNCTION public.ottoq_owner_state_group(p_state text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT CASE
    WHEN p_state IN ('deployed', 'en_route_to_deployment') THEN 'on the road'
    WHEN p_state = 'en_route_to_depot' THEN 'heading back'
    WHEN p_state IN ('charging_dcfc', 'charging_l2') THEN 'charging'
    WHEN p_state IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay') THEN 'in a bay'
    WHEN p_state = 'staged_for_departure' THEN 'staged to leave'
    WHEN p_state IN ('arrived_at_gate', 'staged_awaiting_service', 'charge_complete_holding', 'service_complete_holding')
      THEN 'waiting at the depot'
    ELSE 'parked or offline' END
$fn$;

-- The services an owner may request, and the five it may not, with the reason. ONE list: the command, the catalog
-- read and V1 of the test read it from here.
CREATE OR REPLACE FUNCTION public.ottoq_owner_requestable_services()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT ARRAY['exterior_wash', 'interior_deep_clean', 'interior_tidy', 'interior_inspection', 'sensor_clean',
               'sensor_calibration', 'software_update', 'remote_diagnostics', 'mechanical_pm', 'cosmetic_repair',
               'item_retrieval']::text[]
$fn$;

-- A service named the way a person or an agent names it -> the engine's code, or NULL.
CREATE OR REPLACE FUNCTION public.ottoq_owner_service_code(p_text text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  WITH n AS (SELECT btrim(regexp_replace(regexp_replace(lower(COALESCE(p_text, '')), '[_\-]+', ' ', 'g'), '\s+', ' ', 'g')) AS t)
  SELECT COALESCE(
    (SELECT c.svc FROM public.service_cadence_policy c, n
      WHERE c.is_active AND (replace(c.svc, '_', ' ') = n.t OR lower(c.display_name) = n.t) LIMIT 1),
    (SELECT CASE
       WHEN n.t IN ('wash', 'car wash', 'exterior cleaning', 'external cleaning', 'exterior clean', 'outside wash',
                    'exterior washing', 'clean the outside') THEN 'exterior_wash'
       WHEN n.t IN ('detail', 'deep clean', 'interior detail', 'interior cleaning', 'interior clean', 'cabin deep clean',
                    'full detail') THEN 'interior_deep_clean'
       WHEN n.t IN ('tidy', 'cabin tidy', 'quick clean', 'interior tidy up') THEN 'interior_tidy'
       WHEN n.t IN ('inspection', 'cabin inspection') THEN 'interior_inspection'
       WHEN n.t IN ('sensor cleaning', 'clean sensors', 'sensors', 'lidar clean', 'camera clean') THEN 'sensor_clean'
       WHEN n.t IN ('calibration', 'adas calibration', 'calibrate sensors', 'sensor recalibration') THEN 'sensor_calibration'
       WHEN n.t IN ('software', 'ota', 'ota update', 'update', 'firmware update') THEN 'software_update'
       WHEN n.t IN ('diagnostics', 'diagnostic', 'remote diagnostic') THEN 'remote_diagnostics'
       WHEN n.t IN ('pm', 'maintenance', 'preventive maintenance', 'preventative maintenance', 'service bay',
                    'service bay visit', 'mechanical', 'mechanical maintenance', 'inspection and maintenance')
         THEN 'mechanical_pm'
       WHEN n.t IN ('cosmetic', 'body work', 'bodywork', 'dent repair', 'scratch repair') THEN 'cosmetic_repair'
       WHEN n.t IN ('lost item', 'lost and found', 'item', 'items', 'retrieve item', 'retrieve an item') THEN 'item_retrieval'
     END FROM n))
$fn$;

-- The owner's contract terms an agent works inside: [min, max] charge target (max under the fleet default), blocked
-- services. NULL when the operator has no active contract.
CREATE OR REPLACE FUNCTION public.ottoq_owner_contract(p_fleet_operator_id uuid, p_as_of timestamptz)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object(
           'contract', s.contract_reference, 'version', s.version,
           'min_charge_pct', COALESCE(s.min_charge_target_pct, 80),
           'max_charge_pct', LEAST(COALESCE(s.max_charge_target_pct, 100), public.ottoq_default_target_soc()),
           'blocked_services', COALESCE(to_jsonb(s.blocked_services), '[]'::jsonb))
    FROM public.ottoq_fleet_operator_slas s
   WHERE s.fleet_operator_id = p_fleet_operator_id AND s.status = 'active'
     AND s.effective_from <= COALESCE(p_as_of, now())
     AND (s.effective_until IS NULL OR s.effective_until > COALESCE(p_as_of, now()))
   ORDER BY s.version DESC
   LIMIT 1
$fn$;

-- The cars a token may command: its operator's, at its depot (home or current -- 0559's rule), active.
CREATE OR REPLACE FUNCTION public.ottoq_owner_fleet(p_agent public.ottoq_agent_principals)
 RETURNS SETOF public.vehicles
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT v.* FROM public.vehicles v
   WHERE p_agent.fleet_operator_id IS NOT NULL
     AND v.fleet_operator_id = p_agent.fleet_operator_id
     AND (v.home_depot_id = p_agent.depot_id OR v.current_depot_id = p_agent.depot_id)
     AND v.is_active
   ORDER BY v.display_name, v.id
$fn$;

-- "Tesla-AV-045", "AV-45", "45", "twin-sim-045", "RT 3", "Cybercab 2", a uuid, or "all" -> the cars, in the order
-- asked, each once. Matched ONLY inside the token's fleet at its depot: the same names exist at other depots, and a
-- car outside the scope reads exactly like one that does not exist. A name that matches nothing or more than one car
-- is refused with the fleet's own names, never guessed.
CREATE OR REPLACE FUNCTION public.ottoq_owner_resolve_vehicles(p_agent public.ottoq_agent_principals, p_ref jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_fleet jsonb;
  v_refs  text[];
  v_ref   text;
  v_hit   uuid[];
  v_out   uuid[] := ARRAY[]::uuid[];
  v_num   text;
  v_hint  text;
  v_names text;
  v_cands jsonb;
  v_brand text;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', f.id, 'name', COALESCE(f.display_name, f.id::text), 'av', f.av_api_vehicle_id,
           'norm', regexp_replace(lower(COALESCE(f.display_name, '')), '[^a-z0-9]', '', 'g'),
           'letters', regexp_replace(lower(COALESCE(f.display_name, '')), '[^a-z]', '', 'g'),
           'model', regexp_replace(lower(COALESCE(f.model, '')), '[^a-z]', '', 'g'),
           'num', CASE WHEN substring(f.display_name FROM '([0-9]{1,6})\s*$') IS NOT NULL
                       THEN substring(f.display_name FROM '([0-9]{1,6})\s*$')::int END)
           ORDER BY f.display_name, f.id), '[]'::jsonb)
    INTO v_fleet
    FROM public.ottoq_owner_fleet(p_agent) f;
  -- the words a person may put before a number: the fleet's own make(s) and generic words. Another make is NOT one of
  -- them: "Waymo-AV-001" must not find Tesla-AV-001.
  SELECT '^(' || COALESCE(string_agg(DISTINCT NULLIF(regexp_replace(lower(COALESCE(f.make, '')), '[^a-z]', '', 'g'), ''), '|'), 'x')
         || '|car|vehicle|unit|number|no|the)+'
    INTO v_brand FROM public.ottoq_owner_fleet(p_agent) f;
  -- the fleet's names, compactly, for every refusal
  SELECT string_agg(g.txt, '; ' ORDER BY g.first_name) INTO v_names
    FROM (SELECT min(x ->> 'name') AS first_name,
                 CASE WHEN count(*) = 1 THEN min(x ->> 'name')
                      ELSE min(x ->> 'name') || ' to ' || max(x ->> 'name') || ' (' || count(*) || ' cars)' END AS txt
            FROM jsonb_array_elements(v_fleet) x
           GROUP BY regexp_replace(x ->> 'name', '[0-9]+\s*$', '')) g;

  IF p_ref IS NULL OR jsonb_typeof(p_ref) = 'null' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'vehicles is required: "all", or a list of car names such as "Tesla-AV-045".';
  ELSIF jsonb_typeof(p_ref) = 'string' THEN
    v_refs := ARRAY[p_ref #>> '{}'];
  ELSIF jsonb_typeof(p_ref) = 'array' AND jsonb_array_length(p_ref) BETWEEN 1 AND 100
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_ref) e WHERE jsonb_typeof(e) <> 'string') THEN
    v_refs := ARRAY(SELECT e #>> '{}' FROM jsonb_array_elements(p_ref) e);
  ELSE
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'vehicles is "all" or a list of 1 to 100 car names.';
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(v_refs) r WHERE lower(btrim(r)) IN ('all', 'all cars', 'every car', 'fleet', 'my fleet')) THEN
    IF cardinality(v_refs) > 1 THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'Send "all" on its own, or a list of names.';
    END IF;
    IF jsonb_array_length(v_fleet) = 0 THEN
      RETURN jsonb_build_object('ok', false, 'code', 'no_cars_in_scope',
        'message', 'Your token''s fleet has no active cars at this depot.');
    END IF;
    RETURN jsonb_build_object('ok', true, 'all', true,
      'vehicles', (SELECT jsonb_agg(jsonb_build_object('id', x -> 'id', 'name', x -> 'name')) FROM jsonb_array_elements(v_fleet) x));
  END IF;

  FOREACH v_ref IN ARRAY v_refs LOOP
    v_ref := btrim(v_ref);
    IF v_ref = '' OR char_length(v_ref) > 64 THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'A car name is 1 to 64 characters.';
    END IF;
    v_hit := ARRAY[]::uuid[];
    IF v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      v_hit := ARRAY(SELECT (x ->> 'id')::uuid FROM jsonb_array_elements(v_fleet) x WHERE x ->> 'id' = lower(v_ref));
    ELSE
      -- exact: the name or the AV stack's id
      v_hit := ARRAY(SELECT (x ->> 'id')::uuid FROM jsonb_array_elements(v_fleet) x
                      WHERE lower(x ->> 'name') = lower(v_ref) OR lower(x ->> 'av') = lower(v_ref));
      -- the name without its punctuation
      IF cardinality(v_hit) = 0 THEN
        v_hit := ARRAY(SELECT (x ->> 'id')::uuid FROM jsonb_array_elements(v_fleet) x
                        WHERE x ->> 'norm' = regexp_replace(lower(v_ref), '[^a-z0-9]', '', 'g'));
      END IF;
      -- the number at its end, narrowed by any letters left after the brand ("AV-45", "RT 3", "Cybercab 2")
      IF cardinality(v_hit) = 0 THEN
        v_num := substring(v_ref FROM '([0-9]{1,6})\s*$');
        IF v_num IS NOT NULL THEN
          v_hint := regexp_replace(regexp_replace(lower(v_ref), '[^a-z]', '', 'g'), v_brand, '');
          v_hit := ARRAY(SELECT (x ->> 'id')::uuid FROM jsonb_array_elements(v_fleet) x
                          WHERE (x ->> 'num')::int = v_num::int
                            AND (v_hint = '' OR position(v_hint IN x ->> 'letters') > 0
                                 OR position(v_hint IN x ->> 'model') > 0));
        END IF;
      END IF;
    END IF;
    IF cardinality(v_hit) = 0 THEN
      SELECT COALESCE(jsonb_agg(c.name ORDER BY c.d, c.name), '[]'::jsonb) INTO v_cands
        FROM (SELECT x ->> 'name' AS name,
                     abs(COALESCE((x ->> 'num')::int, 0) - COALESCE(substring(v_ref FROM '([0-9]{1,6})\s*$')::int, 0)) AS d
                FROM jsonb_array_elements(v_fleet) x
               ORDER BY 2, 1 LIMIT 3) c;
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found', 'ref', v_ref,
        'message', format('No car in your fleet matches "%s". Your cars here: %s.', v_ref, COALESCE(v_names, 'none')),
        'candidates', v_cands);
    END IF;
    IF cardinality(v_hit) > 1 THEN
      RETURN jsonb_build_object('ok', false, 'code', 'vehicle_ambiguous', 'ref', v_ref,
        'message', format('"%s" matches %s cars: %s. Name one.', v_ref, cardinality(v_hit),
                          (SELECT string_agg(x ->> 'name', ', ' ORDER BY x ->> 'name') FROM jsonb_array_elements(v_fleet) x
                            WHERE (x ->> 'id')::uuid = ANY (v_hit))),
        'candidates', (SELECT jsonb_agg(x ->> 'name' ORDER BY x ->> 'name') FROM jsonb_array_elements(v_fleet) x
                        WHERE (x ->> 'id')::uuid = ANY (v_hit)));
    END IF;
    IF NOT (v_hit[1] = ANY (v_out)) THEN
      v_out := v_out || v_hit[1];
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'all', false,
    'vehicles', (SELECT jsonb_agg(jsonb_build_object('id', x -> 'id', 'name', x -> 'name') ORDER BY array_position(v_out, (x ->> 'id')::uuid))
                   FROM jsonb_array_elements(v_fleet) x WHERE (x ->> 'id')::uuid = ANY (v_out)));
END $fn$;

-- "36 Teslas" / "Tesla-AV-045" / "5 cars": the cars a command names, the way a person says it.
CREATE OR REPLACE FUNCTION public.ottoq_owner_cars_phrase(p_cars jsonb, p_all boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  WITH c AS (SELECT (x ->> 'id')::uuid AS id, x ->> 'name' AS name FROM jsonb_array_elements(COALESCE(p_cars, '[]'::jsonb)) x),
       m AS (SELECT count(*) AS n, count(DISTINCT lower(v.make)) AS makes, min(v.make) AS make, min(c.name) AS one
               FROM c LEFT JOIN public.vehicles v ON v.id = c.id)
  SELECT CASE WHEN m.n = 1 THEN m.one
              WHEN m.makes = 1 AND m.make IS NOT NULL
                THEN CASE WHEN p_all THEN 'all ' ELSE '' END || m.n || ' ' || m.make || 's'
              ELSE CASE WHEN p_all THEN 'all ' ELSE '' END || m.n || ' cars' END
    FROM m
$fn$;

-- Where a service is done, in plain words.
CREATE OR REPLACE FUNCTION public.ottoq_owner_service_where(p_service text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT CASE c.lane
           WHEN 'wash_bay'    THEN 'in the wash bay'
           WHEN 'detail'      THEN 'in the wash bay''s detail lane'
           WHEN 'service_bay' THEN 'in the service bay'
           WHEN 'cabin'       THEN 'in the cabin, by a technician at the car'
           WHEN 'exterior'    THEN 'at the car, by a technician'
           WHEN 'digital'     THEN 'over the air, at the car'
           ELSE 'at the depot' END
    FROM public.service_cadence_policy c WHERE c.svc = p_service AND c.is_active LIMIT 1
$fn$;

-- One summary from a headline, the per-car effects grouped by what happens now, and a closing line.
CREATE OR REPLACE FUNCTION public.ottoq_owner_summarize(p_head text, p_effects jsonb, p_tail text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $fn$
  SELECT upper(left(COALESCE(p_head, ''), 1)) || substr(COALESCE(p_head, ''), 2)
         || CASE WHEN jsonb_array_length(COALESCE(p_effects, '[]'::jsonb)) = 1
                 THEN CASE WHEN COALESCE(p_head, '') = '' THEN '' ELSE ' ' END || (p_effects -> 0 ->> 'now')
                 WHEN jsonb_array_length(COALESCE(p_effects, '[]'::jsonb)) > 1
                 THEN COALESCE((SELECT string_agg(E'\n- ' || g.n || ' ' || CASE WHEN g.n = 1 THEN g.one ELSE g.many END, ''
                                                  ORDER BY g.n DESC, g.grp)
                                  FROM (SELECT e ->> 'group' AS grp, count(*) AS n,
                                               min(e ->> 'group_one') AS one, min(e ->> 'group_many') AS many
                                          FROM jsonb_array_elements(p_effects) e GROUP BY 1) g), '')
                 ELSE '' END
         || CASE WHEN COALESCE(p_tail, '') = '' THEN '' ELSE E'\n' || p_tail END
$fn$;

-- One car's charge-limit change, in plain words. p_before / p_after are the car's effective targets on this run.
CREATE OR REPLACE FUNCTION public.ottoq_owner_limit_effect(p_v public.vehicles, p_before numeric, p_after numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_name  text := COALESCE(p_v.display_name, p_v.id::text);
  v_state text := p_v.current_state::text;
  v_soc   numeric := p_v.current_soc;
  v_grp   text;
  v_one   text;
  v_many  text;
  v_now   text;
BEGIN
  IF p_before = p_after THEN
    v_grp := 'unchanged'; v_now := format('%s already charges to %s%%; nothing changes.', v_name, p_after);
    v_one := format('car already charges to %s%%', p_after); v_many := format('cars already charge to %s%%', p_after);
  ELSIF v_state IN ('charging_dcfc', 'charging_l2') AND p_after < p_before AND v_soc IS NOT NULL AND v_soc >= p_after - 0.5 THEN
    v_grp := 'stops_now'; v_now := format('%s is charging at %s%%, already at or past %s%%: its charge ends at the next tick.', v_name, v_soc, p_after);
    v_one := format('is charging past %s%%: its charge ends at the next tick', p_after);
    v_many := format('are charging past %s%%: their charges end at the next tick', p_after);
  ELSIF v_state IN ('charging_dcfc', 'charging_l2') THEN
    v_grp := 'charging'; v_now := format('%s is charging (now %s%%) and will stop at %s%%.', v_name, COALESCE(v_soc::text, '?'), p_after);
    v_one := format('is charging and will stop at %s%%', p_after); v_many := format('are charging and will stop at %s%%', p_after);
  ELSIF v_state IN ('deployed', 'en_route_to_deployment', 'en_route_to_depot') THEN
    v_grp := 'out'; v_now := format('%s is %s; it charges to %s%% when it next comes in.', v_name, public.ottoq_owner_state_phrase(v_state), p_after);
    v_one := format('is out; it charges to %s%% when it next comes in', p_after);
    v_many := format('are out; they charge to %s%% when they next come in', p_after);
  ELSIF v_state IN ('offline', 'out_of_service', 'tow_requested', 'emergency_staged') THEN
    v_grp := 'idle'; v_now := format('%s is %s; %s%% applies to its next charge.', v_name, public.ottoq_owner_state_phrase(v_state), p_after);
    v_one := format('is parked or offline; %s%% applies to its next charge', p_after);
    v_many := format('are parked or offline; %s%% applies to their next charge', p_after);
  ELSIF v_soc IS NOT NULL AND v_soc >= p_after - 1 THEN
    v_grp := 'enough'; v_now := format('%s is at %s%%, enough for %s%%: it needs no more charge to leave.', v_name, v_soc, p_after);
    v_one := format('already has enough charge for %s%%', p_after); v_many := format('already have enough charge for %s%%', p_after);
  ELSE
    v_grp := 'will_charge'; v_now := format('%s is at %s%% and will charge to %s%% before it leaves.', v_name, COALESCE(v_soc::text, '?'), p_after);
    v_one := format('will charge to %s%% before it leaves', p_after); v_many := format('will charge to %s%% before they leave', p_after);
  END IF;
  RETURN jsonb_build_object('vehicle_id', p_v.id, 'vehicle', v_name, 'state', v_state, 'soc', v_soc,
    'before', p_before, 'after', p_after, 'change', p_before <> p_after,
    'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now);
END $fn$;

-- The reply an agent gets for a command, from its evidence row: the summary, the link, the receipt, and the next
-- move (confirm a preview, undo an apply).
CREATE OR REPLACE FUNCTION public.ottoq_owner_command_reply(p_c public.ottoq_owner_commands, p_duplicate boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'outcome', p_c.outcome,
    'duplicate', p_duplicate,
    'summary', p_c.summary,
    'link', p_c.link,
    'refusal', p_c.refusal,
    'command', jsonb_build_object(
      'command_id', p_c.command_id, 'tool', p_c.tool, 'mode', p_c.mode, 'outcome', p_c.outcome,
      'cars', jsonb_array_length(p_c.vehicles), 'vehicles', p_c.vehicles, 'effects', p_c.effects,
      'args', p_c.args, 'plan_hash', p_c.plan_hash, 'sim_run_id', p_c.sim_run_id,
      'sim_clock', p_c.sim_clock, 'sim_clock_local', public.ottoq_owner_clock(p_c.sim_clock, true),
      'created_at', p_c.created_at, 'created_at_local', public.ottoq_owner_clock(p_c.created_at, false),
      'undone_at', p_c.undone_at, 'undone_by_command_id', p_c.undone_by_command_id,
      'lifted_at', p_c.lifted_at, 'lifted_reason', p_c.lifted_reason),
    'confirm', CASE WHEN p_c.outcome = 'previewed' THEN jsonb_build_object(
                 'tool', p_c.tool,
                 -- what the preview showed, exactly: a hold goes back as the absolute time it resolved to, so a
                 -- confirm sent after the sim clock moved holds until the time shown, not "90 minutes from now"
                 'args', (p_c.args - 'mode' - 'expect_plan_hash' - 'idempotency_key' - 'until_sim'
                          - CASE WHEN p_c.args ? 'until_sim' THEN ARRAY['until', 'for_minutes'] ELSE ARRAY[]::text[] END)
                         || CASE WHEN p_c.args ? 'until_sim' THEN jsonb_build_object('until', p_c.args ->> 'until_sim')
                                 ELSE '{}'::jsonb END
                         || jsonb_build_object('mode', 'apply', 'expect_plan_hash', p_c.plan_hash),
                 'note', 'Send this to apply exactly the plan shown. If the cars or settings change first, OTTO-Q refuses with the new plan.') END,
    'undo', CASE WHEN p_c.outcome = 'applied' AND p_c.undone_at IS NULL AND p_c.lifted_at IS NULL AND p_c.tool <> 'undo_command'
                 THEN jsonb_build_object('tool', 'undo_command', 'args', jsonb_build_object('command_id', p_c.command_id)) END,
    'expires', CASE WHEN p_c.outcome = 'applied' AND p_c.tool <> 'undo_command'
                    THEN 'Lasts until this demo run ends or you undo it; a stop or reset of the twin puts every car back to baseline.' END))
$fn$;

-- ══ 8. the commands ═════════════════════════════════════════════════════════════════════════════════════════════════
--
-- One function for the seven commands, so every one shares the same order of checks:
--   argument shapes (OQA01: refused, ledgered by the dispatcher, not recorded here)
--   -> the same idempotency key replays the first command
--   -> the cars, by name, inside the token's scope
--   -> the owner's contract and OTTO-Q's rules (refused and RECORDED: a refusal is evidence too)
--   -> a live demo run (refused and recorded otherwise)
--   -> the plan: every car's before -> after and what happens now, and its hash
--   -> preview: recorded and returned | apply: refused if the plan is not the one previewed (expect_plan_hash),
--      no_change if nothing changes, else the settings are written and the engine applies them at its next tick.
CREATE OR REPLACE FUNCTION public.ottoq_owner_command(p_agent public.ottoq_agent_principals, p_tool text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_tool     text := lower(btrim(COALESCE(p_tool, '')));
  v_args     jsonb := COALESCE(p_args, '{}'::jsonb);
  v_mode     text := lower(COALESCE(NULLIF(btrim(COALESCE(p_args ->> 'mode', '')), ''), 'apply'));
  v_expect   text := NULLIF(lower(btrim(COALESCE(p_args ->> 'expect_plan_hash', ''))), '');
  v_idem     text := NULLIF(btrim(COALESCE(p_args ->> 'idempotency_key', '')), '');
  v_note     text := NULLIF(btrim(COALESCE(p_args ->> 'note', '')), '');
  v_run      jsonb;
  v_run_id   uuid;
  v_clock    timestamptz;
  v_run_end  timestamptz;
  v_demo     boolean;
  v_contract jsonb;
  v_ceiling  numeric;
  v_res      jsonb;
  v_all      boolean := false;
  v_cars     jsonb := '[]'::jsonb;
  v_effects  jsonb := '[]'::jsonb;
  v_e        jsonb;
  v_refusal  jsonb;
  v_head     text;
  v_tail     text;
  v_summary  text;
  v_hash     text;
  v_norm     jsonb;
  v_changed  int := 0;
  v_cmd      public.ottoq_owner_commands;
  v_target   public.ottoq_owner_commands;
  v_veh      public.vehicles;
  v_old      public.ottoq_owner_settings;
  v_set      public.ottoq_owner_settings;
  v_pct      numeric;
  v_before   numeric;
  v_after    numeric;
  v_service  text;
  v_svc_name text;
  v_svc_min  numeric;
  v_when     text;
  v_incl     boolean;
  v_until    timestamptz;
  v_minutes  int;
  v_atom     jsonb;
  v_grp      text;
  v_now      text;
  v_one      text;
  v_many     text;
  v_car      jsonb;
  v_cphrase  text;
BEGIN
  -- ── shapes ──
  IF v_tool NOT IN ('set_charge_limit', 'clear_charge_limit', 'request_service', 'cancel_service', 'hold_vehicle',
                    'release_hold', 'undo_command') THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'unknown_tool', DETAIL = format('No owner command named %s.', v_tool);
  END IF;
  IF jsonb_typeof(v_args) <> 'object' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'arguments must be a JSON object.';
  END IF;
  IF v_mode NOT IN ('apply', 'preview') THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'mode is apply (the default) or preview.';
  END IF;
  IF v_expect IS NOT NULL AND v_expect !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
      DETAIL = 'expect_plan_hash is the 32-character plan_hash a preview returned.';
  END IF;
  IF v_idem IS NOT NULL AND v_idem !~ '^[A-Za-z0-9._:-]{1,100}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'idempotency_key is 1 to 100 of A-Z a-z 0-9 . _ : -';
  END IF;
  IF v_note IS NOT NULL AND char_length(v_note) > 500 THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'note is at most 500 characters.';
  END IF;
  IF p_agent.fleet_operator_id IS NULL OR NOT ('owner_settings' = ANY (p_agent.capabilities)) THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA03', MESSAGE = 'capability_missing',
      DETAIL = 'Owner commands need a token bound to one fleet with the owner_settings capability.';
  END IF;

  v_run := public.ottoq_agent_live_run(p_agent.depot_id);
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_clock := (v_run ->> 'sim_clock')::timestamptz;
  v_demo := v_run IS NOT NULL AND v_run ->> 'run_by' = 'operator_demo';
  IF v_run_id IS NOT NULL THEN
    SELECT r.sim_clock_end INTO v_run_end FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run_id;
  END IF;
  v_contract := public.ottoq_owner_contract(p_agent.fleet_operator_id, COALESCE(v_clock, now()));
  v_ceiling := COALESCE((v_contract ->> 'max_charge_pct')::numeric, public.ottoq_default_target_soc());
  v_norm := jsonb_build_object('mode', v_mode);

  -- ── the arguments each command takes (shapes: OQA01) ──
  IF v_tool = 'set_charge_limit' THEN
    IF NOT (v_args ? 'percent') OR NOT ((jsonb_typeof(v_args -> 'percent') = 'number' AND (v_args ->> 'percent') ~ '^[0-9]{1,3}(\.0+)?$')
                                        OR (jsonb_typeof(v_args -> 'percent') = 'string' AND btrim(v_args ->> 'percent') ~ '^[0-9]{1,3}%?$')) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'percent is required: a whole number, the most a car charges to (for example 90).';
    END IF;
    v_pct := replace(btrim(v_args ->> 'percent'), '%', '')::numeric;
    v_norm := v_norm || jsonb_build_object('percent', v_pct);
  ELSIF v_tool IN ('request_service', 'cancel_service') THEN
    IF v_tool = 'request_service' AND NULLIF(btrim(COALESCE(v_args ->> 'service', '')), '') IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'service is required, for example exterior_wash or mechanical_pm.';
    END IF;
    IF NULLIF(btrim(COALESCE(v_args ->> 'service', '')), '') IS NOT NULL THEN
      v_service := public.ottoq_owner_service_code(v_args ->> 'service');
      v_norm := v_norm || jsonb_build_object('service', COALESCE(v_service, v_args ->> 'service'));
    END IF;
    IF v_tool = 'request_service' THEN
      v_when := lower(COALESCE(NULLIF(btrim(COALESCE(v_args ->> 'when', '')), ''), 'now'));
      v_when := CASE WHEN v_when IN ('now', 'this_visit', 'this visit', 'today') THEN 'now'
                     WHEN v_when IN ('next_return', 'next return', 'next_visit', 'next visit', 'next') THEN 'next_return'
                     WHEN v_when IN ('every_return', 'every return', 'every_visit', 'every visit', 'always', 'standing') THEN 'every_return'
                     ELSE NULL END;
      IF v_when IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'when is now (default), next_return or every_return.';
      END IF;
      IF v_args ? 'include_current_visit' AND jsonb_typeof(v_args -> 'include_current_visit') <> 'boolean' THEN
        RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'include_current_visit is true or false.';
      END IF;
      v_incl := CASE WHEN v_when = 'every_return' THEN COALESCE((v_args ->> 'include_current_visit')::boolean, true) END;
      v_norm := v_norm || jsonb_strip_nulls(jsonb_build_object('when', v_when, 'include_current_visit', v_incl));
    END IF;
  ELSIF v_tool = 'hold_vehicle' THEN
    IF (v_args ? 'until') = (v_args ? 'for_minutes') THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'Give exactly one of until (a sim time such as "06:00" or an ISO timestamp) or for_minutes (1 to 1440).';
    END IF;
    IF v_args ? 'for_minutes' THEN
      v_minutes := public.ottoq_agent_arg_int(v_args, 'for_minutes', NULL, 1, 1440);
      v_norm := v_norm || jsonb_build_object('for_minutes', v_minutes);
    ELSE
      IF jsonb_typeof(v_args -> 'until') <> 'string' OR char_length(v_args ->> 'until') > 40 THEN
        RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'until is a time: "06:00", "6:00 AM" or an ISO timestamp.';
      END IF;
      v_norm := v_norm || jsonb_build_object('until', btrim(v_args ->> 'until'));
    END IF;
  ELSIF v_tool = 'undo_command' THEN
    IF public.ottoq_agent_arg_uuid(v_args, 'command_id') IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'command_id is required: the id a command''s receipt gave.';
    END IF;
    v_norm := v_norm || jsonb_build_object('command_id', public.ottoq_agent_arg_uuid(v_args, 'command_id'));
  END IF;
  IF v_note IS NOT NULL THEN v_norm := v_norm || jsonb_build_object('note', v_note); END IF;

  -- ── the same key is the same command: a retry replays it instead of acting twice. A key sent again with a DIFFERENT
  -- command is refused, not answered with the first command's receipt: a client that reuses a key by mistake must not
  -- be told its new command was done (draft-ietf-httpapi-idempotency-key-header-07, 2025-10-15, "Error Scenarios": "If
  -- there is an attempt to reuse an idempotency key with a different request payload, the resource SHOULD reply with a
  -- HTTP 422 status code", https://www.ietf.org/archive/id/draft-ietf-httpapi-idempotency-key-header-07.html). The
  -- payload compared is the normalized one, so "service bay" and "mechanical_pm" are the same command; mode and note are
  -- not part of it, and until_sim is what the first command derived from its own until. ──
  IF v_idem IS NOT NULL AND v_mode = 'apply' THEN
    SELECT * INTO v_cmd FROM public.ottoq_owner_commands c
     WHERE c.principal_id = p_agent.principal_id AND c.idempotency_key = v_idem;
    IF FOUND THEN
      IF v_cmd.tool IS DISTINCT FROM v_tool
         OR (v_cmd.args - 'mode' - 'note' - 'until_sim')
            IS DISTINCT FROM ((v_norm - 'mode' - 'note')
                              || CASE WHEN v_tool <> 'undo_command' THEN jsonb_build_object('vehicles', v_args -> 'vehicles')
                                      ELSE '{}'::jsonb END) THEN
        RAISE EXCEPTION USING ERRCODE = 'OQA22', MESSAGE = 'idempotency_key_reused',
          DETAIL = format('idempotency_key "%s" was already used for a different command (%s, sent at %s). Nothing was done; a new command needs a new key.',
                          v_idem, replace(v_cmd.tool, '_', ' '), public.ottoq_owner_clock(v_cmd.created_at, false));
      END IF;
      RETURN public.ottoq_owner_command_reply(v_cmd, true);
    END IF;
  END IF;

  -- ── the cars ──
  IF v_tool <> 'undo_command' THEN
    v_res := public.ottoq_owner_resolve_vehicles(p_agent, v_args -> 'vehicles');
    v_norm := v_norm || jsonb_build_object('vehicles', v_args -> 'vehicles');
    IF NOT COALESCE((v_res ->> 'ok')::boolean, false) THEN
      v_refusal := jsonb_build_object('code', v_res ->> 'code', 'message', v_res ->> 'message', 'candidates', v_res -> 'candidates');
    ELSE
      v_cars := v_res -> 'vehicles';
      v_all := COALESCE((v_res ->> 'all')::boolean, false);
    END IF;
  END IF;
  v_cphrase := public.ottoq_owner_cars_phrase(v_cars, v_all);

  -- ── the owner's contract and OTTO-Q's rules ──
  IF v_refusal IS NULL AND v_tool = 'set_charge_limit' THEN
    IF v_contract IS NULL THEN
      v_refusal := jsonb_build_object('code', 'no_contract', 'message', 'Your fleet has no active contract on file, so OTTO-Q has no range to set a charge limit in.');
    ELSIF v_pct < (v_contract ->> 'min_charge_pct')::numeric THEN
      v_refusal := jsonb_build_object('code', 'below_contract_minimum',
        'message', format('%s%% is below the %s%% minimum in your contract. Choose %s%% to %s%%.', v_pct,
                          v_contract ->> 'min_charge_pct', v_contract ->> 'min_charge_pct', v_ceiling),
        'hint', format('Your contract%s sets the range a charge limit can take: %s%% to %s%%.',
                       COALESCE(' (' || (v_contract ->> 'contract') || ')', ''), v_contract ->> 'min_charge_pct', v_ceiling));
    ELSIF v_pct > v_ceiling THEN
      v_refusal := jsonb_build_object('code', 'above_ceiling',
        'message', format('%s%% is more than a car charges to (%s%%). Choose %s%% to %s%%.', v_pct, v_ceiling,
                          v_contract ->> 'min_charge_pct', v_ceiling));
    END IF;
  ELSIF v_refusal IS NULL AND v_tool IN ('request_service', 'cancel_service') AND v_args ? 'service' THEN
    IF v_service IS NULL THEN
      v_refusal := jsonb_build_object('code', 'unknown_service',
        'message', format('OTTO-Q has no service called "%s". You can request: %s.', v_args ->> 'service',
                          (SELECT string_agg(lower(c.display_name), ', ' ORDER BY c.display_name)
                             FROM public.service_cadence_policy c
                            WHERE c.svc = ANY (public.ottoq_owner_requestable_services()) AND c.is_active)));
    ELSIF v_tool = 'request_service' AND NOT (v_service = ANY (public.ottoq_owner_requestable_services())) THEN
      v_refusal := jsonb_build_object('code', 'service_not_requestable',
        'message', CASE v_service
          WHEN 'charge'               THEN 'Charging is not requested: every car charges to its target on every visit. To change how full, set a charge limit.'
          WHEN 'readiness_check'      THEN 'The readiness check is OTTO-Q''s own gate: every car passes it before it leaves.'
          WHEN 'triage_check'         THEN 'A triage check is how OTTO-Q confirms a need it is unsure of; it adds one itself when it needs one.'
          WHEN 'fault_repair'         THEN 'A fault repair follows a fault: a faulted car is repaired before it charges or leaves. To have a car looked over, request mechanical_pm.'
          WHEN 'perimeter_walkaround' THEN 'The perimeter walkaround is the depot''s own night round.'
          ELSE format('%s is not a service an owner requests.', v_service) END);
    ELSIF v_tool = 'request_service' AND (v_contract -> 'blocked_services') ? v_service THEN
      v_refusal := jsonb_build_object('code', 'service_blocked_by_contract',
        'message', format('Your contract blocks %s at this depot.', v_service));
    END IF;
  END IF;

  -- ── a live demo run: owner settings live on one, and end with it ──
  IF v_refusal IS NULL AND NOT v_demo THEN
    v_refusal := jsonb_build_object('code', 'no_live_demo',
      'message', CASE WHEN v_run IS NULL THEN 'No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies to that run and resets when it ends.'
                      ELSE 'The live run at the twin depot is not a demo run, and owner settings apply only to demo runs.' END);
  END IF;

  -- ── the plan, per command: every car's before -> after, and what happens now ──
  IF v_refusal IS NULL AND v_tool IN ('set_charge_limit', 'clear_charge_limit') THEN
    v_pct := CASE WHEN v_tool = 'set_charge_limit' THEN LEAST(v_pct, v_ceiling) ELSE v_ceiling END;
    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP
      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> 'id')::uuid;
      v_old := NULL;
      SELECT * INTO v_old FROM public.ottoq_owner_settings o
       WHERE o.sim_run_id = v_run_id AND o.vehicle_id = v_veh.id AND o.kind = 'charge_limit' AND o.status = 'active'
       FOR UPDATE;
      v_before := LEAST(v_ceiling, COALESCE(v_old.charge_limit_pct, v_ceiling));
      v_effects := v_effects || jsonb_build_array(public.ottoq_owner_limit_effect(v_veh, v_before, v_pct)
                                                  || jsonb_build_object('key', 'charge_limit'));
    END LOOP;
    v_head := CASE WHEN v_tool = 'set_charge_limit' AND v_pct < v_ceiling
                   THEN format('%s %s to at most %s%% instead of %s%%.', v_cphrase,
                               CASE WHEN jsonb_array_length(v_cars) = 1 THEN 'charges' ELSE 'charge' END, v_pct, v_ceiling)
                   ELSE format('%s %s to the full %s%% again.', v_cphrase,
                               CASE WHEN jsonb_array_length(v_cars) = 1 THEN 'charges' ELSE 'charge' END, v_ceiling) END;

  ELSIF v_refusal IS NULL AND v_tool = 'request_service' THEN
    SELECT c.display_name, c.est_min_default INTO v_svc_name, v_svc_min
      FROM public.service_cadence_policy c WHERE c.svc = v_service AND c.is_active;
    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP
      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> 'id')::uuid;
      v_old := NULL;
      SELECT * INTO v_old FROM public.ottoq_owner_settings o
       WHERE o.sim_run_id = v_run_id AND o.vehicle_id = v_veh.id AND o.kind = 'service' AND o.service = v_service
         AND o.status = 'active'
       FOR UPDATE;
      v_atom := NULL;
      SELECT a INTO v_atom
        FROM (SELECT vn.atoms FROM public.ottoq_visit_needs vn
               WHERE vn.vehicle_id = v_veh.id AND vn.sim_run_id = v_run_id AND vn.status IN ('open', 'in_progress')
               ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) w
        CROSS JOIN LATERAL jsonb_array_elements(w.atoms) a
       WHERE a ->> 'svc' = v_service AND COALESCE(a ->> 'status', 'pending') <> 'cancelled'
       LIMIT 1;
      IF v_old.setting_id IS NOT NULL AND v_old.service_when = v_when
         AND COALESCE(v_old.include_current_visit, true) = COALESCE(v_incl, true) THEN
        v_grp := 'already_ordered';
        v_now := format('%s already has this order.', v_veh.display_name);
        v_one := 'already has this order'; v_many := 'already have this order';
      ELSIF v_when = 'next_return' OR (v_when = 'every_return' AND NOT v_incl) THEN
        v_grp := 'next_return';
        v_now := format('%s gets %s %s.', v_veh.display_name, public.ottoq_owner_lc(v_svc_name),
                        CASE WHEN v_when = 'next_return' THEN 'on its next return' ELSE 'on every return after it next leaves' END);
        v_one := 'gets it from its next return'; v_many := 'get it from their next return';
      ELSIF v_atom IS NOT NULL AND v_atom ->> 'status' = 'done' THEN
        v_grp := 'done_already';
        v_now := format('%s already had %s on this visit%s.', v_veh.display_name, public.ottoq_owner_lc(v_svc_name),
                        CASE WHEN v_when = 'every_return' THEN ', and gets one on every return from now on' ELSE '' END);
        v_one := 'already had it on this visit'; v_many := 'already had it on this visit';
      ELSIF v_atom IS NOT NULL THEN
        v_grp := 'already_planned';
        v_now := format('%s already has %s planned on this visit, because OTTO-Q found it needed; it is noted as yours too.',
                        v_veh.display_name, public.ottoq_owner_lc(v_svc_name));
        v_one := 'already has it planned on this visit'; v_many := 'already have it planned on this visit';
      ELSIF EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                     WHERE vn.vehicle_id = v_veh.id AND vn.sim_run_id = v_run_id AND vn.status IN ('open', 'in_progress')) THEN
        v_grp := 'added_now';
        v_now := format('%s gets %s on this visit (%s, about %s min); OTTO-Q fits it into the car''s plan, and the car does not leave until it is done.',
                        v_veh.display_name, public.ottoq_owner_lc(v_svc_name), public.ottoq_owner_service_where(v_service), v_svc_min);
        v_one := 'is at the depot and gets it on this visit'; v_many := 'are at the depot and get it on this visit';
      ELSIF v_veh.current_state::text IN ('deployed', 'en_route_to_deployment', 'en_route_to_depot') THEN
        v_grp := 'on_return';
        v_now := format('%s is %s; it gets %s when it next comes in.', v_veh.display_name,
                        public.ottoq_owner_state_phrase(v_veh.current_state::text), public.ottoq_owner_lc(v_svc_name));
        v_one := 'is out and gets it when it comes in';
        v_many := 'are out and get it when they come in';
      ELSE
        v_grp := 'next_visit';
        v_now := format('%s is %s; it gets %s on its next visit.', v_veh.display_name,
                        public.ottoq_owner_state_phrase(v_veh.current_state::text), public.ottoq_owner_lc(v_svc_name));
        v_one := 'gets it on its next visit'; v_many := 'get it on their next visit';
      END IF;
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'vehicle_id', v_veh.id, 'vehicle', v_veh.display_name, 'state', v_veh.current_state::text, 'soc', v_veh.current_soc,
        'key', 'service:' || v_service,
        'before', CASE WHEN v_old.setting_id IS NULL THEN NULL
                       ELSE v_old.service_when || CASE WHEN v_old.service_when = 'every_return' AND NOT COALESCE(v_old.include_current_visit, true) THEN ':later' ELSE '' END END,
        'after', v_when || CASE WHEN v_when = 'every_return' AND NOT v_incl THEN ':later' ELSE '' END,
        'change', v_grp <> 'already_ordered',
        'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now));
    END LOOP;
    v_head := format('%s %s %s (%s, about %s min)%s.', v_cphrase,
                     CASE WHEN jsonb_array_length(v_cars) = 1 THEN 'gets' ELSE 'get' END, public.ottoq_owner_lc(v_svc_name),
                     public.ottoq_owner_service_where(v_service), v_svc_min,
                     CASE v_when WHEN 'now' THEN ' on this visit, or on the next one for a car that is out'
                                 WHEN 'next_return' THEN ' on the next return'
                                 ELSE CASE WHEN v_incl THEN ' on every visit from now on, this one included'
                                           ELSE ' on every return from the next one on' END END);
    IF jsonb_array_length(v_cars) = 1 THEN v_head := NULL; END IF;
    v_tail := 'OTTO-Q decides when and where: work in a bay comes after the charge, work at the car runs during it, and no car leaves with it undone.';

  ELSIF v_refusal IS NULL AND v_tool = 'cancel_service' THEN
    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP
      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> 'id')::uuid;
      FOR v_old IN SELECT * FROM public.ottoq_owner_settings o
                    WHERE o.sim_run_id = v_run_id AND o.vehicle_id = v_veh.id AND o.kind = 'service' AND o.status = 'active'
                      AND (v_service IS NULL OR o.service = v_service)
                    ORDER BY o.service
                    FOR UPDATE LOOP
        v_atom := NULL;
        SELECT a INTO v_atom
          FROM (SELECT vn.atoms FROM public.ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v_veh.id AND vn.sim_run_id = v_run_id AND vn.status IN ('open', 'in_progress')
                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) w
          CROSS JOIN LATERAL jsonb_array_elements(w.atoms) a
         WHERE jsonb_typeof(a -> 'owner_setting_ids') = 'array' AND (a -> 'owner_setting_ids') @> jsonb_build_array(v_old.setting_id::text)
         LIMIT 1;
        SELECT c.display_name INTO v_svc_name FROM public.service_cadence_policy c WHERE c.svc = v_old.service;
        IF v_atom IS NOT NULL AND v_atom ->> 'status' = 'in_progress' THEN
          v_grp := 'finishes'; v_now := format('%s: %s is under way and finishes (OTTO-Q never stops a service midway); it will not be added again.', v_veh.display_name, public.ottoq_owner_lc(v_svc_name));
          v_one := 'has it under way: it finishes, and is not added again'; v_many := 'have it under way: it finishes, and is not added again';
        ELSIF v_atom IS NOT NULL AND NOT COALESCE((v_atom ->> 'owner_added')::boolean, false) AND COALESCE(v_atom ->> 'status', 'pending') <> 'done' THEN
          v_grp := 'engine_needs_it'; v_now := format('%s: OTTO-Q found %s needed on this visit, so it stays; your order is withdrawn.', v_veh.display_name, public.ottoq_owner_lc(v_svc_name));
          v_one := 'keeps it on this visit because OTTO-Q found it needed'; v_many := 'keep it on this visit because OTTO-Q found it needed';
        ELSE
          v_grp := 'withdrawn'; v_now := format('%s: %s comes off its plan.', v_veh.display_name, public.ottoq_owner_lc(v_svc_name));
          v_one := 'has it taken off its plan'; v_many := 'have it taken off their plans';
        END IF;
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(
          'vehicle_id', v_veh.id, 'vehicle', v_veh.display_name, 'state', v_veh.current_state::text, 'soc', v_veh.current_soc,
          'key', 'service:' || v_old.service, 'setting_id', v_old.setting_id,
          'before', v_old.service_when, 'after', NULL, 'change', true,
          'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now));
      END LOOP;
    END LOOP;
    v_head := CASE WHEN v_service IS NULL THEN format('Your service orders on %s are withdrawn.', v_cphrase)
                   ELSE format('Your order for %s on %s is withdrawn.',
                               public.ottoq_owner_lc(COALESCE((SELECT c.display_name FROM public.service_cadence_policy c WHERE c.svc = v_service), v_service)),
                               v_cphrase) END;
    v_tail := 'Only what you ordered comes off: a service OTTO-Q found a car to need stays until it is done.';

  ELSIF v_refusal IS NULL AND v_tool = 'hold_vehicle' THEN
    IF v_minutes IS NOT NULL THEN
      v_until := v_clock + make_interval(mins => v_minutes);
    ELSIF (v_args ->> 'until') ~ '^\d{4}-\d{2}-\d{2}' THEN
      BEGIN
        v_until := CASE WHEN (v_args ->> 'until') ~ '(Z|[+-]\d{2}(:?\d{2})?)$' THEN (v_args ->> 'until')::timestamptz
                        ELSE ((v_args ->> 'until')::timestamp AT TIME ZONE 'America/Chicago') END;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'until is not a time OTTO-Q can read.';
      END;
    ELSIF lower(btrim(v_args ->> 'until')) ~ '^\d{1,2}(:\d{2})?\s*(am|pm)?$' THEN
      DECLARE
        v_txt  text := lower(btrim(v_args ->> 'until'));
        v_h    int  := substring(v_txt FROM '^(\d{1,2})')::int;
        v_m    int  := COALESCE(substring(v_txt FROM ':(\d{2})')::int, 0);
        v_ampm text := substring(v_txt FROM '(am|pm)$');
        v_day  date := (v_clock AT TIME ZONE 'America/Chicago')::date;
      BEGIN
        IF v_ampm IS NOT NULL AND (v_h < 1 OR v_h > 12) OR v_h > 23 OR v_m > 59 THEN
          RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'until is not a time of day.';
        END IF;
        IF v_ampm = 'pm' AND v_h < 12 THEN v_h := v_h + 12; END IF;
        IF v_ampm = 'am' AND v_h = 12 THEN v_h := 0; END IF;
        v_until := ((v_day + make_time(v_h, v_m, 0)) AT TIME ZONE 'America/Chicago');
        IF v_until <= v_clock THEN
          v_until := (((v_day + 1) + make_time(v_h, v_m, 0)) AT TIME ZONE 'America/Chicago');
        END IF;
      END;
    ELSE
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'until is a time: "06:00", "6:00 AM" or an ISO timestamp.';
    END IF;
    IF v_until <= v_clock THEN
      v_refusal := jsonb_build_object('code', 'hold_in_the_past',
        'message', format('%s is not later than the sim clock (%s).', public.ottoq_owner_clock(v_until, true, true), public.ottoq_owner_clock(v_clock, true, true)));
    ELSIF v_until > v_clock + interval '24 hours' THEN
      v_refusal := jsonb_build_object('code', 'hold_too_long',
        'message', 'A hold is at most 24 sim hours. Hold for less, and set it again later if you need to.');
    ELSE
      v_norm := v_norm || jsonb_build_object('until_sim', v_until);
      FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP
        SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> 'id')::uuid;
        v_old := NULL;
        SELECT * INTO v_old FROM public.ottoq_owner_settings o
         WHERE o.sim_run_id = v_run_id AND o.vehicle_id = v_veh.id AND o.kind = 'hold' AND o.status = 'active'
         FOR UPDATE;
        IF v_old.setting_id IS NOT NULL AND v_old.hold_until_sim = v_until THEN
          v_grp := 'unchanged'; v_now := format('%s is already held until then.', v_veh.display_name);
          v_one := 'is already held until then'; v_many := 'are already held until then';
        ELSIF v_veh.current_state::text IN ('deployed', 'en_route_to_deployment', 'en_route_to_depot') THEN
          v_grp := 'out'; v_now := format('%s is out; if it comes back before %s, it waits at the depot until then.', v_veh.display_name, public.ottoq_owner_clock(v_until, true));
          v_one := 'is out, and waits until then if it comes back sooner'; v_many := 'are out, and wait until then if they come back sooner';
        ELSE
          v_grp := 'held'; v_now := format('%s will not leave before %s; once it is ready it waits in staging, and no charger is kept for it.', v_veh.display_name, public.ottoq_owner_clock(v_until, true));
          v_one := 'is at the depot and will not leave before then'; v_many := 'are at the depot and will not leave before then';
        END IF;
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(
          'vehicle_id', v_veh.id, 'vehicle', v_veh.display_name, 'state', v_veh.current_state::text, 'soc', v_veh.current_soc,
          'key', 'hold', 'before', v_old.hold_until_sim, 'after', v_until, 'change', v_grp <> 'unchanged',
          'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now));
      END LOOP;
      v_head := CASE WHEN jsonb_array_length(v_cars) > 1
                     THEN format('%s will not leave the depot before %s.', v_cphrase, public.ottoq_owner_clock(v_until, true, true)) END;
      v_tail := 'A hold only delays a departure; it never sends a car anywhere.'
                || CASE WHEN v_run_end IS NOT NULL AND v_until > v_run_end
                        THEN format(' The run ends at %s, and the hold with it.', public.ottoq_owner_clock(v_run_end, true, true)) ELSE '' END;
    END IF;

  ELSIF v_refusal IS NULL AND v_tool = 'release_hold' THEN
    FOR v_car IN SELECT x FROM jsonb_array_elements(v_cars) x LOOP
      SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_car ->> 'id')::uuid;
      v_old := NULL;
      SELECT * INTO v_old FROM public.ottoq_owner_settings o
       WHERE o.sim_run_id = v_run_id AND o.vehicle_id = v_veh.id AND o.kind = 'hold' AND o.status = 'active'
       FOR UPDATE;
      IF v_old.setting_id IS NULL THEN
        v_grp := 'unchanged'; v_now := format('%s is not held.', v_veh.display_name);
        v_one := 'is not held'; v_many := 'are not held';
      ELSE
        v_grp := 'released'; v_now := format('%s may leave as soon as it is ready.', v_veh.display_name);
        v_one := 'may leave as soon as it is ready'; v_many := 'may leave as soon as they are ready';
      END IF;
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'vehicle_id', v_veh.id, 'vehicle', v_veh.display_name, 'state', v_veh.current_state::text, 'soc', v_veh.current_soc,
        'key', 'hold', 'setting_id', v_old.setting_id, 'before', v_old.hold_until_sim, 'after', NULL,
        'change', v_old.setting_id IS NOT NULL,
        'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now));
    END LOOP;
    v_head := CASE WHEN jsonb_array_length(v_cars) > 1 THEN format('The hold on %s is released.', v_cphrase) END;

  ELSIF v_refusal IS NULL AND v_tool = 'undo_command' THEN
    SELECT * INTO v_target FROM public.ottoq_owner_commands c
     WHERE c.command_id = (v_norm ->> 'command_id')::uuid AND c.principal_id = p_agent.principal_id
     FOR UPDATE;
    IF NOT FOUND THEN
      v_refusal := jsonb_build_object('code', 'command_not_found', 'message', 'You sent no command with that id.');
    ELSIF v_target.tool = 'undo_command' THEN
      v_refusal := jsonb_build_object('code', 'cannot_undo_an_undo', 'message', 'That command was itself an undo. Send the original command again instead.');
    ELSIF v_target.outcome <> 'applied' THEN
      v_refusal := jsonb_build_object('code', 'nothing_to_undo', 'message', format('That command changed nothing (it was %s).', v_target.outcome));
    ELSIF v_target.undone_at IS NOT NULL THEN
      v_refusal := jsonb_build_object('code', 'already_undone', 'message', format('That command was already undone at %s.', public.ottoq_owner_clock(v_target.undone_at, false)));
    ELSIF v_target.lifted_at IS NOT NULL OR v_target.sim_run_id IS DISTINCT FROM v_run_id THEN
      v_refusal := jsonb_build_object('code', 'run_ended', 'message', 'That command applied to a run that has ended; its settings were lifted with it.');
    ELSE
      v_cars := COALESCE((SELECT jsonb_agg(DISTINCT jsonb_build_object('id', v.id, 'name', v.display_name))
                            FROM public.ottoq_owner_settings o JOIN public.vehicles v ON v.id = o.vehicle_id
                           WHERE o.command_id = v_target.command_id), '[]'::jsonb);
      v_cphrase := public.ottoq_owner_cars_phrase(v_cars, false);
      FOR v_set IN SELECT * FROM public.ottoq_owner_settings o WHERE o.command_id = v_target.command_id
                    ORDER BY o.vehicle_id, o.kind, o.service FOR UPDATE LOOP
        SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = v_set.vehicle_id;
        v_old := NULL;
        IF v_set.replaces_setting_id IS NOT NULL THEN
          SELECT * INTO v_old FROM public.ottoq_owner_settings o
           WHERE o.setting_id = v_set.replaces_setting_id AND o.status = 'replaced'
             AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands c WHERE c.command_id = o.command_id AND c.undone_at IS NOT NULL);
        END IF;
        IF v_set.status <> 'active' THEN
          v_grp := 'superseded';
          v_now := format('%s: already changed since (%s), so nothing is undone for it.', v_veh.display_name,
                          COALESCE(v_set.closed_reason, v_set.status));
          v_one := 'was already changed since'; v_many := 'were already changed since';
        ELSIF v_set.kind = 'charge_limit' THEN
          v_grp := 'limit_back';
          v_now := format('%s goes back to charging to %s%%.', v_veh.display_name, COALESCE(v_old.charge_limit_pct, v_ceiling));
          v_one := format('goes back to %s%%', COALESCE(v_old.charge_limit_pct, v_ceiling));
          v_many := format('go back to %s%%', COALESCE(v_old.charge_limit_pct, v_ceiling));
        ELSIF v_set.kind = 'hold' THEN
          v_grp := 'hold_back';
          v_now := CASE WHEN v_old.setting_id IS NOT NULL
                        THEN format('%s goes back to the earlier hold, until %s.', v_veh.display_name, public.ottoq_owner_clock(v_old.hold_until_sim, true))
                        ELSE format('%s is no longer held.', v_veh.display_name) END;
          v_one := 'is back to its earlier hold, or none'; v_many := 'are back to their earlier holds, or none';
        ELSE
          v_grp := 'order_back';
          v_now := format('%s: the order for %s is withdrawn%s.', v_veh.display_name, replace(v_set.service, '_', ' '),
                          CASE WHEN v_old.setting_id IS NOT NULL THEN ' and the earlier one restored' ELSE '' END);
          v_one := 'has the order withdrawn'; v_many := 'have the order withdrawn';
        END IF;
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(
          'vehicle_id', v_veh.id, 'vehicle', v_veh.display_name, 'state', v_veh.current_state::text, 'soc', v_veh.current_soc,
          'key', v_set.kind || COALESCE(':' || v_set.service, ''), 'setting_id', v_set.setting_id,
          'restores_setting_id', v_old.setting_id,
          'before', CASE WHEN v_set.status = 'active' THEN 'active' ELSE v_set.status END,
          'after', CASE WHEN v_set.status = 'active' THEN 'undone' ELSE v_set.status END,
          'change', v_set.status = 'active',
          'group', v_grp, 'group_one', v_one, 'group_many', v_many, 'now', v_now));
      END LOOP;
      v_head := format('Your command of %s (%s) is undone for %s.', public.ottoq_owner_clock(v_target.created_at, false),
                       replace(v_target.tool, '_', ' '), v_cphrase);
    END IF;
  END IF;

  -- ── the plan's hash: what changes (cars, settings, before -> after), never telemetry, so a car's state of charge
  -- moving between a preview and its confirmation does not invalidate the plan; a setting moving does. A hold is hashed
  -- by the time it RESOLVED to (until_sim), not the words that named it: "for 90 minutes" previewed at 7:00 and
  -- confirmed as "until 8:30" is the same plan, and the clock moving in between must not make it a different one ──
  v_changed := (SELECT count(*) FROM jsonb_array_elements(v_effects) e WHERE COALESCE((e ->> 'change')::boolean, false));
  v_hash := md5(jsonb_build_object(
              'tool', v_tool, 'run', v_run_id,
              'args', v_norm - 'mode' - 'note' - 'vehicles' - 'expect_plan_hash' - 'idempotency_key' - 'until' - 'for_minutes',
              'plan', COALESCE((SELECT jsonb_agg(jsonb_build_array(e ->> 'vehicle_id', e ->> 'key', e -> 'before', e -> 'after', e -> 'change')
                                                 ORDER BY e ->> 'vehicle_id', e ->> 'key')
                                  FROM jsonb_array_elements(v_effects) e), '[]'::jsonb))::text);
  IF v_refusal IS NULL AND v_mode = 'apply' AND v_expect IS NOT NULL AND v_expect <> v_hash THEN
    v_refusal := jsonb_build_object('code', 'plan_changed', 'plan_hash', v_hash,
      'message', 'The plan changed since it was previewed (a car''s settings moved). Nothing was applied. Read the new plan and confirm it with its hash.');
  END IF;

  -- ── record, and answer ──
  v_cmd.command_id := gen_random_uuid();
  v_cmd.link := CASE WHEN v_refusal IS NULL THEN public.ottoq_owner_app_link(v_run_id, p_agent.fleet_operator_id, v_cmd.command_id) END;
  v_summary := CASE
    WHEN v_refusal IS NOT NULL THEN 'Not done: ' || (v_refusal ->> 'message')
    WHEN v_mode = 'preview' THEN 'Preview only, nothing has changed. If you confirm: '
         || public.ottoq_owner_summarize(v_head, v_effects, v_tail)
         || format(E'\nTo confirm, send the same command with mode "apply" and expect_plan_hash "%s".', v_hash)
    WHEN v_changed = 0 THEN 'Nothing to change. ' || public.ottoq_owner_summarize('', v_effects, NULL)
    ELSE 'Done. ' || public.ottoq_owner_summarize(v_head, v_effects, v_tail)
         || CASE WHEN v_tool = 'undo_command' THEN '' ELSE E'\nThis lasts until the demo run ends or you undo it.' END
         || E'\nSee it in OrchestrAV: ' || v_cmd.link END;

  BEGIN
    INSERT INTO public.ottoq_owner_commands
      (command_id, principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, sim_clock, tool, mode, outcome,
       args, vehicles, effects, refusal, summary, plan_hash, link, idempotency_key, undoes_command_id)
    VALUES
      (v_cmd.command_id, p_agent.principal_id, p_agent.name, p_agent.fleet_operator_id, p_agent.depot_id, v_run_id, v_clock,
       v_tool, v_mode,
       CASE WHEN v_refusal IS NOT NULL THEN 'refused' WHEN v_mode = 'preview' THEN 'previewed'
            WHEN v_changed = 0 THEN 'no_change' ELSE 'applied' END,
       v_norm, v_cars, v_effects, v_refusal, left(v_summary, 6000), v_hash, v_cmd.link,
       CASE WHEN v_mode = 'apply' THEN v_idem END,
       CASE WHEN v_tool = 'undo_command' AND v_target.command_id IS NOT NULL THEN v_target.command_id END)
    RETURNING * INTO v_cmd;

    IF v_cmd.outcome = 'applied' THEN
      FOR v_e IN SELECT e FROM jsonb_array_elements(v_effects) e WHERE COALESCE((e ->> 'change')::boolean, false) LOOP
        IF v_tool IN ('set_charge_limit', 'clear_charge_limit') THEN
          v_old := NULL;
          UPDATE public.ottoq_owner_settings o
             SET status = CASE WHEN v_pct < v_ceiling THEN 'replaced' ELSE 'withdrawn' END,
                 closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id, pending_reconcile = true,
                 closed_reason = CASE WHEN v_pct < v_ceiling THEN 'replaced by a new limit' ELSE 'cleared by the owner' END
           WHERE o.sim_run_id = v_run_id AND o.vehicle_id = (v_e ->> 'vehicle_id')::uuid AND o.kind = 'charge_limit'
             AND o.status = 'active'
          RETURNING * INTO v_old;
          IF v_pct < v_ceiling THEN
            INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct,
                                                    command_id, replaces_setting_id, set_at_sim)
            VALUES (v_run_id, p_agent.depot_id, p_agent.fleet_operator_id, (v_e ->> 'vehicle_id')::uuid, 'charge_limit', v_pct,
                    v_cmd.command_id, v_old.setting_id, v_clock);
          END IF;
        ELSIF v_tool = 'request_service' THEN
          v_old := NULL;
          UPDATE public.ottoq_owner_settings o
             SET status = 'replaced', closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id,
                 closed_reason = 'replaced by a new order', pending_reconcile = true
           WHERE o.sim_run_id = v_run_id AND o.vehicle_id = (v_e ->> 'vehicle_id')::uuid AND o.kind = 'service'
             AND o.service = v_service AND o.status = 'active'
          RETURNING * INTO v_old;
          INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, service,
                                                  service_when, include_current_visit, command_id, replaces_setting_id, set_at_sim)
          VALUES (v_run_id, p_agent.depot_id, p_agent.fleet_operator_id, (v_e ->> 'vehicle_id')::uuid, 'service', v_service,
                  v_when, v_incl, v_cmd.command_id, v_old.setting_id, v_clock);
        ELSIF v_tool = 'cancel_service' THEN
          UPDATE public.ottoq_owner_settings o
             SET status = 'withdrawn', closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id,
                 closed_reason = 'cancelled by the owner', pending_reconcile = true
           WHERE o.setting_id = (v_e ->> 'setting_id')::uuid AND o.status = 'active';
        ELSIF v_tool = 'hold_vehicle' THEN
          v_old := NULL;
          UPDATE public.ottoq_owner_settings o
             SET status = 'replaced', closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id,
                 closed_reason = 'replaced by a new hold', pending_reconcile = true
           WHERE o.sim_run_id = v_run_id AND o.vehicle_id = (v_e ->> 'vehicle_id')::uuid AND o.kind = 'hold' AND o.status = 'active'
          RETURNING * INTO v_old;
          INSERT INTO public.ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, hold_until_sim,
                                                  command_id, replaces_setting_id, set_at_sim)
          VALUES (v_run_id, p_agent.depot_id, p_agent.fleet_operator_id, (v_e ->> 'vehicle_id')::uuid, 'hold', v_until,
                  v_cmd.command_id, v_old.setting_id, v_clock);
        ELSIF v_tool = 'release_hold' THEN
          UPDATE public.ottoq_owner_settings o
             SET status = 'withdrawn', closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id,
                 closed_reason = 'released by the owner', pending_reconcile = true
           WHERE o.setting_id = (v_e ->> 'setting_id')::uuid AND o.status = 'active';
        ELSIF v_tool = 'undo_command' THEN
          UPDATE public.ottoq_owner_settings o
             SET status = 'withdrawn', closed_at = now(), closed_at_sim = v_clock, closed_by_command_id = v_cmd.command_id,
                 closed_reason = 'undone by the owner', pending_reconcile = true
           WHERE o.setting_id = (v_e ->> 'setting_id')::uuid AND o.status = 'active';
          IF (v_e ->> 'restores_setting_id') IS NOT NULL THEN
            UPDATE public.ottoq_owner_settings o
               SET status = 'active', closed_at = NULL, closed_at_sim = NULL, closed_reason = NULL, closed_by_command_id = NULL,
                   pending_reconcile = true
             WHERE o.setting_id = (v_e ->> 'restores_setting_id')::uuid AND o.status = 'replaced';
          END IF;
        END IF;
      END LOOP;
      IF v_tool = 'undo_command' THEN
        UPDATE public.ottoq_owner_commands c SET undone_by_command_id = v_cmd.command_id, undone_at = now()
         WHERE c.command_id = v_target.command_id AND c.undone_at IS NULL;
      END IF;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    --: the same idempotency key sent twice at once: the second replays the first, if it is the same command
    IF v_idem IS NOT NULL AND v_mode = 'apply' THEN
      SELECT * INTO v_target FROM public.ottoq_owner_commands c
       WHERE c.principal_id = p_agent.principal_id AND c.idempotency_key = v_idem;
      IF FOUND THEN
        IF v_target.tool IS DISTINCT FROM v_tool
           OR (v_target.args - 'mode' - 'note' - 'until_sim') IS DISTINCT FROM (v_norm - 'mode' - 'note' - 'until_sim') THEN
          RAISE EXCEPTION USING ERRCODE = 'OQA22', MESSAGE = 'idempotency_key_reused',
            DETAIL = format('idempotency_key "%s" was used at the same moment for a different command (%s). Nothing was done; a new command needs a new key.',
                            v_idem, replace(v_target.tool, '_', ' '));
        END IF;
        RETURN public.ottoq_owner_command_reply(v_target, true);
      END IF;
    END IF;
    --: two commands for the same car at the same moment: the second records the clash instead of acting
    INSERT INTO public.ottoq_owner_commands
      (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, sim_clock, tool, mode, outcome, args,
       vehicles, effects, refusal, summary, plan_hash)
    VALUES
      (p_agent.principal_id, p_agent.name, p_agent.fleet_operator_id, p_agent.depot_id, v_run_id, v_clock, v_tool, v_mode,
       'refused', v_norm, v_cars, v_effects,
       jsonb_build_object('code', 'concurrent_change', 'message', 'Another command changed these cars at the same moment. Nothing was applied; send it again.'),
       'Not done: another command changed these cars at the same moment. Nothing was applied; send it again.', v_hash)
    RETURNING * INTO v_cmd;
  END;
  RETURN public.ottoq_owner_command_reply(v_cmd, false);
END $fn$;

-- ══ 9. the owner's reads ════════════════════════════════════════════════════════════════════════════════════════════

-- One car as its owner reads it: where it is, its charge and target, what is still to do (and which of it the owner
-- asked for), the owner's settings on it, and when it is planned to be ready. p_run NULL = no live run.
CREATE OR REPLACE FUNCTION public.ottoq_owner_car(p_v public.vehicles, p_run uuid, p_ceiling numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_limit  numeric;
  v_hold   timestamptz;
  v_orders jsonb;
  v_open   jsonb;
  v_ready  timestamptz;
  v_stall  text;
BEGIN
  IF p_run IS NOT NULL THEN
    SELECT o.charge_limit_pct INTO v_limit FROM public.ottoq_owner_settings o
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'charge_limit' AND o.status = 'active';
    SELECT o.hold_until_sim INTO v_hold FROM public.ottoq_owner_settings o
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'hold' AND o.status = 'active';
    SELECT COALESCE(jsonb_agg(jsonb_build_object('service', o.service, 'name', c.display_name, 'when', o.service_when,
                                                 'setting_id', o.setting_id, 'command_id', o.command_id) ORDER BY o.service), '[]'::jsonb)
      INTO v_orders
      FROM public.ottoq_owner_settings o LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
     WHERE o.sim_run_id = p_run AND o.vehicle_id = p_v.id AND o.kind = 'service' AND o.status = 'active';
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'service', a ->> 'svc', 'name', COALESCE(c.display_name, a ->> 'svc'),
             'status', COALESCE(a ->> 'status', 'pending'),
             'yours', COALESCE(jsonb_typeof(a -> 'owner_setting_ids') = 'array' AND jsonb_array_length(a -> 'owner_setting_ids') > 0, false))
             ORDER BY a ->> 'svc'), '[]'::jsonb)
      INTO v_open
      FROM (SELECT vn.atoms FROM public.ottoq_visit_needs vn
             WHERE vn.vehicle_id = p_v.id AND vn.sim_run_id = p_run AND vn.status IN ('open', 'in_progress')
             ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) w
      CROSS JOIN LATERAL jsonb_array_elements(w.atoms) a
      LEFT JOIN public.service_cadence_policy c ON c.svc = a ->> 'svc'
     WHERE COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled');
    SELECT max(l.planned_end_sim) INTO v_ready FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_run AND l.vehicle_id = p_v.id AND l.status IN ('planned', 'active');
  END IF;
  SELECT s.stall_code INTO v_stall FROM public.stalls s WHERE s.id = p_v.current_stall_id;
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'vehicle_id', p_v.id, 'name', p_v.display_name, 'model', p_v.model,
    'state', p_v.current_state::text, 'state_phrase', public.ottoq_owner_state_phrase(p_v.current_state::text),
    'group', public.ottoq_owner_state_group(p_v.current_state::text),
    'stall', v_stall, 'soc', p_v.current_soc,
    'charge_target', LEAST(p_ceiling, COALESCE(v_limit, p_ceiling)),
    'open_services', COALESCE(v_open, '[]'::jsonb),
    'yours', jsonb_strip_nulls(jsonb_build_object(
               'charge_limit_pct', v_limit, 'hold_until_sim', v_hold,
               'hold_until_local', public.ottoq_owner_clock(v_hold, true, true),
               'orders', CASE WHEN jsonb_array_length(COALESCE(v_orders, '[]'::jsonb)) > 0 THEN v_orders END)),
    'ready_by_sim', v_ready, 'ready_by_local', public.ottoq_owner_clock(v_ready, true)));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_owner_read(p_agent public.ottoq_agent_principals, p_tool text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_tool     text := lower(btrim(COALESCE(p_tool, '')));
  v_args     jsonb := COALESCE(p_args, '{}'::jsonb);
  v_run      jsonb := public.ottoq_agent_live_run(p_agent.depot_id);
  v_run_id   uuid;
  v_clock    timestamptz;
  v_demo     boolean;
  v_contract jsonb;
  v_ceiling  numeric;
  v_depot    text;
  v_op       text;
  v_cars     jsonb;
  v_counts   text;
  v_mine     text;
  v_next     text;
  v_avg      numeric;
  v_res      jsonb;
  v_car      jsonb;
  v_veh      public.vehicles;
  v_dec_at   timestamptz;
  v_dec      jsonb;
  v_text     text;
  v_limit    integer;
  v_id       uuid;
  v_rows     jsonb;
BEGIN
  IF p_agent.fleet_operator_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQA03', MESSAGE = 'fleet_scope_required',
      DETAIL = 'my_fleet, my_vehicle, my_settings and my_commands are for a token bound to one fleet. fleet_summary reads every owner.';
  END IF;
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_clock := (v_run ->> 'sim_clock')::timestamptz;
  v_demo := v_run IS NOT NULL AND v_run ->> 'run_by' = 'operator_demo';
  v_contract := public.ottoq_owner_contract(p_agent.fleet_operator_id, COALESCE(v_clock, now()));
  v_ceiling := COALESCE((v_contract ->> 'max_charge_pct')::numeric, public.ottoq_default_target_soc());
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  SELECT f.name INTO v_op FROM public.fleet_operators f WHERE f.id = p_agent.fleet_operator_id;

  IF v_tool = 'my_fleet' THEN
    SELECT COALESCE(jsonb_agg(public.ottoq_owner_car(f, v_run_id, v_ceiling) ORDER BY f.display_name, f.id), '[]'::jsonb)
      INTO v_cars FROM public.ottoq_owner_fleet(p_agent) f;
    SELECT string_agg(g.n || ' ' || g.grp, ', ' ORDER BY g.n DESC, g.grp)
      INTO v_counts
      FROM (SELECT c ->> 'group' AS grp, count(*) AS n FROM jsonb_array_elements(v_cars) c GROUP BY 1) g;
    SELECT round(avg((c ->> 'soc')::numeric)) INTO v_avg FROM jsonb_array_elements(v_cars) c WHERE c ? 'soc';
    SELECT string_agg(x.line, '; ' ORDER BY x.ord) INTO v_mine FROM (
      SELECT 1 AS ord, l.n || CASE WHEN l.n = 1 THEN ' car charges' ELSE ' cars charge' END || ' to at most ' || l.pct || '%' AS line
        FROM (SELECT (c #>> '{yours,charge_limit_pct}') AS pct, count(*) AS n FROM jsonb_array_elements(v_cars) c
               WHERE c #> '{yours,charge_limit_pct}' IS NOT NULL GROUP BY 1) l
      UNION ALL
      SELECT 2, o.n || CASE WHEN o.n = 1 THEN ' car has ' ELSE ' cars have ' END || public.ottoq_owner_lc(o.name)
                || CASE o.w WHEN 'every_return' THEN ' on every return' WHEN 'next_return' THEN ' on the next return' ELSE ' ordered on this visit' END
        FROM (SELECT x ->> 'name' AS name, x ->> 'when' AS w, count(*) AS n
                FROM jsonb_array_elements(v_cars) c CROSS JOIN LATERAL jsonb_array_elements(COALESCE(c #> '{yours,orders}', '[]'::jsonb)) x
               GROUP BY 1, 2) o
      UNION ALL
      SELECT 3, (c ->> 'name') || ' is held until ' || (c #>> '{yours,hold_until_local}')
        FROM jsonb_array_elements(v_cars) c WHERE c #> '{yours,hold_until_sim}' IS NOT NULL) x;
    SELECT string_agg((c ->> 'name') || ' around ' || (c ->> 'ready_by_local'), ', ' ORDER BY (c ->> 'ready_by_sim')::timestamptz)
      INTO v_next
      FROM (SELECT c FROM jsonb_array_elements(v_cars) c
             WHERE c ? 'ready_by_sim' AND c ->> 'group' IN ('charging', 'in a bay', 'waiting at the depot', 'staged to leave')
             ORDER BY (c ->> 'ready_by_sim')::timestamptz LIMIT 3) q;
    v_text := format('You have %s %s at %s.', jsonb_array_length(v_cars),
                     CASE WHEN jsonb_array_length(v_cars) = 1 THEN 'car' ELSE 'cars' END, COALESCE(v_depot, 'the depot'))
      || CASE WHEN v_run IS NULL THEN ' No run is live, so they are parked. Start a demo in OTTO-TWIN to see them work.'
              ELSE format(' On the %s run (sim clock %s): %s.', CASE WHEN v_demo THEN 'demo' ELSE 'live' END,
                          public.ottoq_owner_clock(v_clock, true), COALESCE(v_counts, 'no cars'))
                   || CASE WHEN v_avg IS NOT NULL THEN format(' Average charge %s%%.', v_avg) ELSE '' END END
      || CASE WHEN v_mine IS NOT NULL THEN ' Your settings: ' || v_mine || '.' ELSE ' You have no settings in force; every car charges to ' || v_ceiling || '%.' END
      || CASE WHEN v_next IS NOT NULL THEN ' Next planned ready: ' || v_next || '.' ELSE '' END;
    RETURN jsonb_build_object(
      'summary', v_text, 'fleet_operator', v_op, 'depot', v_depot,
      'run', CASE WHEN v_run IS NULL THEN NULL ELSE jsonb_build_object('sim_run_id', v_run_id, 'demo', v_demo,
               'sim_clock', v_clock, 'sim_clock_local', public.ottoq_owner_clock(v_clock, true)) END,
      'cars', v_cars, 'total', jsonb_array_length(v_cars),
      'your_range', jsonb_build_object('charge_limit_min_pct', v_contract -> 'min_charge_pct', 'charge_limit_max_pct', v_ceiling),
      'link', public.ottoq_owner_app_link(v_run_id, p_agent.fleet_operator_id, NULL),
      'clocks', 'sim_* and *_local with "sim time" are SIMULATION time in Nashville local time; created_at is real time.');

  ELSIF v_tool = 'my_vehicle' THEN
    v_res := public.ottoq_owner_resolve_vehicles(p_agent, COALESCE(v_args -> 'vehicle', v_args -> 'vehicles'));
    IF NOT COALESCE((v_res ->> 'ok')::boolean, false) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = COALESCE(v_res ->> 'code', 'vehicle_not_found'),
        DETAIL = v_res ->> 'message';
    END IF;
    IF jsonb_array_length(v_res -> 'vehicles') <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'Name one car.';
    END IF;
    SELECT * INTO v_veh FROM public.vehicles v WHERE v.id = (v_res #>> '{vehicles,0,id}')::uuid;
    v_car := public.ottoq_owner_car(v_veh, v_run_id, v_ceiling);
    IF v_run_id IS NOT NULL THEN
      SELECT f.occurred_at, jsonb_build_object('at_sim', f.occurred_at, 'action', f.action, 'target', f.target,
                                               'outcome', f.outcome, 'reason', f.reason, 'rationale', f.rationale)
        INTO v_dec_at, v_dec
        FROM public.ottoq_activity_feed(v_run_id, 200, v_veh.id, true, 240) f
       ORDER BY f.occurred_at DESC, f.decision_seq DESC LIMIT 1;
    END IF;
    v_text := format('%s (%s) is %s%s', v_veh.display_name, COALESCE(v_veh.model, 'car'), v_car ->> 'state_phrase',
                     CASE WHEN v_car ? 'stall' THEN ' at ' || (v_car ->> 'stall') ELSE '' END)
      || CASE WHEN v_car ? 'soc' THEN format(', at %s%%, target %s%%', v_car ->> 'soc', v_car ->> 'charge_target') ELSE '' END
      || CASE WHEN v_car #> '{yours,charge_limit_pct}' IS NOT NULL THEN format(' (your limit; full is %s%%)', v_ceiling) ELSE '' END
      || '.'
      || CASE WHEN jsonb_array_length(v_car -> 'open_services') > 0
              THEN ' Still to do before it leaves: '
                   || (SELECT string_agg(public.ottoq_owner_lc(x ->> 'name') || CASE WHEN (x ->> 'yours')::boolean THEN ' (yours)' ELSE '' END
                                         || CASE WHEN x ->> 'status' = 'in_progress' THEN ', under way' ELSE '' END, '; ')
                         FROM jsonb_array_elements(v_car -> 'open_services') x) || '.'
              WHEN v_run_id IS NOT NULL THEN ' Nothing is left to do on its visit.' ELSE '' END
      || CASE WHEN v_car #> '{yours,hold_until_local}' IS NOT NULL
              THEN ' You asked OTTO-Q to keep it until ' || (v_car #>> '{yours,hold_until_local}') || '.' ELSE '' END
      || CASE WHEN v_car ? 'ready_by_local' THEN ' Planned to be ready around ' || (v_car ->> 'ready_by_local') || '.' ELSE '' END
      || CASE WHEN v_dec_at IS NOT NULL
              THEN format(' OTTO-Q''s last decision for it: %s%s at %s.', replace(v_dec ->> 'action', '_', ' '),
                          CASE WHEN v_dec ->> 'target' IS NOT NULL THEN ' (' || (v_dec ->> 'target') || ')' ELSE '' END,
                          public.ottoq_owner_clock(v_dec_at, true))
              ELSE '' END;
    RETURN jsonb_build_object('summary', v_text, 'car', v_car,
      'last_decision', v_dec,
      'link', public.ottoq_owner_app_link(v_run_id, p_agent.fleet_operator_id, NULL),
      'clocks', 'Times marked "sim time" are SIMULATION time in Nashville local time.');

  ELSIF v_tool = 'my_settings' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'setting_id', o.setting_id, 'vehicle_id', o.vehicle_id, 'vehicle', v.display_name, 'kind', o.kind,
             'charge_limit_pct', o.charge_limit_pct, 'hold_until_sim', o.hold_until_sim,
             'hold_until_local', public.ottoq_owner_clock(o.hold_until_sim, true, true),
             'service', o.service, 'service_name', c.display_name, 'when', o.service_when,
             'set_at', o.set_at, 'set_at_local', public.ottoq_owner_clock(o.set_at, false), 'command_id', o.command_id,
             'waiting_for_tick', o.pending_reconcile)
             ORDER BY o.kind, v.display_name, o.service), '[]'::jsonb)
      INTO v_rows
      FROM public.ottoq_owner_settings o
      JOIN public.vehicles v ON v.id = o.vehicle_id
      LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
     WHERE o.sim_run_id = v_run_id AND o.fleet_operator_id = p_agent.fleet_operator_id AND o.status = 'active';
    SELECT string_agg(x.line, '; ' ORDER BY x.ord) INTO v_mine FROM (
      SELECT 1 AS ord, count(*) || CASE WHEN count(*) = 1 THEN ' car charges' ELSE ' cars charge' END
                       || ' to at most ' || (s ->> 'charge_limit_pct') || '%' AS line
        FROM jsonb_array_elements(v_rows) s WHERE s ->> 'kind' = 'charge_limit' GROUP BY s ->> 'charge_limit_pct'
      UNION ALL
      SELECT 2, count(*) || CASE WHEN count(*) = 1 THEN ' car has ' ELSE ' cars have ' END || public.ottoq_owner_lc(s ->> 'service_name')
                || CASE s ->> 'when' WHEN 'every_return' THEN ' on every return' WHEN 'next_return' THEN ' on the next return'
                                     ELSE ' ordered on this visit' END
        FROM jsonb_array_elements(v_rows) s WHERE s ->> 'kind' = 'service' GROUP BY s ->> 'service_name', s ->> 'when'
      UNION ALL
      SELECT 3, (s ->> 'vehicle') || ' is held until ' || (s ->> 'hold_until_local')
        FROM jsonb_array_elements(v_rows) s WHERE s ->> 'kind' = 'hold') x;
    RETURN jsonb_build_object(
      'summary', CASE WHEN v_run IS NULL THEN 'No run is live, so nothing is in force: every car is at baseline.'
                      WHEN v_mine IS NULL THEN format('Nothing is in force on this run: every car charges to %s%% and gets what OTTO-Q finds it needs.', v_ceiling)
                      ELSE 'In force on this run: ' || v_mine || '. Everything lifts when the run ends.' END,
      'settings', v_rows, 'run', v_run_id,
      'undo', 'Send undo_command with a command_id, or clear_charge_limit, cancel_service or release_hold.');

  ELSIF v_tool = 'my_commands' THEN
    v_limit := public.ottoq_agent_arg_int(v_args, 'limit', 10, 1, 50);
    v_id := public.ottoq_agent_arg_uuid(v_args, 'command_id');
    SELECT COALESCE(jsonb_agg(public.ottoq_owner_command_reply(q.c, false) - 'confirm' ORDER BY q.created_at DESC), '[]'::jsonb)
      INTO v_rows
      FROM (SELECT c, c.created_at FROM public.ottoq_owner_commands c
             WHERE c.principal_id = p_agent.principal_id AND (v_id IS NULL OR c.command_id = v_id)
               AND (NULLIF(v_args ->> 'outcome', '') IS NULL OR c.outcome = v_args ->> 'outcome')
             ORDER BY c.created_at DESC LIMIT v_limit) q;
    IF v_id IS NOT NULL AND jsonb_array_length(v_rows) = 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'command_not_found', DETAIL = 'You sent no command with that id.';
    END IF;
    RETURN jsonb_build_object('commands', v_rows, 'returned', jsonb_array_length(v_rows));
  END IF;
  RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'unknown_tool', DETAIL = format('No owner read named %s.', v_tool);
END $fn$;


-- ══ 10. 0559's three functions, extended (each is 0559's body plus the 0605 lines; P1 pinned the bodies replaced) ════

CREATE OR REPLACE FUNCTION public.ottoq_agent_call(
    p_token_hash text,
    p_tool       text,
    p_args       jsonb DEFAULT '{}'::jsonb,
    p_transport  text  DEFAULT 'rest',
    p_meta       jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0559. The ONLY function the ottoq-agent-gateway edge function calls. It resolves the token hash to an active
   principal, applies the per-principal rate limit, checks the tool's capability, runs the tool and writes the call
   ledger, in one transaction. Business refusals from a tool (SQLSTATE OQAxx) roll back whatever the tool started and
   come back as an HTTP status the edge function forwards. This function names no engine door: an agent can read and
   can ASK, and a person decides through ottoq_agent_request_decide.
   0605: and an OWNER's agent can set what its own cars need (owner_settings): the owner tools write only
   ottoq_owner_commands and ottoq_owner_settings, and the engine applies the settings at its next tick. A refused owner
   command is not an exception: it is recorded as evidence and answered 422 with the recorded command. Transport 'ask'
   is the gateway's natural-language door (OTTO-Command speaking for the agent, with the agent's own token). */
DECLARE
  t0          timestamptz := clock_timestamp();
  v_agent     public.ottoq_agent_principals;
  v_tool      text := left(lower(btrim(COALESCE(p_tool, ''))), 64);
  v_transport text := CASE WHEN p_transport IN ('rest', 'mcp', 'ask') THEN p_transport ELSE 'other' END;
  v_args      jsonb := COALESCE(p_args, '{}'::jsonb);
  v_meta      jsonb;
  v_need      text;
  v_data      jsonb;
  v_status    integer := 200;
  v_code      text;
  v_msg       text;
  v_detail    text;
  v_hint      text;
  v_state     text;
  v_recent    integer;
  v_request   uuid;
  v_call      bigint;
  v_owner_cmd boolean;
BEGIN
  --: only small, known keys from the caller reach the ledger
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'http_method',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'http_method', 8),
    'path',         left(COALESCE(p_meta, '{}'::jsonb) ->> 'path', 200),
    'mcp_method',   left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_method', 64),
    'mcp_version',  left(COALESCE(p_meta, '{}'::jsonb) ->> 'mcp_version', 16),
    'client',       left(COALESCE(p_meta, '{}'::jsonb) ->> 'client', 120),
    'ip',           left(COALESCE(p_meta, '{}'::jsonb) ->> 'ip', 64)));

  v_agent := public.ottoq_agent_resolve(p_token_hash);
  IF v_agent.principal_id IS NULL THEN
    --: an unknown or revoked token reaches no tool. Ledgered, but at most 60 a minute, so a caller without a token
    --: cannot grow the ledger without bound.
    SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
     WHERE l.principal_id IS NULL AND l.called_at > now() - interval '1 minute';
    IF v_recent < 60 THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, transport, tool, http_method, path, ok, http_status,
                                                 error_code, latency_ms, detail)
      VALUES (NULL, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', false, 401, 'unauthenticated',
              (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_meta - 'http_method' - 'path')
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', 401, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_build_object('code', 'unauthenticated', 'message', 'The token is unknown or has been revoked.'));
  END IF;

  --: the rate limit reads the ledger, so it holds across edge isolates and cold starts
  SELECT count(*) INTO v_recent FROM public.ottoq_agent_call_ledger l
   WHERE l.principal_id = v_agent.principal_id AND l.called_at > now() - interval '1 minute';
  IF v_recent >= v_agent.rate_limit_per_min THEN
    IF v_recent < 2 * v_agent.rate_limit_per_min THEN
      INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                                 http_status, error_code, latency_ms, depot_id, fleet_operator_id, detail)
      VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path',
              false, 429, 'rate_limited', (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer,
              v_agent.depot_id, v_agent.fleet_operator_id, v_meta - 'http_method' - 'path')
      RETURNING call_id INTO v_call;
    END IF;
    RETURN jsonb_build_object('ok', false, 'http_status', 429, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_build_object('code', 'rate_limited', 'retry_after_s', 60,
        'message', format('At most %s calls a minute for this token.', v_agent.rate_limit_per_min)));
  END IF;

  UPDATE public.ottoq_agent_principals a SET last_used_at = now()
   WHERE a.principal_id = v_agent.principal_id
     AND (a.last_used_at IS NULL OR a.last_used_at < now() - interval '1 minute');

  --: TOTAL over the tool vocabulary: an unknown name is a 404, never a fall-through
  v_need := CASE v_tool
    WHEN 'handshake'          THEN ''
    WHEN 'whoami'             THEN ''
    WHEN 'list_requests'      THEN ''
    WHEN 'depot_status'       THEN 'read'
    WHEN 'fleet_summary'      THEN 'read'
    WHEN 'vehicle_card'       THEN 'read'
    WHEN 'recent_decisions'   THEN 'read'
    WHEN 'stall_availability' THEN 'read'
    WHEN 'send_note'          THEN 'note'
    WHEN 'submit_request'     THEN 'per_kind'
    -- 0605: the owner's reads and commands
    WHEN 'my_fleet'           THEN 'read'
    WHEN 'my_vehicle'         THEN 'read'
    WHEN 'my_settings'        THEN 'read'
    WHEN 'my_commands'        THEN ''
    WHEN 'set_charge_limit'   THEN 'owner_settings'
    WHEN 'clear_charge_limit' THEN 'owner_settings'
    WHEN 'request_service'    THEN 'owner_settings'
    WHEN 'cancel_service'     THEN 'owner_settings'
    WHEN 'hold_vehicle'       THEN 'owner_settings'
    WHEN 'release_hold'       THEN 'owner_settings'
    WHEN 'undo_command'       THEN 'owner_settings'
    ELSE NULL END;
  v_owner_cmd := v_tool IN ('set_charge_limit', 'clear_charge_limit', 'request_service', 'cancel_service', 'hold_vehicle',
                            'release_hold', 'undo_command');

  BEGIN
    IF v_need IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA04', MESSAGE = 'unknown_tool', DETAIL = format('No tool named %s.', v_tool);
    END IF;
    IF jsonb_typeof(v_args) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments', DETAIL = 'arguments must be a JSON object.';
    END IF;
    IF v_need NOT IN ('', 'per_kind') AND NOT (v_need = ANY (v_agent.capabilities)) THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA03', MESSAGE = 'capability_missing',
        DETAIL = format('This token does not carry the %s capability.', v_need);
    END IF;
    --: the gateway refused the arguments against the tool's published schema. It still asks here first, so the
    --: refusal is authenticated, rate-limited and ledgered like any call: an unknown token learns nothing from a
    --: malformed request, and a known one leaves a trace of it.
    IF (COALESCE(p_meta, '{}'::jsonb) ->> 'gateway_refusal') = 'invalid_arguments' THEN
      RAISE EXCEPTION USING ERRCODE = 'OQA01', MESSAGE = 'invalid_arguments',
        DETAIL = 'The arguments do not match the tool''s schema; the gateway''s reply lists each problem.';
    END IF;
    v_data := CASE v_tool
      WHEN 'handshake'          THEN public.ottoq_agent_read_whoami(v_agent)
      WHEN 'whoami'             THEN public.ottoq_agent_read_whoami(v_agent)
      WHEN 'depot_status'       THEN public.ottoq_agent_read_depot(v_agent)
      WHEN 'fleet_summary'      THEN public.ottoq_agent_read_fleet(v_agent, v_args)
      WHEN 'vehicle_card'       THEN public.ottoq_agent_read_vehicle(v_agent, v_args)
      WHEN 'recent_decisions'   THEN public.ottoq_agent_read_decisions(v_agent, v_args)
      WHEN 'stall_availability' THEN public.ottoq_agent_read_stalls(v_agent, v_args)
      WHEN 'list_requests'      THEN public.ottoq_agent_read_requests(v_agent, v_args)
      WHEN 'send_note'          THEN public.ottoq_agent_submit_request(v_agent, 'note', v_args)
      WHEN 'submit_request'     THEN public.ottoq_agent_submit_request(v_agent, COALESCE(v_args ->> 'kind', ''), v_args)
      WHEN 'my_fleet'           THEN public.ottoq_owner_read(v_agent, 'my_fleet', v_args)
      WHEN 'my_vehicle'         THEN public.ottoq_owner_read(v_agent, 'my_vehicle', v_args)
      WHEN 'my_settings'        THEN public.ottoq_owner_read(v_agent, 'my_settings', v_args)
      WHEN 'my_commands'        THEN public.ottoq_owner_read(v_agent, 'my_commands', v_args)
      ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)
    END;
    IF v_tool IN ('send_note', 'submit_request') THEN
      v_status := CASE WHEN COALESCE((v_data ->> 'duplicate')::boolean, false) THEN 200 ELSE 201 END;
      v_request := (v_data #>> '{request,request_id}')::uuid;
    END IF;
    IF v_owner_cmd THEN
      v_status := CASE WHEN v_data ->> 'outcome' = 'refused' THEN 422
                       WHEN v_data ->> 'outcome' = 'applied' AND NOT COALESCE((v_data ->> 'duplicate')::boolean, false) THEN 201
                       ELSE 200 END;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT,
                            v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT;
    v_status := CASE v_state WHEN 'OQA01' THEN 400 WHEN 'OQA03' THEN 403 WHEN 'OQA04' THEN 404
                             WHEN 'OQA09' THEN 409 WHEN 'OQA22' THEN 422 WHEN 'OQA29' THEN 429 ELSE 500 END;
    v_code := CASE WHEN v_status = 500 THEN 'internal_error' ELSE v_msg END;
    INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                               http_status, error_code, latency_ms, depot_id, fleet_operator_id, detail)
    VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path', false,
            v_status, v_code, (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer,
            v_agent.depot_id, v_agent.fleet_operator_id,
            (v_meta - 'http_method' - 'path')
            || CASE WHEN v_status = 500 THEN jsonb_build_object('sqlstate', v_state, 'error', left(v_msg, 300))
                    ELSE '{}'::jsonb END)
    RETURNING call_id INTO v_call;
    RETURN jsonb_build_object('ok', false, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
      'error', jsonb_strip_nulls(jsonb_build_object(
        'code', v_code,
        'message', CASE WHEN v_status = 500 THEN 'The gateway hit an internal error. It is recorded under this call_id.'
                        ELSE COALESCE(NULLIF(v_detail, ''), v_msg) END,
        'hint', CASE WHEN v_status = 500 THEN NULL ELSE NULLIF(v_hint, '') END)));
  END;

  INSERT INTO public.ottoq_agent_call_ledger (principal_id, principal_name, transport, tool, http_method, path, ok,
                                             http_status, error_code, latency_ms, request_id, depot_id, fleet_operator_id, detail)
  VALUES (v_agent.principal_id, v_agent.name, v_transport, v_tool, v_meta ->> 'http_method', v_meta ->> 'path',
          v_status < 400, v_status, CASE WHEN v_status >= 400 THEN v_data #>> '{refusal,code}' END,
          (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, v_request,
          v_agent.depot_id, v_agent.fleet_operator_id,
          (v_meta - 'http_method' - 'path')
          || CASE WHEN v_owner_cmd THEN jsonb_strip_nulls(jsonb_build_object('command_id', v_data #>> '{command,command_id}',
                                                                             'outcome', v_data ->> 'outcome'))
                  ELSE '{}'::jsonb END)
  RETURNING call_id INTO v_call;
  --: 0605: a refused owner command was recorded, not raised: it answers 422 WITH the recorded command
  IF v_status >= 400 THEN
    RETURN jsonb_build_object('ok', false, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
      'principal', jsonb_build_object('name', v_agent.name, 'kind', v_agent.kind,
                                      'capabilities', to_jsonb(v_agent.capabilities)),
      'error', jsonb_strip_nulls(jsonb_build_object('code', v_data #>> '{refusal,code}',
                                                    'message', v_data #>> '{refusal,message}',
                                                    'hint', v_data #>> '{refusal,hint}')),
      'data', v_data);
  END IF;
  RETURN jsonb_build_object('ok', true, 'http_status', v_status, 'tool', v_tool, 'call_id', v_call,
    'principal', jsonb_build_object('name', v_agent.name, 'kind', v_agent.kind,
                                    'capabilities', to_jsonb(v_agent.capabilities)),
    'data', v_data);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_issue_token(
    p_name               text,
    p_kind               text,
    p_capabilities       text[]  DEFAULT ARRAY['read','note']::text[],
    p_fleet_operator_id  uuid    DEFAULT NULL,
    p_depot_id           uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_note               text    DEFAULT NULL,
    p_rate_limit_per_min integer DEFAULT 60,
    p_max_pending        integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $fn$
/* 0559. Creates an agent principal and returns its token ONCE. Only sha256(token) is stored; a lost token cannot be
   recovered -- revoke the principal and issue a new one.
   0605: owner_settings is issued only with a fleet: an owner's settings are for its own cars. */
DECLARE
  v_name  text   := lower(btrim(COALESCE(p_name, '')));
  v_kind  text   := lower(btrim(COALESCE(p_kind, '')));
  v_caps  text[];
  v_token text;
  v_row   public.ottoq_agent_principals;
BEGIN
  IF v_name !~ '^[a-z0-9][a-z0-9_.-]{1,62}$' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_name',
      'message', '2 to 63 characters of a-z 0-9 . _ -, starting with a letter or digit.');
  END IF;
  IF v_kind NOT IN ('personal', 'fleet_operator', 'depot_ops') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_kind', 'message', 'kind is personal, fleet_operator or depot_ops.');
  END IF;
  IF p_depot_id IS DISTINCT FROM '11111111-1111-1111-1111-111111111111'::uuid THEN
    RETURN jsonb_build_object('ok', false, 'error', 'twin_depot_only',
      'message', 'CLAUDE.md rule 8: the twin depot (11111111-1111-1111-1111-111111111111) is the only site an agent is scoped to.');
  END IF;
  IF v_kind = 'fleet_operator' AND p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fleet_operator_required', 'message', 'A fleet_operator agent names its fleet operator.');
  END IF;
  IF v_kind = 'depot_ops' AND p_fleet_operator_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_ops_sees_every_owner', 'message', 'A depot_ops agent is not fleet-scoped.');
  END IF;
  IF p_fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id AND f.is_active) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No active fleet operator with that id.');
  END IF;
  v_caps := ARRAY(SELECT DISTINCT lower(btrim(c)) FROM unnest(COALESCE(p_capabilities, ARRAY[]::text[])) c ORDER BY 1);
  IF cardinality(v_caps) = 0
     OR NOT (v_caps <@ ARRAY['read','note','request_recall','request_ops_action','request_adjustment','owner_settings']::text[]) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_capabilities',
      'allowed', jsonb_build_array('read','note','request_recall','request_ops_action','request_adjustment','owner_settings'));
  END IF;
  IF 'owner_settings' = ANY (v_caps) AND p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_settings_needs_a_fleet',
      'message', 'owner_settings changes what one owner''s cars need, so the token names that owner (p_fleet_operator_id).');
  END IF;
  IF 'request_ops_action' = ANY (v_caps) AND p_fleet_operator_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ops_action_needs_depot_scope',
      'message', 'An ops action changes the whole depot, so a fleet-scoped agent cannot ask for one.');
  END IF;
  IF p_rate_limit_per_min NOT BETWEEN 1 AND 600 OR p_max_pending NOT BETWEEN 1 AND 200 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_limits', 'message', 'rate 1..600 per minute, pending 1..200.');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_principals a WHERE a.name = v_name) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'name_taken',
      'message', 'A principal already has that name. A token''s scope is fixed at issue: revoke the old one and issue under a new name.');
  END IF;

  v_token := 'oqa_' || encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO public.ottoq_agent_principals
    (name, kind, depot_id, fleet_operator_id, capabilities, token_hash, token_prefix, rate_limit_per_min, max_pending, note)
  VALUES
    (v_name, v_kind, p_depot_id, p_fleet_operator_id, v_caps, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
     left(v_token, 12), p_rate_limit_per_min, p_max_pending, NULLIF(btrim(COALESCE(p_note, '')), ''))
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'ok', true,
    'token', v_token,
    'warning', 'This is the only time the token is shown. Only its SHA-256 is stored. If it is lost, revoke this principal and issue a new one.',
    'principal', jsonb_build_object('principal_id', v_row.principal_id, 'name', v_row.name, 'kind', v_row.kind,
                                    'depot_id', v_row.depot_id, 'fleet_operator_id', v_row.fleet_operator_id,
                                    'capabilities', to_jsonb(v_row.capabilities), 'token_prefix', v_row.token_prefix,
                                    'rate_limit_per_min', v_row.rate_limit_per_min, 'max_pending', v_row.max_pending));
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_read_whoami(p_agent public.ottoq_agent_principals)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE v_depot text; v_fleet text; v_owner jsonb; v_run jsonb; v_contract jsonb;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_agent.depot_id;
  IF p_agent.fleet_operator_id IS NOT NULL THEN
    SELECT f.name INTO v_fleet FROM public.fleet_operators f WHERE f.id = p_agent.fleet_operator_id;
  END IF;
  --: 0605: what an owner's agent may set, and inside what range
  IF 'owner_settings' = ANY (p_agent.capabilities) AND p_agent.fleet_operator_id IS NOT NULL THEN
    v_run := public.ottoq_agent_live_run(p_agent.depot_id);
    v_contract := public.ottoq_owner_contract(p_agent.fleet_operator_id, COALESCE((v_run ->> 'sim_clock')::timestamptz, now()));
    v_owner := jsonb_build_object(
      'cars', (SELECT count(*) FROM public.ottoq_owner_fleet(p_agent)),
      'live_demo_run', CASE WHEN v_run ->> 'run_by' = 'operator_demo' THEN v_run -> 'sim_run_id' END,
      'charge_limit_pct', jsonb_build_object('min', v_contract -> 'min_charge_pct', 'max', v_contract -> 'max_charge_pct'),
      'requestable_services', (SELECT jsonb_agg(jsonb_build_object('service', c.svc, 'name', c.display_name,
                                                                    'minutes', c.est_min_default,
                                                                    'where', public.ottoq_owner_service_where(c.svc))
                                                ORDER BY c.display_name)
                                 FROM public.service_cadence_policy c
                                WHERE c.svc = ANY (public.ottoq_owner_requestable_services()) AND c.is_active
                                  AND NOT COALESCE((v_contract -> 'blocked_services') ? c.svc, false)),
      'hold_max_hours', 24,
      'commands', jsonb_build_array('set_charge_limit', 'clear_charge_limit', 'request_service', 'cancel_service',
                                    'hold_vehicle', 'release_hold', 'undo_command'),
      'rules', 'Your settings change what your cars need, never how they move: OTTO-Q decides when and where, the AV stack moves the car. Each setting is checked against your contract, applied at OTTO-Q''s next tick, undoable, and lifted when the demo run ends.',
      'orchestrav', public.ottoq_owner_app_link((v_run ->> 'sim_run_id')::uuid, p_agent.fleet_operator_id, NULL));
  END IF;
  RETURN jsonb_build_object(
    'principal', jsonb_build_object('name', p_agent.name, 'kind', p_agent.kind, 'token_prefix', p_agent.token_prefix,
                                    'created_at', p_agent.created_at, 'last_used_at', p_agent.last_used_at,
                                    'note', p_agent.note),
    'scope', jsonb_build_object(
      'depot', jsonb_build_object('id', p_agent.depot_id, 'name', v_depot),
      'fleet_operator', CASE WHEN p_agent.fleet_operator_id IS NULL THEN NULL
                             ELSE jsonb_build_object('id', p_agent.fleet_operator_id, 'name', v_fleet) END,
      'sees', CASE WHEN p_agent.fleet_operator_id IS NULL THEN 'every vehicle at the depot, all owners'
                   ELSE 'only this fleet operator''s vehicles' END),
    'capabilities', to_jsonb(p_agent.capabilities),
    'limits', jsonb_build_object('calls_per_minute', p_agent.rate_limit_per_min,
                                 'max_pending_requests', p_agent.max_pending),
    'how_changes_happen',
      CASE WHEN v_owner IS NOT NULL THEN
        'Settings for your own cars (charge limit, services, holds) are yours to set: OTTO-Q checks each against your '
        || 'contract and its own rules, applies it at its next tick, and answers with a receipt and an OrchestrAV link. '
        || 'Anything else is a request a person approves or declines in OTTO-PULSE.'
      ELSE
      'Every change you ask for is a request. A person approves or declines it: the depot crew in OTTO-PULSE, or the '
      || 'fleet''s own operator once signed in. An approved request goes to one of OTTO-Q''s own doors, which may still '
      || 'refuse it; list_requests shows the decision and the engine''s exact reply. Nothing happens on your say-so alone.'
      END,
    'owner', v_owner);
END $fn$;

-- ══ 11. the event the tick writes, registered ══════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES ('ottoq.owner_settings_applied', 'action',
        'OTTO-Q applied what an owner''s agent set for its own cars, at one tick: cars re-targeted to a new charge limit, owner service orders put on or taken off visits, holds and fulfilled orders closed. One event per tick that changed something.',
        'ottoq.ottoq_owner_orders_tick', 'info', '0605')
ON CONFLICT (event_type) DO NOTHING;

-- ══ 12. privileges: revoke everything, then grant exactly ═══════════════════════════════════════════════════════════

ALTER TABLE public.ottoq_owner_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_owner_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_owner_commands, public.ottoq_owner_settings FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.ottoq_owner_commands_guard(),
  public.ottoq_owner_charge_limit(uuid),
  public.ottoq_owner_departure_blocked(uuid, uuid, timestamptz),
  public.ottoq_tg_owner_orders_on_new_visit(),
  public.ottoq_tg_lift_owner_settings_on_terminal(),
  public.ottoq_owner_app_link(uuid, uuid, uuid),
  public.ottoq_owner_clock(timestamptz, boolean, boolean),
  public.ottoq_owner_state_phrase(text),
  public.ottoq_owner_lc(text),
  public.ottoq_owner_state_group(text),
  public.ottoq_owner_requestable_services(),
  public.ottoq_owner_service_code(text),
  public.ottoq_owner_contract(uuid, timestamptz),
  public.ottoq_owner_fleet(public.ottoq_agent_principals),
  public.ottoq_owner_resolve_vehicles(public.ottoq_agent_principals, jsonb),
  public.ottoq_owner_cars_phrase(jsonb, boolean),
  public.ottoq_owner_service_where(text),
  public.ottoq_owner_summarize(text, jsonb, text),
  public.ottoq_owner_limit_effect(public.vehicles, numeric, numeric),
  public.ottoq_owner_command_reply(public.ottoq_owner_commands, boolean),
  public.ottoq_owner_command(public.ottoq_agent_principals, text, jsonb),
  public.ottoq_owner_car(public.vehicles, uuid, numeric),
  public.ottoq_owner_read(public.ottoq_agent_principals, text, jsonb),
  ottoq.ottoq_owner_order_applies(public.ottoq_owner_settings),
  ottoq.ottoq_owner_service_atom(public.ottoq_owner_settings, uuid),
  ottoq.ottoq_owner_merge_atom(jsonb, public.ottoq_owner_settings, uuid),
  ottoq.ottoq_owner_unmerge_atoms(jsonb, uuid),
  ottoq.ottoq_owner_orders_tick(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

--: ottoq_departure_clear is SECURITY INVOKER. Measured: anon may execute it but not the effective target it calls first,
--: so for anon it already raises before it could reach this helper; authenticated and service_role reach both. The
--: helper is granted to exactly those two, so the departure test answers for every role it answered for before.
GRANT EXECUTE ON FUNCTION public.ottoq_owner_departure_blocked(uuid, uuid, timestamptz) TO authenticated, service_role;

COMMENT ON FUNCTION ottoq.ottoq_owner_orders_tick(uuid, timestamptz) IS
'0605. The tick applies what owners set: re-targets cars whose charge limit changed (vehicles.target_soc, the open visit''s target, its charge atom), puts active service orders on open visits and takes withdrawn ones off, closes reached holds and done orders, and writes one ottoq.owner_settings_applied event per tick that changed something. Called by public.ottoq_sim_advance_tick_world before the visit-atom step. Inert (one index probe) on a run with no owner settings.';
COMMENT ON FUNCTION public.ottoq_owner_command(public.ottoq_agent_principals, text, jsonb) IS
'0605. The seven owner commands (set_charge_limit, clear_charge_limit, request_service, cancel_service, hold_vehicle, release_hold, undo_command), reachable only through ottoq_agent_call with the owner_settings capability. Checks shapes, replays an idempotency key, resolves cars inside the token''s scope, checks the contract and OTTO-Q''s rules, requires a live demo run, plans every car''s before -> after, records the command (previews and refusals too) and, on apply, writes ottoq_owner_settings for the tick to apply. Writes ottoq_owner_* tables only.';
COMMENT ON FUNCTION public.ottoq_owner_departure_blocked(uuid, uuid, timestamptz) IS
'0605. True while a car''s owner holds it at the depot past this clock, or an owner service order placed this tick still waits for the tick that puts it on the visit (at most one sim hour). Read by ottoq_departure_clear.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════

-- V1: the world step is the measured body plus the one step, once, and nothing else
DO $v1$
DECLARE
  v_old  text := (SELECT definition FROM public.ottoq_schema_snapshots
                   WHERE label = '0605_pre' AND object_name = 'ottoq_sim_advance_tick_world'
                   ORDER BY snapshot_id DESC LIMIT 1);
  v_new  text := pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);
  v_step text := current_setting('ottoq.m0605_step', true);
BEGIN
  IF COALESCE(v_step, '') = '' OR v_old IS NULL
     OR length(v_new) - length(replace(v_new, v_step, '')) <> length(v_step)
     OR replace(v_new, v_step, '') IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION '0605 V1: the world step is not the measured body plus the owner step, once';
  END IF;
END $v1$;

-- V2: INERT, MEASURED. With no owner setting anywhere (true at apply: the tables are new), every twin-depot car's
-- effective target and both departure verdicts on the latest run are what they were before this file, and the tick
-- step does nothing.
DO $v2$
DECLARE v_diff int; v_n int; v_run uuid; v_clock timestamptz;
BEGIN
  SELECT x.sim_run_id, x.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs x
   WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY x.started_at DESC LIMIT 1;
  SELECT count(*), count(*) FILTER (WHERE
           b.target IS DISTINCT FROM public.ottoq_effective_target_soc_at(b.vehicle_id, COALESCE(v_clock, now()))
        OR b.clear_full IS DISTINCT FROM public.ottoq_departure_clear(b.vehicle_id, v_run, COALESCE(v_clock, now()), true)
        OR b.clear_recheck IS DISTINCT FROM public.ottoq_departure_clear(b.vehicle_id, v_run, COALESCE(v_clock, now()), false))
    INTO v_n, v_diff
    FROM m0605_before b;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0605 V2: % of % twin-depot cars read a different target or departure verdict after this file', v_diff, v_n;
  END IF;
  IF ottoq.ottoq_owner_orders_tick(v_run, COALESCE(v_clock, now())) <> 0 THEN
    RAISE EXCEPTION '0605 V2: the tick step acted on a run with no owner settings';
  END IF;
  RAISE NOTICE '0605 V2: % twin-depot cars read the same target and departure verdicts before and after', v_n;
END $v2$;

-- V3: grants, measured rather than trusted (0405's "REVOKE that removed nothing")
DO $v3$
DECLARE v_fn regprocedure; v_tbl text;
BEGIN
  FOREACH v_tbl IN ARRAY ARRAY['public.ottoq_owner_commands', 'public.ottoq_owner_settings'] LOOP
    IF has_table_privilege('anon', v_tbl, 'SELECT') OR has_table_privilege('authenticated', v_tbl, 'SELECT')
       OR has_table_privilege('service_role', v_tbl, 'SELECT') OR has_table_privilege('service_role', v_tbl, 'INSERT')
       OR has_table_privilege('service_role', v_tbl, 'UPDATE') OR has_table_privilege('service_role', v_tbl, 'DELETE')
       OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = v_tbl::regclass)
       OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = v_tbl::regclass) THEN
      RAISE EXCEPTION '0605 V3: % is reachable by a client role, or lacks RLS-with-no-policy', v_tbl;
    END IF;
  END LOOP;
  FOR v_fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname IN ('public', 'ottoq') AND (p.proname LIKE 'ottoq\_owner\_%' OR p.proname IN
                     ('ottoq_tg_owner_orders_on_new_visit', 'ottoq_tg_lift_owner_settings_on_terminal'))
                 AND p.proname <> 'ottoq_owner_departure_blocked' LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0605 V3: % is executable by a client role', v_fn;
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.ottoq_owner_departure_blocked(uuid,uuid,timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_owner_departure_blocked(uuid,uuid,timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_owner_departure_blocked(uuid,uuid,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION '0605 V3: the departure helper is not granted to exactly the roles that reach the departure test''s target';
  END IF;
  -- 0559's grants survive the replacements (CREATE OR REPLACE keeps them; measured, not assumed)
  IF has_function_privilege('anon', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.ottoq_agent_read_whoami(public.ottoq_agent_principals)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '0605 V3: a replaced function''s grants changed';
  END IF;
END $v3$;

-- V4: registered, and the guard is clean
DO $v4$
DECLARE v_block int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_owner_settings' AND column_name = 'sim_run_id' AND class = 'engine')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_owner_commands' AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0605 V4: an owner table is not registered as this file says';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0605 V4: the registry guard now reports % blocking defect(s)', v_block;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE table_name LIKE 'ottoq\_owner\_%') THEN
    RAISE EXCEPTION '0605 V4: the registry guard reports an ottoq_owner_* table';
  END IF;
END $v4$;

-- V5: WHAT AN AGENT'S TOKEN CAN REACH writes only the agent and owner ledgers and names no engine door, and no
-- function of the engine's own side. Comment-stripped and whitespace-tolerant; FOR UPDATE / DO UPDATE are row locks
-- and upserts, not writes to a table named after them.
DO $v5$
DECLARE v_fn regprocedure; v_src text; v_target text;
BEGIN
  FOR v_fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public'
                 AND (p.proname IN ('ottoq_agent_call', 'ottoq_agent_read_whoami', 'ottoq_agent_read_depot',
                                    'ottoq_agent_read_fleet', 'ottoq_agent_read_vehicle', 'ottoq_agent_read_decisions',
                                    'ottoq_agent_read_stalls', 'ottoq_agent_read_requests', 'ottoq_agent_submit_request')
                      OR (p.proname LIKE 'ottoq\_owner\_%'
                          AND p.proname NOT IN ('ottoq_owner_charge_limit', 'ottoq_owner_departure_blocked',
                                                'ottoq_owner_commands_guard'))) LOOP
    v_src := regexp_replace(regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = v_fn), '/\*.*?\*/', '', 'g'),
                            '--[^' || chr(10) || ']*', '', 'g');
    v_src := regexp_replace(v_src, '(for|do)[[:space:]]+update', '', 'gi');
    IF v_src ~* '(ottoq_hw_recall_vehicle|ottoq_apply_ops_action|ottoq_agent_request_decide|ottoq_submit_external_proposal|ottoq_policy_set|ottoq_hw_set_return_threshold|ottoq_owner_orders_tick|ottoq_owner_merge_atom|ottoq_owner_unmerge_atoms|ottoq_plan_visit_itinerary|ottoq_record_event)' THEN
      RAISE EXCEPTION '0605 V5: % names an engine door or the engine''s own side', v_fn;
    END IF;
    FOR v_target IN
      SELECT lower(regexp_replace(m[2], '^public\.', ''))
        FROM regexp_matches(v_src, '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+([a-z_.]+)', 'gi') AS m
    LOOP
      IF v_target NOT LIKE 'ottoq\_agent\_%' AND v_target NOT LIKE 'ottoq\_owner\_%' THEN
        RAISE EXCEPTION '0605 V5: % writes to % (the agent side may write only ottoq_agent_* and ottoq_owner_* tables)', v_fn, v_target;
      END IF;
    END LOOP;
  END LOOP;
END $v5$;

-- V6: the hooks are where §2 says, and the two triggers fire on what §2 says
DO $v6$
BEGIN
  IF position('public.ottoq_owner_charge_limit(v.id)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'::regprocedure)) = 0
     OR position('public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure)) = 0
     OR position('ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0605 V6: a hook is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.ottoq_visit_needs'::regclass
                    AND t.tgname = 'ottoq_visit_needs_owner_orders_trg' AND (t.tgtype & 2) = 2 AND (t.tgtype & 4) = 4)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.ottoq_sim_runs'::regclass
                       AND t.tgname = 'ottoq_sim_runs_lift_owner_settings'
                       AND pg_get_triggerdef(t.oid) LIKE '%(new.status = ANY (ARRAY[''completed''::text, ''failed''::text, ''aborted''::text]))%') THEN
    RAISE EXCEPTION '0605 V6: a trigger is missing or fires on the wrong event';
  END IF;
END $v6$;

-- V7: THE OWNER'S DOOR, EXECUTED AND ROLLED BACK, against the live fleet and contract. Each step can fail.
DO $probe$
DECLARE
  v        jsonb;
  v_hash   text;
  v_tesla  uuid := '33333333-3333-3333-3333-333333333333';
  v_twin   uuid := '11111111-1111-1111-1111-111111111111';
  v_agent  public.ottoq_agent_principals;
  v_min    numeric;
  v_other  uuid;
  v_ok     boolean;
  v_live   jsonb := public.ottoq_agent_live_run('11111111-1111-1111-1111-111111111111');
BEGIN
  BEGIN
    v := public.ottoq_agent_issue_token('probe-0605-v7', 'personal', ARRAY['read', 'note', 'owner_settings'], v_tesla,
                                        v_twin, '0605 V7, rolled back', 600, 5);
    IF NOT COALESCE((v ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0605 V7a: issue refused: %', v - 'token'; END IF;
    v_hash := encode(sha256(convert_to(v ->> 'token', 'UTF8')), 'hex');
    SELECT * INTO v_agent FROM public.ottoq_agent_principals WHERE name = 'probe-0605-v7';

    v := public.ottoq_agent_issue_token('probe-0605-v7b', 'personal', ARRAY['read', 'owner_settings'], NULL, v_twin, NULL, 60, 5);
    IF v ->> 'error' IS DISTINCT FROM 'owner_settings_needs_a_fleet' THEN
      RAISE EXCEPTION '0605 V7b: owner_settings without a fleet was not refused: %', v - 'token';
    END IF;

    v := public.ottoq_agent_call(v_hash, 'whoami', '{}'::jsonb, 'rest', '{}'::jsonb);
    v_min := (public.ottoq_owner_contract(v_tesla, now()) ->> 'min_charge_pct')::numeric;
    IF (v #>> '{data,owner,charge_limit_pct,min}')::numeric IS DISTINCT FROM v_min THEN
      RAISE EXCEPTION '0605 V7c: whoami does not carry the owner''s contract range: %', v -> 'data';
    END IF;

    v := public.ottoq_agent_call(v_hash, 'my_fleet', '{}'::jsonb, 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::int <> 200
       OR (v #>> '{data,total}')::int IS DISTINCT FROM (SELECT count(*)::int FROM public.ottoq_owner_fleet(v_agent))
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(v #> '{data,cars}') c JOIN public.vehicles x ON x.id = (c ->> 'vehicle_id')::uuid
                   WHERE x.fleet_operator_id IS DISTINCT FROM v_tesla
                      OR NOT (x.home_depot_id = v_twin OR x.current_depot_id = v_twin)) THEN
      RAISE EXCEPTION '0605 V7d: my_fleet read outside the token''s scope: %', v ->> 'error';
    END IF;

    v := public.ottoq_agent_call(v_hash, 'set_charge_limit',
           jsonb_build_object('vehicles', 'all', 'percent', v_min - 10, 'mode', 'preview'), 'rest', '{}'::jsonb);
    IF (v ->> 'http_status')::int <> 422 OR v #>> '{error,code}' IS DISTINCT FROM 'below_contract_minimum'
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_owner_commands c WHERE c.principal_id = v_agent.principal_id
                         AND c.outcome = 'refused' AND c.refusal ->> 'code' = 'below_contract_minimum') THEN
      RAISE EXCEPTION '0605 V7e: a limit below the contract was not refused and recorded: %', v;
    END IF;

    v := public.ottoq_agent_call(v_hash, 'set_charge_limit',
           '{"vehicles": ["Tesla 98"], "percent": 90, "mode": "preview"}'::jsonb, 'rest', '{}'::jsonb);
    IF v #>> '{error,code}' IS DISTINCT FROM 'vehicle_not_found' THEN
      RAISE EXCEPTION '0605 V7f: a car that does not exist was not refused: %', v;
    END IF;

    SELECT x.id INTO v_other FROM public.vehicles x
     WHERE x.fleet_operator_id IS DISTINCT FROM v_tesla AND (x.home_depot_id = v_twin OR x.current_depot_id = v_twin)
     ORDER BY x.id LIMIT 1;
    IF v_other IS NOT NULL THEN
      v := public.ottoq_agent_call(v_hash, 'request_service',
             jsonb_build_object('vehicles', jsonb_build_array(v_other::text), 'service', 'exterior_wash', 'mode', 'preview'),
             'rest', '{}'::jsonb);
      IF v #>> '{error,code}' IS DISTINCT FROM 'vehicle_not_found' THEN
        RAISE EXCEPTION '0605 V7g: another owner''s car was not out of scope: %', v;
      END IF;
    END IF;

    v := public.ottoq_agent_call(v_hash, 'request_service',
           '{"vehicles": "all", "service": "fault_repair", "mode": "preview"}'::jsonb, 'rest', '{}'::jsonb);
    IF v #>> '{error,code}' IS DISTINCT FROM 'service_not_requestable' THEN
      RAISE EXCEPTION '0605 V7h: a service owners may not request was not refused: %', v;
    END IF;

    v := public.ottoq_agent_call(v_hash, 'set_charge_limit',
           '{"vehicles": "all", "percent": 90, "mode": "preview"}'::jsonb, 'rest', '{}'::jsonb);
    IF v_live ->> 'run_by' = 'operator_demo' THEN
      IF (v ->> 'http_status')::int <> 200 OR v #>> '{data,outcome}' IS DISTINCT FROM 'previewed'
         OR EXISTS (SELECT 1 FROM public.ottoq_owner_settings) THEN
        RAISE EXCEPTION '0605 V7i: a preview on the live demo did not preview, or changed something: %', v;
      END IF;
    ELSIF v #>> '{error,code}' IS DISTINCT FROM 'no_live_demo' THEN
      RAISE EXCEPTION '0605 V7i: with no live demo, a command was not refused: %', v;
    END IF;

    BEGIN
      UPDATE public.ottoq_owner_commands SET summary = 'edited' WHERE principal_id = v_agent.principal_id;
      v_ok := false;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0605 V7j: an owner command could be edited'; END IF;
    BEGIN
      DELETE FROM public.ottoq_owner_commands WHERE principal_id = v_agent.principal_id;
      v_ok := false;
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '0605 V7k: an owner command could be deleted'; END IF;

    RAISE EXCEPTION USING ERRCODE = 'OQA99', MESSAGE = '0605_v7_rollback';
  EXCEPTION WHEN SQLSTATE 'OQA99' THEN
    NULL;  -- everything above is undone; each step proved what it set out to
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_principals WHERE name LIKE 'probe-0605-v7%')
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_commands)
     OR EXISTS (SELECT 1 FROM public.ottoq_owner_settings) THEN
    RAISE EXCEPTION '0605 V7: the probe survived its own rollback';
  END IF;
END $probe$;

-- Rollback: re-create the six functions from their '0605_pre' snapshots (ottoq_sim_advance_tick_world,
-- ottoq_effective_target_soc_at, ottoq_departure_clear, ottoq_agent_call, ottoq_agent_issue_token,
-- ottoq_agent_read_whoami); DROP TRIGGER ottoq_visit_needs_owner_orders_trg ON ottoq_visit_needs and
-- ottoq_sim_runs_lift_owner_settings ON ottoq_sim_runs; DROP every ottoq_owner_* function and the two ottoq_tg_*
-- functions this file created; DROP TABLE ottoq_owner_settings, then ottoq_owner_commands; drop
-- ottoq_agent_principals_owner_scope_check (revoke any principal holding owner_settings first; 0559's capabilities CHECK
-- stays as 0559 created it); DELETE the two registry rows, the event-catalog row and this file's ottoq_cert_lineage row.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back', true, true,
  'Owner settings through an owner''s agent (Chase 2026-10-02): charge limit, service orders, holds, on a live operator_demo run only, lifted at the run''s end. Hooks ottoq_effective_target_soc_at (the owner''s limit, 0539''s reserved slot), ottoq_departure_clear (holds; an order waiting for its tick), the world step (ottoq.ottoq_owner_orders_tick before the visit-atom step), a BEFORE INSERT trigger on ottoq_visit_needs and an AFTER UPDATE OF status trigger on ottoq_sim_runs. Every hook is inert without an owner row, which no certification, dial or sweep arm can hold (the dispatcher refuses any run but a live demo, and no arm starts while one is live); V2 measured it on every twin-depot car. Classified TRUE anyway because three tick-path bodies change and a migration cannot run a pair.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
