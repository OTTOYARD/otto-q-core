-- migration-version: 20260831140000
-- migration-name:    the_power_cap_is_a_constraint
-- 0132 -- GAP 1 of db/checks/0052: the site power cap was accounted and never enforced.
--
-- WHAT WAS WRONG. public.ottoq_decide_tick already computed everything a constraint needs and
-- then never compared any of it:
--     line  16   v_charge_cap_kw numeric;  v_ev_committed_kw numeric := 0;
--     line 181   v_charge_cap_kw := ottoq_active_charge_cap_kw(run, depot, clock);
--     line 183   SELECT ...taper-weighted sum... INTO v_ev_committed_kw   (vehicles now charging)
--     line 289   PERFORM ottoq_claim_tick_kw(run, tick, depot, requested_kw, vehicle);
--     line 335   v_ev_committed_kw := v_ev_committed_kw + requested_kw;
-- No relational test between the cap and the committed load exists anywhere in the function.
-- ottoq_active_charge_cap_kw is a pure SELECT; ottoq_claim_tick_kw is a pure INSERT returning a
-- uuid with no rejection path. The claims ledger holds 103,489 rows over 222 runs and its only
-- reader (ottoq_tick_claimed_kw) has ZERO callers. So no charge was ever refused for site power,
-- and peak_site_kw -- the demand-charge KPI the C8 economics rest on -- was an outcome the core
-- measured and could not move.
--
-- WHICH CAP. Three different "caps" existed and the decide path read the wrong one:
--   depots.service_max_kw            2500 kW on the flagship and benchmark depots -- the
--                                    PHYSICAL service limit, populated, and previously read by
--                                    NOTHING in the decide path.
--   ottoq_energy_commands            the MPC/DR setpoint, 221 executed rows spanning
--     command_type='charge_cap_kw'   795-13,182 kW -- i.e. it regularly "authorises" up to 5x
--                                    more than the site can physically deliver.
--   twin.ottoq_sim_advance_site_energy's hardcoded v_service_cap_kw := 2500 (observation only).
-- The correct semantic is that the physical limit ALWAYS binds and a demand-response or MPC
-- setpoint may only tighten it further, never raise it. New helper
-- public.ottoq_effective_charge_cap_kw returns LEAST(physical, setpoint) -- LEAST ignores NULLs,
-- so a depot with no service_max_kw and no active setpoint yields NULL and the gate stays off,
-- which keeps every depot that is not configured behaving exactly as before.
--
-- THE GATE. Inserted where the proposal becomes an action, BEFORE the stall is reserved and
-- before any command is emitted, so a refused charge consumes no stall, emits no command and
-- claims no kW. It falls through to the existing decision INSERT, so every refusal is audited
-- with its own reason code rather than vanishing.
--     v_action:=v_proposal;
--     IF <cap set> AND <policy on> AND committed + requested > cap THEN
--          v_outcome:='deferred_site_power_cap'; v_deferred:=v_deferred+1;
--     ELSIF ottoq_reserve_stall(...) THEN  ...enact as before...
-- Kill switch: policy 'enforce_site_charge_cap' (default 1). Set 0 to restore the old
-- behaviour without a migration.
--
-- WHY THE CHECK CONSTRAINT MOVES TOO. ottoq_decisions.outcome_status carries a CHECK allowlist
-- of eight values. Writing a ninth would abort the tick, so the constraint is extended in the
-- same migration. Reusing 'deferred_noop' was rejected deliberately: a power-cap refusal must be
-- countable on its own, or the one thing we now want to measure -- how often the cap binds --
-- is indistinguishable from every other no-op in the audit trail.
--
-- DETERMINISM. The gate is pure arithmetic over run-scoped values already in scope: no clock
-- read, no new ordering, no heap-fed pick. It changes BEHAVIOUR, so all six certification
-- columns must be re-run (db/checks/0050); expect one transition pair per column.
--
-- Pre-image pin, read live 2026-08-31 (both anchors asserted at exactly 1 occurrence):
--   public.ottoq_decide_tick   180ad17c4c05359ffda7aad30f2a0ccb

-- 1. The reason code becomes legal before any code can emit it.
ALTER TABLE public.ottoq_decisions DROP CONSTRAINT IF EXISTS ottoq_decisions_outcome_status_check;
ALTER TABLE public.ottoq_decisions ADD CONSTRAINT ottoq_decisions_outcome_status_check
  CHECK (outcome_status = ANY (ARRAY[
    'enacted','overridden_to_default','deferred_noop','errored','noop_no_candidate',
    'shield_disarmed','deferred_stale_entity','context_insufficient',
    'deferred_site_power_cap'  -- 0132
  ]));

