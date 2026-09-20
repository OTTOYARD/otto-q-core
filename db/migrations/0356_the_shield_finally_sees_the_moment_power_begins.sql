-- migration-version: 20260919235738
-- migration-name:    the_shield_finally_sees_the_moment_power_begins
--
-- 0356  THE SIXTH CALLED PROBE POINT, AND THE FIRST ONE THAT WATCHES ELECTRONS.
--
-- Part two of two for G74 (0355 fixed the two evaluators). This adds the
-- `charge_session_start` probe to `twin.ottoq_sim_start_charge_session` -- the
-- single routine in the database that opens a charge session, and therefore the
-- one place where "is there room on the grid for this car" is a gate rather than
-- a forecast.
--
-- Five ACTIVE rules declare this action context and every one is
-- `enforcement='block'`: EN.001 grid capacity (safety_critical), EN.002 stall
-- power ceiling, EN.004 demand-response compliance, EN.005 grid event hardstop
-- (safety_critical), HW.002 charger state precondition. **None had ever been
-- evaluated, because nothing had ever probed here.** So the energy-safety cluster
-- between the orchestrator and the switchgear has never run. 0355's header has
-- the pre-flight; the short version is that all five were shadow-called against
-- the live run with their own registered parameters and the sim clock, and all
-- five pass on a healthy Available charger.
--
-- ── MEASURED, NOT ENFORCED, AND THAT IS THE POINT ──────────────────────────────
--
-- This probe RECORDS. It does not refuse a session, even when a rule says
-- `would_block`. CLAUDE.md 2.9a: an atom is added MEASURED first and ENFORCED
-- only after a flagship round shows the arms agree (0139 / 0206 / 0217 / 0225),
-- and 0353 followed the same order for the AI write path. Wiring five
-- never-executed block rules straight to enforcing is how a demo dies at the
-- worst possible moment. Promotion is a later, deliberate step; it reads
-- `would_block`, which is why this calls `ottoq_shield_probe` (9 columns,
-- including that one) rather than `ottoq_evaluate_rules_for_action` (5, without).
--
-- ── FOUR PLACEMENT DECISIONS, EACH ONE A TRAP THIS REPO HAS ALREADY PAID FOR ───
--
-- 1. BEFORE the `INSERT INTO ocpp_sessions`, never after. EN.001 computes
--    `ottoq_depot_current_demand_kw(depot, now_ts)`, and once the row exists that
--    sum INCLUDES the session being started -- the check would double-count its
--    own load and every evaluation would be wrong by one car, in the direction
--    that makes the depot look closer to its cap than it is.
--
-- 2. `p_entity_id := p_stall_id`, NEVER `v_session_id`. The session id is
--    `gen_random_uuid()` minted at DECLARE, so it differs between the two arms of
--    a determinism pair, and `ottoq_hash_rule_evaluations` DIGESTS `entity_id`.
--    Every certification pair would have disagreed on `h_rule` and the cause
--    would have looked like anything except this file. Fifth instance of 0139's
--    class, after 0137, 0139, 0280 and 0353 -- which is once more than a comment
--    can be trusted to prevent, so A4 asserts it. A stall is a pre-existing row
--    and arm-stable; the hash function's own comment says exactly that.
--
-- 3. `now_ts := v_clock`, the SIM clock, never `now()`. Passing wall clock makes
--    every charger read eight hours stale against a 90-second offline threshold
--    and HW.002 refuses the entire depot -- measured, that is the false reading
--    0355's pre-flight produced before it was corrected. A wall clock inside a
--    certified path is G15's defect class.
--
-- 4. Wrapped in `EXCEPTION WHEN OTHERS THEN RAISE WARNING`, the pattern this
--    function already uses for the arm cycle and the travel leg. A shield probe
--    must never abort a charge session, and per CLAUDE.md a failure must never
--    abort the tick path. A5 asserts the handler is present in the body.
--
-- The run id is set as a transaction-local GUC before probing so the evaluations
-- are attributed to this run even though `ottoq_shield_probe` takes no run
-- argument -- the same idiom `ottoq_sim_stop_and_reset` uses (0092).
--
-- ── WHAT THIS DOES NOT DO ──────────────────────────────────────────────────────
--
-- It does not enforce. It does not wire `power_increase`, the other
-- declared-never-called energy context, which needs a throttle path that does not
-- exist. It does not change `task_start`'s abstentions -- they are correct, and
-- 0355 made them say so. And it is not a claim that the grid is the binding
-- constraint: measured on the live run the worst case was 712.6 kW against a
-- 1,620 kW engineering cap, so this depot is STALL-constrained with roughly
-- 908 kW spare at peak.
--
-- forces_recert: TRUE. It adds rule evaluations at a new action_context, and
-- `ottoq_hash_rule_evaluations` digests every evaluation. Classified TRUE rather
-- than argued down.
--
-- Applied through the Management API, so the `schema_migrations` row is written
-- explicitly -- see 0354's header for why that is mandatory on this path.

