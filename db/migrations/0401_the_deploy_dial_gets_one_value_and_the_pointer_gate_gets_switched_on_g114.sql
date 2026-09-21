-- migration-version: 20260921192817
-- migration-name:    the_deploy_dial_gets_one_value_and_the_pointer_gate_gets_switched_on_g114
--
-- 0401  **G114 items (c) and (d), decided under delegated authority** — Chase, 2026-09-21: *"You make
--       the call in the open decisions."* Evidence and reasoning in `db/checks/0312`; this file is the
--       change. Two things: `deploy_peak_fraction` stops having two values in one tick, and the
--       pointer gate in the shared candidate source is switched on.
--
-- **BATCHES WITH `0400` AND G111's ACTOR FIX.** All three are `forces_recert` TRUE, and `0397` §1b is
-- explicit that such changes are free only when they land TOGETHER. Note what changed about that
-- argument: `0307` §6 and `0400` both deferred on the grounds that *"a G112 granularity decision would
-- force a recert anyway, so this rides along for nothing."* `0312` §3 decided **not** to
-- re-granularise, so that free ride does not exist — this batch now stands on its own merits, which
-- is three fixes for one nine-column sweep.
--
-- ══ (c) `deploy_peak_fraction`: 0.55 → 0.90 IN THE TWIN ════════════════════
--
-- Four sites read this dial. **Three already say 0.90** — `ottoq_agent_board`, `ottoq_cil_propose`,
-- and, decisively, the consumer `ottoq_deploy_target_fraction`, whose body opens
-- `GREATEST(0.005, LEAST(COALESCE(p_peak,0.90), COALESCE(p_peak,0.90) * …))`. The catalog says 0.90.
-- And `ottoq_prime` has written this dial **307** times with mean **0.892**, 82% at or above 0.85,
-- and 0.55 exactly **3** times. `twin.ottoq_sim_advance_service_flow` is the outlier.
--
-- **Why it matters beyond tidiness:** on **20 of 22** surviving twin-depot runs no row sets this key,
-- so the agent's board reported 0.90 while the twin deployed against 0.55. `ottoq-orchestrator-agent`
-- clamps with `clampDial(key, requested, board.policy?.[key])`, so the ±30% window was [0.63, 1.17]
-- around 0.90, clamped to the dial range [0.5, 1.0] — **the value in force was below the floor of what
-- the agent was permitted to request.** v16 fixed that clamp's arithmetic; this fixes the input it was
-- handed.
--
-- **This changes the deploy TARGET, so it changes the world.** `v_target := FLOOR(v_fleet *
-- ottoq_deploy_target_fraction(v_hour, …))` — a larger fraction deploys more vehicles per tick, which
-- moves dispatches, bookings and the fingerprint. `forces_recert` TRUE, unarguably.
--
-- **If the twin is ever wanted to under-deploy deliberately, that is a policy ROW at depot or global
-- scope**, where all four sites read it coherently and the board shows the truth. Not a call-site
-- literal that contradicts three other sites and that the agent cannot reach.
--
-- ══ (d) `calendar_occupancy_guard`: A GLOBAL ROW SET TO 1 ══════════════════
--
-- Part 3's three-gate rule requires pointer ∩ calendar ∩ charger-not-`Faulted`.
-- `ottoq_stall_free_between` — shared source for SEVEN callers — has the calendar and the charger, and
-- its pointer check sits behind this switch, whose effective value is **0** (call-site literal; the
-- one row that ever set it belonged to a since-purged run). **0 of 22 surviving twin-depot runs ever
-- offered stalls through the pointer gate.**
--
-- `0311` §4 established that a pointer/calendar conflict IS caught downstream, by
-- `ottoq_validate_assignment`, with `target_occupied`. **So this switch does not decide whether a
-- conflict is caught — it decides whether it is caught BEFORE or AFTER the engine commits to the
-- offer.** Earlier is strictly better: wasted solver time, a wasted tick of right-of-first-refusal,
-- and phantom entries in every capacity count are what "later" costs.
--
-- **The guard is a FORECAST, not a veto**, which is what makes ON safe: it admits a pointer-held stall
-- whose occupant's `ottoq_itinerary_legs` forecast ends before the requested window, bounded by
-- `occupied_stall_horizon_min` (45) and `occupied_stall_horizon_max_min` (240).
--
-- **A ROW, NOT A CODE EDIT, DELIBERATELY.** Reversible by one `UPDATE` with no migration and no
-- deploy; explicit and greppable instead of implicit in a literal; and settling the key at global
-- scope removes it from `ottoq_assert_policy_default_coherence()`'s divergence set by construction
-- rather than by agreement.
--
-- **AND THE COST IS UNMEASURED — stated here, not only in the check.** Two probes returned a delta of
-- exactly zero on every stall type, and **neither is evidence the guard is free**: the twin depot has
-- **0 pointer-occupied stalls** and **0 live itinerary legs**, because every surviving run is completed
-- and torn down, so the guard's first escape admits everything. It is measurable only on a live run,
-- and starting one purges every `class='engine'` table. `0312` §2 records the falsifiable prediction:
-- if offers fall and pointer-flavoured `target_occupied` refusals do NOT fall with them, the guard is
-- over-restricting — most likely through the 45-minute fallback horizon for an occupant with no live
-- leg — and this row goes back to 0.
--
-- ══ AND THE COHERENCE ASSERTION, WHICH IS WHY `ottoq_policy_get` IS UNTOUCHED ══
--
-- `0310` §6(d) recommended making `ottoq_policy_get` read `ottoq_policy_param_catalog.default_value`.
-- **`0312` §1c retracts that**, because `default_value` is not uniformly a default: for
-- `contention_wait_cap_min` and `timer_backstop_min` the catalog row exists to ADMIT the key to
-- `ottoq_policy_set`'s allow-list (their own descriptions say *"UNBOUNDED BY DESIGN … admits the key,
-- clamps nothing"*), and for `robotic_demate_seconds` the declared 11.5 against a live sentinel of -1
-- would **switch on a legacy whole-window override that has never been active in this engine's life**,
-- silently, as a side effect of hygiene. Changing the resolution order of the most-called
-- configuration function in the engine to fix a divergence in one key is the wrong trade.
--
-- Instead, the repo's own pattern — a declaration that lies made impossible to keep, after
-- `ottoq_assert_service_vocabulary()` and `ottoq_assert_bess_state_vocabulary()`.

