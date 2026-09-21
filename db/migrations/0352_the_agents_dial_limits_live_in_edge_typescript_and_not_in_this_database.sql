-- migration-version: 20260919205659
-- migration-name:    the_agents_dial_limits_live_in_edge_typescript_and_not_in_this_database
--
-- 0352  THE LIMITS THE AI OBEYS ARE NOT IN THIS DATABASE, AND THE CATALOG IS
--       WIDER THAN THEM ON HALF THE DIALS IT CAN WRITE.
--
-- Part one of two. 0352 puts the agent's envelope into the engine as data;
-- 0353 puts a rule at a policy_write probe point and wires the shield to it.
-- Split because the two have different `forces_recert` classifications and the
-- envelope is useful on its own -- the edge function can read it whether or not
-- the rule ever lands.
--
-- ── FIRST, A CORRECTION TO OUR OWN FINDING, BECAUSE IT OVERSTATED THE HOLE ──
--
-- G64 has been carried as "agent_calls_with_no_l1_rules = 1,120 of 1,120 --
-- every Nemotron call changes engine state with no L1 rule evaluated." The
-- count is right; the implication is not. Read end to end, the agent's dial
-- write passes FOUR guards before it reaches a row:
--
--   1. KNOBS -- a six-key allowlist in ottoq-orchestrator-agent. A key outside
--      it is not written at all; it is queued to ottoq_ops_approvals as
--      `nemotron_policy_out_of_whitelist` for a human.
--   2. a move cap of 3 per chain.
--   3. clampDial -- a +/-30% per-tick drift limiter plus a per-key range clamp.
--   4. ottoq_policy_set -- scope validation, NULL refusal (0306), unknown_param
--      refusal, the catalog's inclusive clamp, and the exclusive-bound refusal
--      (0303). Five refusal reasons, all RETURNED rather than raised, and the
--      edge function reads the enacted value back from the database.
--
-- So the AI is bounded. It is not bounded BY THE SHIELD, which is a different
-- sentence with two consequences. This file addresses the first.
--
-- ── THE FINDING: THE ENVELOPE IS NOT IN THE ENGINE, AND IS TIGHTER THAN IT ──
--
-- Three of the six dials the agent may write are bounded only in edge
-- TypeScript, and on every one of those three the catalog is WIDER. Measured
-- today against ottoq_policy_param_catalog:
--
--   param_key                        edge lo/hi     catalog min/max
--   deploy_peak_fraction             0.5  - 1.0     0.30 - 1.00     differ
--   energy_demand_factor_peak        0.3  - 0.9     0.25 - 0.95     differ
--   energy_demand_factor_expensive   0.2  - 0.8     0.20 - 0.90     differ
--   deploy_surge_catchup             0.1  - 1.0     0.10 - 1.00     agree
--   forecast_horizon_min             10   - 90      10   - 90       agree
--   energy_reserve_shave             0    - 1       0    - 1        agree
--
-- The edge is TIGHTER in all three, so nothing unsafe has happened. But
-- ottoq_policy_set's own comment -- "when two allow-lists disagree the catalog
-- is the one that actually wrote the row" -- is mechanically true and
-- descriptively wrong: the edge clamps FIRST, so the catalog never sees an
-- out-of-envelope value and is the OUTER bound, not the effective one. Nothing
-- in this database can state, let alone check, what the agent is permitted to
-- do. An OEM auditor asking "what stops your model writing any of the 148
-- dials?" cannot be answered from the engine.
--
-- The envelope below is seeded from behaviour that has HELD, not from an
-- aspiration: ottoq_policy_params holds 1,269 rows written by `ottoq_prime`
-- across exactly the six keys KNOBS declares, and every value ever written sits
-- inside the edge envelope (0.5-1.0, 0.455-1.0, 0.20-0.8, 0.3-0.9, 1-1, 45-90).
--
-- ── WHAT IT DOES NOT DO ────────────────────────────────────────────────────
--
-- The edge function is NOT redeployed here. Until its next deploy reads
-- ottoq_agent_dial_envelope(), the engine's copy is a DECLARATION, and 0353
-- makes it a DETECTOR. It is not yet the enforcer. The repo's copy of that
-- function is stale against what is deployed (G67), so deploying from it would
-- regress production, and a hand-transcribed pull is exactly the silent
-- divergence _MANIFEST.md refuses.
--
-- forces_recert FALSE: four nullable/defaulted columns on a catalog table, a
-- data seed, and one STABLE read-only function. No verdict atom reads
-- ottoq_policy_param_catalog, and nothing on the tick path changes behaviour.