BEGIN;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ── PRECONDITIONS ──────────────────────────────────────────────────────────────
DO $pre$
DECLARE v_jobs text; v_pairs int; v_live text; v_block int; v_n int; v_src text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0356 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0356 P1: % certification pair(s) are active', v_pairs;
  END IF;

  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0356 P2: applying while Twin run(s) % are active -- tainted for reproducibility from here, deliberately', v_live;
  END IF;

  -- P3. 0355 must already be in place: this probe fires evaluators, and EN.001's
  -- labelling and HW.002's repaired fallback are what make the results readable
  -- and correct. Applying 0356 first would work but would record 0355's defects.
  IF position('en001_evaluated' in
        (SELECT prosrc FROM pg_proc WHERE proname='ottoq_eval_en_001_grid_capacity')) = 0 THEN
    RAISE EXCEPTION '0356 P3: 0355 is not applied (EN.001 carries no en001_evaluated label)';
  END IF;

  -- P4. Not already applied. position(), NOT LIKE: `_` is a LIKE wildcard, and
  -- `prosrc LIKE '%charge_session_start%'` matches the `charge.session_started`
  -- event type this function already emits because `_` matched the `.`. That
  -- false positive aborted 0355's first dry-run.
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0356 P4a: twin.ottoq_sim_start_charge_session not found';
  END IF;
  IF position('charge_session_start' in v_src) > 0 THEN
    RAISE EXCEPTION '0356 P4b: the probe is already present';
  END IF;

  -- P5. The anchor this migration substitutes on must appear EXACTLY ONCE, or the
  -- rewrite would land in the wrong place or not at all. An anchored substitution
  -- that silently matches nothing is worse than a failed migration.
  IF (length(v_src) - length(replace(v_src, 'INSERT INTO ocpp_sessions', ''))) / length('INSERT INTO ocpp_sessions') <> 1 THEN
    RAISE EXCEPTION '0356 P5: the INSERT INTO ocpp_sessions anchor does not appear exactly once';
  END IF;

  -- P6. The five rules must still be what fires here, so 0355's pre-flight still
  -- describes this probe's blast radius.
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE status='active' AND applies_to_actions @> ARRAY['charge_session_start']::text[];
  IF v_n <> 5 THEN
    RAISE EXCEPTION '0356 P6: expected 5 active rules at charge_session_start, found % -- re-run the pre-flight', v_n;
  END IF;

  -- P7. ottoq_shield_probe must expose would_block, which promotion will read.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      CROSS JOIN LATERAL unnest(p.proargnames) a(nm)
     WHERE n.nspname='public' AND p.proname='ottoq_shield_probe' AND a.nm='would_block') THEN
    RAISE EXCEPTION '0356 P7: ottoq_shield_probe does not return would_block';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0356 P8: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── THE SUBSTITUTION ───────────────────────────────────────────────────────────