BEGIN;

-- Preflight messages use the `0401 P<n>:` prefix that scripts/compile-check.py parses as
-- "a precondition working correctly against an empty database" -- see 0400's preflight for why.
DO $preflight$
DECLARE v_n int; v_src text;
BEGIN
  -- (1) The twin function still carries the 0.55 literal this file replaces. If it has already
  --     been changed, replacing blind would clobber whatever it was changed to.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0401 P1: twin.ottoq_sim_advance_service_flow not found';
  END IF;
  IF position('''deploy_peak_fraction'',0.55' in replace(v_src,' ','')) = 0 THEN
    RAISE EXCEPTION '0401 P1: twin.ottoq_sim_advance_service_flow no longer contains the deploy_peak_fraction 0.55 literal; re-measure before replacing';
  END IF;

  -- (2) The consumer's own default really is 0.90 -- the evidence this decision rests on.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.proname='ottoq_deploy_target_fraction' LIMIT 1;
  IF v_src IS NULL OR position('COALESCE(p_peak,0.90)' in replace(v_src,' ','')) = 0 THEN
    RAISE EXCEPTION '0401 P2: ottoq_deploy_target_fraction no longer declares COALESCE(p_peak,0.90); the basis for choosing 0.90 has moved';
  END IF;

  -- (3) The guard key is still spelled as the picker reads it, and is still unsettled at
  --     global/depot scope (so inserting a global row is the operative change, not a no-op).
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key='calendar_occupancy_guard') THEN
    RAISE EXCEPTION '0401 P3: calendar_occupancy_guard is not in ottoq_policy_param_catalog; ottoq_policy_set would refuse it';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key='calendar_occupancy_guard' AND scope_type IN ('global','depot');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0401 P3: calendar_occupancy_guard already has % global/depot row(s); read them before overriding', v_n;
  END IF;

  -- (4) The picker still gates its pointer check on this key. If that coupling is gone, setting
  --     the row achieves nothing and this file is stale.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_stall_free_between';
  IF v_src IS NULL OR v_src !~ 'calendar_occupancy_guard' OR v_src !~ 'current_vehicle_id' THEN
    RAISE EXCEPTION '0401 P4: ottoq_stall_free_between no longer couples its pointer check to calendar_occupancy_guard';
  END IF;

  -- (5) The global sentinel scope_id ottoq_policy_get reads is the one this file writes.
  IF position('00000000-0000-0000-0000-000000000000' in
              (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public' AND p.proname='ottoq_policy_get')) = 0 THEN
    RAISE EXCEPTION '0401 P5: ottoq_policy_get does not read the all-zeros global sentinel; a global row would never be seen';
  END IF;
END
$preflight$;

-- ═════════════════ (c) one value for the deploy dial ═════════════════
-- Surgical: the ONLY change is the fallback literal. Everything else in this function is
-- reproduced from the live source unchanged, so the diff is one number.
DO $fix$
DECLARE v_src text; v_new text; v_args text; v_ndef int; v_ndef_after int;
BEGIN
  -- pg_get_function_ARGUMENTS, never pg_get_function_IDENTITY_arguments. The identity form STRIPS
  -- parameter defaults, and CREATE OR REPLACE with them missing does not silently drop them -- it
  -- fails with 42P13 "cannot remove parameter defaults from existing function". This function
  -- carries one (p_depot_id DEFAULT the twin depot), and the first attempt at this migration died
  -- on exactly that, which is the good outcome: the alternative was a signature change nobody
  -- asked for. Asserted after the rewrite rather than assumed.
  SELECT p.prosrc, pg_get_function_arguments(p.oid), p.pronargdefaults
    INTO v_src, v_args, v_ndef
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow';

  v_new := replace(v_src,
             '''deploy_peak_fraction'',0.55',
             '''deploy_peak_fraction'',0.90');
  IF v_new = v_src THEN
    v_new := replace(v_src,
               '''deploy_peak_fraction'', 0.55',
               '''deploy_peak_fraction'', 0.90');
  END IF;
  IF v_new = v_src THEN
    RAISE EXCEPTION '0401: could not substitute the 0.55 literal -- whitespace differs from both forms tried. Refusing to guess.';
  END IF;

  EXECUTE format('CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_service_flow(%s) RETURNS %s LANGUAGE plpgsql AS %L',
                 v_args,
                 (SELECT pg_get_function_result(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow'),
                 v_new);

  SELECT p.pronargdefaults INTO v_ndef_after
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow';
  IF v_ndef_after <> v_ndef THEN
    RAISE EXCEPTION '0401 P7: parameter defaults changed from % to % -- the signature moved, which this file must never do', v_ndef, v_ndef_after;
  END IF;
END
$fix$;

-- ═════════════════ (d) the pointer gate, on, at global scope ═════════════════
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('global', '00000000-0000-0000-0000-000000000000'::uuid, 'calendar_occupancy_guard', 1,
        'migration:0401', now())
ON CONFLICT (scope_type, scope_id, param_key)
  DO UPDATE SET param_value = 1, updated_by = 'migration:0401', updated_at = now();

-- ═════════════════ the coherence assertion ═════════════════
CREATE OR REPLACE FUNCTION public.ottoq_assert_policy_default_coherence()
RETURNS TABLE (param_key text, call_site_literals text, catalog_default numeric, problem text)
LANGUAGE sql STABLE AS $$
  WITH sites AS (
    SELECT m[1] AS k, m[2]::numeric AS hard
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL regexp_matches(p.prosrc,
        'ottoq_policy_get\s*\([^,]+,\s*''([a-z0-9_]+)''\s*,\s*(-?[0-9]+(?:\.[0-9]+)?)\s*\)', 'g') AS m
     WHERE n.nspname IN ('public','ottoq','twin')
       -- Cheap prefilter before the global regex. Semantically free: the pattern cannot match a
       -- body that lacks this literal. Measured 2026-09-21: 1,392 functions / 2 MB of source in
       -- these three schemas, of which only 76 mention ottoq_policy_get -- an 18x reduction in
       -- regex work. This function is meant to be run routinely, so it has to be cheap enough
       -- that nobody is tempted to skip it.
       AND p.prosrc LIKE '%ottoq_policy_get%'
  ), agg AS (
    SELECT s.k,
           count(DISTINCT s.hard)                                        AS n_lit,
           string_agg(DISTINCT s.hard::text, ' / ' ORDER BY s.hard::text) AS lits,
           (SELECT c.default_value FROM public.ottoq_policy_param_catalog c WHERE c.param_key = s.k) AS cat,
           (SELECT count(*) FROM public.ottoq_policy_params pp
             WHERE pp.param_key = s.k AND pp.scope_type IN ('global','depot'))                       AS row_settled
      FROM sites s GROUP BY s.k
  )
  SELECT a.k, a.lits, a.cat,
         CASE WHEN a.n_lit > 1
                THEN 'TWO OR MORE different call-site defaults for one key -- the value in force depends on which function reads it'
              ELSE 'the sole call-site default disagrees with the catalog, and no global/depot row settles it'
         END
    FROM agg a
   WHERE a.row_settled = 0
     AND ( a.n_lit > 1
        OR (a.cat IS NOT NULL AND a.n_lit = 1 AND a.lits <> a.cat::text) )
   ORDER BY a.n_lit DESC, a.k
$$;

COMMENT ON FUNCTION public.ottoq_assert_policy_default_coherence() IS
'Must return ZERO rows. A key is incoherent when no global/depot row settles it AND either two '
'call sites pass different literal defaults (so the value in force depends on which function reads '
'it -- deploy_peak_fraction read 0.90 on the agent board and 0.55 in the twin that enacts it) or the '
'sole literal disagrees with the catalog. Exists because ottoq_policy_get resolves run -> depot -> '
'global -> THE CALLER''S LITERAL and never reads ottoq_policy_param_catalog, so 160 declared defaults '
'are documentation. It deliberately does NOT propose making policy_get catalog-aware: default_value '
'is a bound or an allow-list filler for some rows (contention_wait_cap_min, timer_backstop_min) and '
'for robotic_demate_seconds it would switch on a legacy override that has never run. G114 / 0312.';

-- Reconcile the catalog to the values actually in force, so the documentation stops lying. These
-- three are read by ottoq_agent_dial_envelope and ottoq_intelligence_status, which is why this file
-- is forces_recert TRUE on its own account: the first is a rule evaluator and the rules atom is one
-- of the fourteen. Reality wins over the declaration in all three -- the live literal is the value
-- that has actually been running, and for robotic_demate_seconds the declared 11.5 would enable an
-- override the engine has never used.
UPDATE public.ottoq_policy_param_catalog SET default_value = 2     WHERE param_key = 'cuopt_debounce_s'       AND default_value <> 2;
UPDATE public.ottoq_policy_param_catalog SET default_value = 4000  WHERE param_key = 'cuopt_solve_window_ms'  AND default_value <> 4000;
UPDATE public.ottoq_policy_param_catalog SET default_value = -1    WHERE param_key = 'robotic_demate_seconds' AND default_value <> -1;

-- Prove it: after the two fixes and three reconciliations, nothing is incoherent.
DO $verify$
DECLARE v_n int; v_rows text;
BEGIN
  SELECT count(*), COALESCE(string_agg(param_key||' ('||problem||')', '; '), '')
    INTO v_n, v_rows FROM public.ottoq_assert_policy_default_coherence();
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0401 P6: ottoq_assert_policy_default_coherence() returns % row(s) after this migration: %', v_n, v_rows;
  END IF;
END
$verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0401_the_deploy_dial_gets_one_value_and_the_pointer_gate_gets_switched_on_g114',
        TRUE,
        'G114 items (c) and (d), decided under authority Chase delegated on 2026-09-21; evidence in '
        'db/checks/0312. (c) deploy_peak_fraction had TWO values in one tick -- 0.90 on the agent '
        'board and in ottoq_cil_propose, 0.55 in twin.ottoq_sim_advance_service_flow, which is the '
        'site that computes the deploy target -- on 20 of 22 surviving twin-depot runs. 0.90 is '
        'canonical: three of four sites already say it, including the consumer '
        'ottoq_deploy_target_fraction whose own body reads COALESCE(p_peak,0.90) twice, and '
        'ottoq_prime wrote this dial 307 times with mean 0.892, 82% at or above 0.85, and 0.55 '
        'exactly 3 times. The twin literal is corrected by substitution into the live source so the '
        'diff is one number. (d) calendar_occupancy_guard is set to 1 at GLOBAL scope, switching on '
        'the pointer gate in ottoq_stall_free_between -- the shared candidate source for seven '
        'callers -- which 0 of 22 surviving twin-depot runs had ever had on. Per 0311 section 4 a '
        'pointer/calendar conflict is already caught downstream by ottoq_validate_assignment, so '
        'this decides whether it is caught BEFORE or AFTER the engine commits to the offer, not '
        'whether it is caught. A ROW rather than a code edit, so it reverts with one UPDATE. ITS '
        'COST IS UNMEASURED AND SAID SO: two probes returned a zero delta and neither is evidence, '
        'because the twin depot has 0 pointer-occupied stalls and 0 live itinerary legs on every '
        'surviving run; measuring it needs a live run, and starting one purges every class=engine '
        'table. Also adds ottoq_assert_policy_default_coherence(), asserted empty here, and '
        'reconciles three stale catalog defaults to the values in force. forces_recert TRUE on two '
        'independent counts: the deploy target changes the world (dispatches, bookings, '
        'fingerprint), and the catalog rows touched are read by ottoq_rule_eval_agent_dial_envelope, '
        'so the rules atom -- one of the fourteen -- can see them. RETRACTS 0310 section 6(d): '
        'ottoq_policy_get is deliberately NOT made catalog-aware, because default_value is a bound '
        'or allow-list filler for contention_wait_cap_min and timer_backstop_min and for '
        'robotic_demate_seconds it would enable a legacy override that has never been active. '
        'BATCHES with 0400 and G111 -- and note that batch no longer waits on anything, since 0312 '
        'decided NOT to re-granularise the cert fixture, removing the free ride both had assumed.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