-- 2. The effective cap: physical limit, tightened (never raised) by an active setpoint.
CREATE OR REPLACE FUNCTION public.ottoq_effective_charge_cap_kw(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz)
RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'twin','ottoq','public','extensions'
AS $function$
  -- LEAST ignores NULLs: an unconfigured depot with no active setpoint yields NULL, and the
  -- caller's gate stays off. The physical limit can never be raised by a setpoint.
  SELECT LEAST(
           (SELECT d.service_max_kw FROM public.depots d WHERE d.id = p_depot_id),
           public.ottoq_active_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock)
         );
$function$;

COMMENT ON FUNCTION public.ottoq_effective_charge_cap_kw(uuid,uuid,timestamptz) IS
'0132: the site charge cap the decide path plans against. depots.service_max_kw is the physical service limit and always binds; an MPC/DR setpoint may only tighten it. NULL means no cap configured, and the caller must then not gate.';

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  a_old text := 'v_charge_cap_kw := ottoq_active_charge_cap_kw(p_sim_run_id, v_depot, v_clock);';
  a_new text := 'v_charge_cap_kw := public.ottoq_effective_charge_cap_kw(p_sim_run_id, v_depot, v_clock);  /* 0132 */';
  b_old text := E'      v_action:=v_proposal;\n      IF ottoq_reserve_stall(';
  b_new text := E'      v_action:=v_proposal;\n'
             || E'      /* 0132: THE SITE POWER CAP IS A CONSTRAINT, NOT A NOTE. Refuse before the stall is\n'
             || E'         reserved and before any command is emitted, so a refusal costs nothing and still\n'
             || E'         falls through to the decision INSERT with its own reason code. */\n'
             || E'      IF v_charge_cap_kw IS NOT NULL\n'
             || E'         AND public.ottoq_policy_get(p_sim_run_id, ''enforce_site_charge_cap'', 1) >= 1\n'
             || E'         AND (COALESCE(v_ev_committed_kw,0) + COALESCE((v_action->>''requested_kw'')::numeric,0)) > v_charge_cap_kw THEN\n'
             || E'        v_outcome:=''deferred_site_power_cap''; v_deferred:=v_deferred+1;\n'
             || E'      ELSIF ottoq_reserve_stall(';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_decide_tick' AND p.prokind='f';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '180ad17c4c05359ffda7aad30f2a0ccb' THEN
    RAISE EXCEPTION '0132 abort: decide_tick drifted (md5 %)', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, a_old, ''))) / length(a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0132 abort: anchor A found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, b_old, ''))) / length(b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0132 abort: anchor B found % times', v_cnt; END IF;

  EXECUTE replace(replace(v_src, a_old, a_new), b_old, b_new);

  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0132 */', ''))) / length('/* 0132 */');
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0132 abort: marker survived % times', v_cnt; END IF;
  IF position('deferred_site_power_cap' in v_src) = 0 THEN
    RAISE EXCEPTION '0132 abort: the gate did not survive';
  END IF;
  IF position('ELSIF ottoq_reserve_stall(' in v_src) = 0 THEN
    RAISE EXCEPTION '0132 abort: the reserve branch was not rewired to ELSIF';
  END IF;
  RAISE NOTICE '0132 applied: the power cap is a constraint.';
END
$patch$;

-- 3. Post-conditions that would have caught the two ways this could ship broken.
DO $verify$
DECLARE v_cap numeric; v_n int;
BEGIN
  SELECT public.ottoq_effective_charge_cap_kw(NULL, '11111111-1111-1111-1111-111111111111'::uuid, now())
    INTO v_cap;
  IF v_cap IS DISTINCT FROM 2500 THEN
    RAISE EXCEPTION '0132 abort: flagship effective cap is %, expected the 2500 kW physical limit', v_cap;
  END IF;

  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid='public.ottoq_decisions'::regclass AND conname='ottoq_decisions_outcome_status_check'
     AND pg_get_constraintdef(oid) LIKE '%deferred_site_power_cap%';
  IF v_n <> 1 THEN RAISE EXCEPTION '0132 abort: the reason code is not legal on ottoq_decisions'; END IF;

  RAISE NOTICE '0132 verified: flagship cap 2500 kW, reason code legal.';
END
$verify$;