-- Anchored rewrite rather than a full re-declaration: the function is ~8.6 KB of
-- charge-curve, OCPP-emission, arm-cycle and render-contract logic that this
-- change has no business retyping. P5 proved the anchor is unique; A1 proves the
-- probe landed before the insert rather than after it.
DO $rewrite$
DECLARE
  v_src    text;
  v_probe  text;
  v_new    text;
  v_anchor text := '  INSERT INTO ocpp_sessions (';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';

  v_probe := concat_ws(E'\n',
    '  -- ═══════════ 0356: THE SHIELD SEES POWER BEGIN ═══════════',
    '  -- Five block-enforcement rules declare charge_session_start -- EN.001 grid',
    '  -- capacity, EN.002 stall power ceiling, EN.004 demand response, EN.005 grid',
    '  -- event hardstop, HW.002 charger state -- and until this probe existed not one',
    '  -- of them had ever been evaluated, because nothing probed here. This is the',
    '  -- moment power actually begins, which makes it the gate rather than a forecast.',
    '  --',
    '  -- MEASURED, NOT ENFORCED: the probe records and does NOT refuse the session,',
    '  -- even on would_block. CLAUDE.md 2.9a -- measured first, enforced after a',
    '  -- flagship round. Promotion reads ottoq_shield_probe.would_block.',
    '  --',
    '  -- IT SITS BEFORE THE INSERT ON PURPOSE. EN.001 reads',
    '  -- ottoq_depot_current_demand_kw(depot, now_ts); after the insert that sum',
    '  -- already contains this session and the check double-counts its own load.',
    '  --',
    '  -- entity_id IS p_stall_id, NOT v_session_id: the session id is gen_random_uuid()',
    '  -- and differs between determinism-pair arms, and ottoq_hash_rule_evaluations',
    '  -- digests entity_id (0139''s class, fifth instance). A stall is arm-stable.',
    '  -- now_ts IS v_clock, the SIM clock: wall clock makes every charger read stale',
    '  -- against HW.002''s 90-second threshold and refuses the whole depot.',
    '  -- Never allowed to abort the session.',
    '  BEGIN',
    '    PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);',
    '    PERFORM 1 FROM public.ottoq_shield_probe(',
    '      p_action_context    := ''charge_session_start'',',
    '      p_entity_type       := ''stall'',',
    '      p_entity_id         := p_stall_id,',
    '      p_context           := jsonb_build_object(',
    '                               ''depot_id'',     v_stall.depot_id::text,',
    '                               ''stall_id'',      p_stall_id::text,',
    '                               ''charger_id'',    v_charger.charger_id::text,',
    '                               ''requested_kw'',  LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),',
    '                               ''now_ts'',        v_clock::text),',
    '      p_fleet_operator_id := v_vehicle.fleet_operator_id,',
    '      p_depot_id          := v_stall.depot_id);',
    '  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''charge_session_start shield probe: %'', SQLERRM;',
    '  END;',
    '');

  v_new := replace(v_src, v_anchor, v_probe || v_anchor);

  IF v_new = v_src THEN
    RAISE EXCEPTION '0356 R1: the anchored substitution changed nothing';
  END IF;
  IF position('charge_session_start' in v_new) = 0 THEN
    RAISE EXCEPTION '0356 R2: the rewritten body does not contain the probe';
  END IF;

  EXECUTE v_new;