BEGIN;

-- ── P1  verify before building ────────────────────────────────────────────
DO $$
DECLARE v_have int;
BEGIN
  SELECT count(*) INTO v_have FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'ottoq_policy_param_catalog'
     AND column_name IN ('agent_writable','agent_min_value','agent_max_value','agent_max_drift_pct');
  IF v_have <> 0 THEN
    RAISE EXCEPTION '0352 P1: % of the four agent-envelope columns already exist', v_have;
  END IF;
  RAISE NOTICE '0352 P1: ok -- nothing to duplicate';
END $$;

-- ── P2  the six keys must be catalogued, or the seed writes nothing ───────
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('deploy_peak_fraction','energy_demand_factor_peak',
                       'energy_demand_factor_expensive','deploy_surge_catchup',
                       'forecast_horizon_min','energy_reserve_shave');
  IF v_n <> 6 THEN
    RAISE EXCEPTION '0352 P2: expected all six agent dials in the catalog, found %', v_n;
  END IF;
  RAISE NOTICE '0352 P2: ok -- all six agent dials are catalogued';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- (A)  THE ENVELOPE BECOMES DATA IN THE ENGINE
-- ══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.ottoq_policy_param_catalog
  ADD COLUMN agent_writable       boolean NOT NULL DEFAULT false,
  ADD COLUMN agent_min_value      numeric,
  ADD COLUMN agent_max_value      numeric,
  ADD COLUMN agent_max_drift_pct  numeric;

COMMENT ON COLUMN public.ottoq_policy_param_catalog.agent_writable IS
  '0352. TRUE only for a dial an AI actor may set. Default FALSE, so a new dial '
  'is out of the agent''s reach until someone decides otherwise -- the safe '
  'direction for a column that grows by accretion.';
COMMENT ON COLUMN public.ottoq_policy_param_catalog.agent_min_value IS
  '0352. The AGENT''s floor, which may be tighter than min_value (the engine-wide '
  'floor) and must never be looser. Seeded from ottoq-orchestrator-agent''s KNOBS.';
COMMENT ON COLUMN public.ottoq_policy_param_catalog.agent_max_value IS
  '0352. The AGENT''s ceiling. Same contract as agent_min_value.';
COMMENT ON COLUMN public.ottoq_policy_param_catalog.agent_max_drift_pct IS
  '0352. Per-tick drift limiter as a fraction (0.30 = +/-30%), mirroring '
  'clampDial''s MAX_DRIFT. Recorded so the limiter has one home. 0353''s rule does '
  'NOT evaluate it: a drift check needs the PREVIOUS value and ottoq_policy_set is '
  'handed only the requested one. Named rather than faked.';

UPDATE public.ottoq_policy_param_catalog c SET
  agent_writable      = true,
  agent_min_value     = e.lo,
  agent_max_value     = e.hi,
  agent_max_drift_pct = e.drift
FROM (VALUES
  -- key                              lo     hi    drift   (verbatim from KNOBS/MAX_DRIFT)
  ('deploy_peak_fraction',           0.5,   1.0,  0.30),
  ('energy_demand_factor_peak',      0.3,   0.9,  0.30),
  ('energy_demand_factor_expensive', 0.2,   0.8,  0.30),
  ('deploy_surge_catchup',           0.1,   1.0,  0.30),
  ('forecast_horizon_min',          10.0,  90.0,  0.30),
  -- a binary switch: clampDial skips drift for these, so the column stays NULL
  ('energy_reserve_shave',           0.0,   1.0,  NULL)
) AS e(key, lo, hi, drift)
WHERE c.param_key = e.key;