END $rewrite$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0356_the_shield_finally_sees_the_moment_power_begins', true,
  'Part two of two for G74 (0355 fixed the evaluators). Adds the charge_session_start shield probe to '
  'twin.ottoq_sim_start_charge_session, the only routine that opens a charge session. Five ACTIVE rules '
  'declare that context and all five are enforcement=block -- EN.001 grid capacity and EN.005 grid event '
  'hardstop are safety_critical -- and NONE had ever been evaluated, because nothing probed there. So the '
  'energy-safety cluster between the orchestrator and the switchgear had never run. FORCES RECERT because '
  'it adds rule evaluations at a new action_context and ottoq_hash_rule_evaluations digests every '
  'evaluation. MEASURED, NOT ENFORCED: it records and does not refuse a session even on would_block, per '
  'CLAUDE.md 2.9a and the order 0353 used for the AI write path; wiring five never-executed block rules '
  'straight to enforcing is how a depot stops. Placement: BEFORE the INSERT (after it, '
  'ottoq_depot_current_demand_kw already includes this session and EN.001 double-counts its own load); '
  'entity_id is p_stall_id not the gen_random_uuid() session id, because entity_id IS digested and a '
  'minted id differs between determinism-pair arms (0139''s class, fifth instance); now_ts is the SIM '
  'clock, because wall clock makes every charger read stale against HW.002''s 90-second threshold and '
  'refuses the whole depot. Wrapped so it can never abort a session.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE v_src text; v_p_probe int; v_p_insert int; v_block int;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session';

  -- A1. THE PROBE LANDED, AND IT LANDED BEFORE THE INSERT. The ordering is the
  -- correctness property, not the presence -- after the insert every evaluation
  -- would be wrong by one car's load.
  v_p_probe  := position('ottoq_shield_probe' in v_src);
  v_p_insert := position('INSERT INTO ocpp_sessions' in v_src);
  IF v_p_probe = 0 THEN
    RAISE EXCEPTION '0356 A1a: the probe is not in the function body';
  END IF;
  IF v_p_insert = 0 THEN
    RAISE EXCEPTION '0356 A1b: the INSERT anchor vanished from the body';
  END IF;
  IF v_p_probe > v_p_insert THEN
    RAISE EXCEPTION '0356 A1c: the probe sits AFTER the insert (probe at %, insert at %) -- EN.001 would double-count this session''s own load', v_p_probe, v_p_insert;
  END IF;

  -- A2. It probes the right action context.
  IF position('''charge_session_start''' in v_src) = 0 THEN
    RAISE EXCEPTION '0356 A2: the probe does not name charge_session_start';
  END IF;

  -- A3. THE SIM CLOCK, not the wall clock. `now()` inside this probe would make
  -- HW.002 refuse every charger; a wall clock in a certified path is G15's class.
  IF position('''now_ts'',        v_clock::text' in v_src) = 0 THEN
    RAISE EXCEPTION '0356 A3a: the probe does not pass v_clock as now_ts';
  END IF;

  -- A4. THE ARM-STABLE ENTITY, asserted rather than trusted, because this is the
  -- fifth instance of 0139's class and a comment has failed to prevent it four
  -- times. The probe must pass p_stall_id and must NOT pass v_session_id.
  IF position('p_entity_id         := p_stall_id' in v_src) = 0 THEN
    RAISE EXCEPTION '0356 A4a: the probe does not pass p_stall_id as the entity';
  END IF;
  IF position('p_entity_id         := v_session_id' in v_src) > 0 THEN
    RAISE EXCEPTION '0356 A4b: the probe passes the minted session id as entity_id -- every certification pair would disagree on h_rule';
  END IF;

  -- A5. The probe cannot abort a charge session.
  IF position('charge_session_start shield probe' in v_src) = 0 THEN
    RAISE EXCEPTION '0356 A5: the probe has no EXCEPTION handler naming itself';
  END IF;

  -- A6. And the function still does its actual job -- the rewrite must not have
  -- dropped anything. Spot-check the four load-bearing tails.
  IF position('ottoq_sim_emit_ocpp' in v_src) = 0
     OR position('charge.session_started' in v_src) = 0
     OR position('ottoq_itin_leg_open' in v_src) = 0
     OR position('ottoq_arm_begin_cycle' in v_src) = 0 THEN
    RAISE EXCEPTION '0356 A6: the anchored rewrite lost part of the original body';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0356 A7: the registry guard now reports % blocking defect(s)', v_block;
  END IF;

  RAISE NOTICE '0356 OK: probe at char %, insert at % -- probe precedes insert', v_p_probe, v_p_insert;
END $post$;

COMMIT;