-- ══════════════════════════════════════════════════════════════════════════
-- (B)  PUBLISH IT, so the edge function can stop carrying its own copy
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_agent_dial_envelope()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $fn$
  SELECT COALESCE(
    jsonb_object_agg(
      c.param_key,
      jsonb_build_object(
        'lo',            c.agent_min_value,
        'hi',            c.agent_max_value,
        'max_drift_pct', c.agent_max_drift_pct,
        'engine_lo',     c.min_value,
        'engine_hi',     c.max_value,
        'default',       c.default_value,
        'affects',       c.affects
      )
    ), '{}'::jsonb)
    FROM public.ottoq_policy_param_catalog c
   WHERE c.agent_writable;
$fn$;

COMMENT ON FUNCTION public.ottoq_agent_dial_envelope() IS
  '0352. The dials an AI actor may write and the bounds it may write them within '
  '-- the single home for what ottoq-orchestrator-agent currently hardcodes as '
  'KNOBS. It reports BOTH the agent bound (lo/hi) and the engine-wide catalog '
  'bound (engine_lo/engine_hi), because the two differ on three of six dials '
  'today and a reader must be able to see which one is binding.';

-- ══════════════════════════════════════════════════════════════════════════
-- A1  the envelope is data, and it is the edge function's numbers
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_n int; v_bad text;
BEGIN
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'ottoq_policy_param_catalog'
     AND column_name IN ('agent_writable','agent_min_value','agent_max_value','agent_max_drift_pct');
  IF v_n <> 4 THEN RAISE EXCEPTION '0352 A1: % of 4 columns present', v_n; END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog WHERE agent_writable;
  IF v_n <> 6 THEN
    RAISE EXCEPTION '0352 A1: % dials marked agent_writable, expected exactly 6', v_n;
  END IF;

  -- every seeded bound must equal the edge function's, to the digit
  SELECT string_agg(format('%s(%s..%s)', c.param_key, c.agent_min_value, c.agent_max_value), ', ')
    INTO v_bad
    FROM public.ottoq_policy_param_catalog c
    JOIN (VALUES ('deploy_peak_fraction',0.5,1.0), ('energy_demand_factor_peak',0.3,0.9),
                 ('energy_demand_factor_expensive',0.2,0.8), ('deploy_surge_catchup',0.1,1.0),
                 ('forecast_horizon_min',10.0,90.0), ('energy_reserve_shave',0.0,1.0)
         ) e(key, lo, hi) ON e.key = c.param_key
   WHERE c.agent_min_value IS DISTINCT FROM e.lo OR c.agent_max_value IS DISTINCT FROM e.hi;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0352 A1: seeded bounds disagree with KNOBS: %', v_bad;
  END IF;

  -- THE SAFETY DIRECTION. An agent bound may be tighter than the engine's, never
  -- looser: a wider agent envelope would hand the model authority the engine
  -- itself refuses, which is the opposite of this file's purpose.
  SELECT string_agg(param_key, ', ') INTO v_bad FROM public.ottoq_policy_param_catalog
   WHERE agent_writable
     AND ((min_value IS NOT NULL AND agent_min_value IS NOT NULL AND agent_min_value < min_value)
       OR (max_value IS NOT NULL AND agent_max_value IS NOT NULL AND agent_max_value > max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0352 A1: agent envelope is LOOSER than the engine catalog on: %', v_bad;
  END IF;

  RAISE NOTICE '0352 A1: ok -- 6 dials, bounds match KNOBS, none looser than the catalog';
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A2  the drift this file REPORTS is measured, not asserted. Three of six must
--     be strictly tighter than the catalog; if that stops being true the header
--     is stale and this refuses rather than shipping a wrong number.
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_tighter int; v_which text;
BEGIN
  SELECT count(*), string_agg(param_key, ', ' ORDER BY param_key)
    INTO v_tighter, v_which
    FROM public.ottoq_policy_param_catalog
   WHERE agent_writable
     AND (agent_min_value IS DISTINCT FROM min_value OR agent_max_value IS DISTINCT FROM max_value);
  IF v_tighter <> 3 THEN
    RAISE EXCEPTION '0352 A2: % dials differ from the engine catalog, header says 3 (%)',
      v_tighter, COALESCE(v_which, '<none>');
  END IF;
  RAISE NOTICE '0352 A2: ok -- 3 of 6 agent bounds are tighter than the engine catalog: %', v_which;
END $$;

-- ══════════════════════════════════════════════════════════════════════════
-- A3  the published envelope agrees with the table it is published from, and
--     names every dial exactly once
-- ══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE v_env jsonb; v_n int; v_bad text;
BEGIN
  v_env := public.ottoq_agent_dial_envelope();
  SELECT count(*) INTO v_n FROM jsonb_object_keys(v_env);
  IF v_n <> 6 THEN RAISE EXCEPTION '0352 A3: envelope publishes % dials, expected 6', v_n; END IF;

  SELECT string_agg(c.param_key, ', ') INTO v_bad
    FROM public.ottoq_policy_param_catalog c
   WHERE c.agent_writable
     AND ( (v_env -> c.param_key -> 'lo')::text IS DISTINCT FROM to_jsonb(c.agent_min_value)::text
        OR (v_env -> c.param_key -> 'hi')::text IS DISTINCT FROM to_jsonb(c.agent_max_value)::text
        OR (v_env -> c.param_key -> 'engine_hi')::text IS DISTINCT FROM to_jsonb(c.max_value)::text );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0352 A3: the published envelope disagrees with the catalog on: %', v_bad;
  END IF;

  -- and it must publish the engine bound too, or a reader cannot tell which is
  -- binding -- the whole reason this function returns both
  IF NOT (v_env -> 'energy_demand_factor_peak' ? 'engine_hi') THEN
    RAISE EXCEPTION '0352 A3: the envelope omits engine_hi';
  END IF;

  RAISE NOTICE '0352 A3: ok -- 6 dials published, agreeing with the catalog, both bounds present';
END $$;

-- ── A4  no dial outside the six was touched ───────────────────────────────
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE NOT agent_writable
     AND (agent_min_value IS NOT NULL OR agent_max_value IS NOT NULL OR agent_max_drift_pct IS NOT NULL);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0352 A4: % non-agent dials carry agent bounds', v_n;
  END IF;
  RAISE NOTICE '0352 A4: ok -- no agent bound on a dial the agent does not own';
END $$;

-- ── A5  the registry is still clean ───────────────────────────────────────
DO $$
DECLARE v_block int;
BEGIN
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block <> 0 THEN
    RAISE EXCEPTION '0352 A5: % blocking run-scope registry defects', v_block;
  END IF;
  RAISE NOTICE '0352 A5: ok -- 0 blocking registry defects';
END $$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0352_the_agents_dial_limits_live_in_edge_typescript_and_not_in_this_database', false,
  'Part one of two (0353 adds the rule and the probe). Corrects G64 in both directions at once: the '
  'agent''s dial write already passes four guards -- a six-key allowlist whose misses are queued to '
  'ottoq_ops_approvals for a human, a move cap of 3, a +/-30% drift limiter, and ottoq_policy_set''s five '
  'returned refusal reasons plus the catalog clamp -- so "no L1 rule evaluated" overstated the exposure. '
  'What is true is narrower and still worth fixing: three of those four guards live only in edge-function '
  'TypeScript, and the catalog is WIDER than the agent envelope on 3 of 6 dials (deploy_peak_fraction '
  '0.5-1.0 vs 0.30-1.00, energy_demand_factor_peak 0.3-0.9 vs 0.25-0.95, energy_demand_factor_expensive '
  '0.2-0.8 vs 0.20-0.90), so nothing in the engine could state what the model was permitted to do. This '
  'file adds agent_writable / agent_min_value / agent_max_value / agent_max_drift_pct to '
  'ottoq_policy_param_catalog, seeded verbatim from KNOBS, and publishes them as '
  'ottoq_agent_dial_envelope() returning BOTH the agent and the engine bound so a reader can see which is '
  'binding. A1 refuses any agent bound LOOSER than the engine''s -- the direction that would hand the '
  'model authority the engine itself refuses. A2 asserts the 3-of-6 drift the header reports, so a stale '
  'number cannot ship. The drift column is recorded and deliberately NOT evaluated: a drift check needs '
  'the previous value and ottoq_policy_set is handed only the requested one, so it is named rather than '
  'faked. forces_recert FALSE: nullable/defaulted columns on a catalog table, a data seed, and one STABLE '
  'read-only function; no verdict atom reads ottoq_policy_param_catalog and no tick-path behaviour moves.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
