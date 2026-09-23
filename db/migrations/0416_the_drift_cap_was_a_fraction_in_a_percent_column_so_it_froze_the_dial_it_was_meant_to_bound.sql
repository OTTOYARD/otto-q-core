-- migration-version: 20260922065233
-- migration-name:    the_drift_cap_was_a_fraction_in_a_percent_column_so_it_froze_the_dial_it_was_meant_to_bound
--
-- 0416  **`agent_max_drift_pct = 0.30` is a FRACTION stored in a column whose every sibling is a
--       PERCENT on a 0-100 scale. `ottoq_promote_dials` divides it by 100, as the convention requires,
--       so the cap reads 0.3% and not 30% — and a cap of 0.3% is not a bound, it is a freeze.**
--
--       `0414` §3 flagged this and deliberately did not resolve it, on the grounds that there was one
--       consumer and no way to arbitrate. **There is a way: the catalog's own convention.** Chase
--       asked for the call; this is it, with the evidence that decides it.
--
--       The fix is to the **VALUE, not the code** — the consumer is right and consistent.
--       `forces_recert` **FALSE**, asserted in §4.
--
-- ══ §1 THE CONVENTION IS UNAMBIGUOUS, AND EVERY SIBLING FOLLOWS IT ════════════
--
-- Measured across `ottoq_policy_param_catalog`, every `_pct` key stores a 0-100 number and its
-- consumer divides by 100:
--
--     key                           value  range      how the consumer reads it
--     ---------------------------   -----  ---------  ----------------------------------------
--     reserve_margin_pct               15  [0,100]    "percentage POINTS added to reserve SoC"
--     sensor_health_clean_pct          90  [0,100]    "0..100 read off the consumer's COALESCE"
--     robotic_fiducial_detect_pct      96  [0,100]    "Probability (percent)"
--     overnight_holdout_pct             1  [1,100]    compared against `% 100`
--     rider_flag_daily_pct            3.0  [0,-]      consumer does `(rate / 100.0)` explicitly
--
-- So `ottoq_promote_dials`'s `v_drift := abs(v_incumbent) * (r.agent_max_drift_pct / 100.0)` is **not
-- a bug — it is the convention correctly applied.** What is wrong is that five rows carry `0.30`,
-- which on this scale means **0.3%**, when whoever wrote it plainly meant 30%. The two readings are
-- numerically identical if the value is written as `30`; the column decides which, and it says percent.
--
-- **And the current setting is not a conservative cap, it is a disabled one.** Against each dial's own
-- agent envelope. **The base column here is the catalog DEFAULT, not the incumbent** — the promoter
-- multiplies the incumbent, and only one of these five has one (§5), so this table sizes the cap on the
-- value every run starts from rather than on a value that mostly does not exist. Saying "incumbent"
-- here would be the same word-spanning-two-things defect `0415` §1(c) and `0324` §1 both recorded:
--
--     dial                               DEFAULT   cap TODAY (0.30)   cap AT 30   envelope   % of env
--     ------------------------------   ---------   ----------------   ---------   --------   --------
--     deploy_peak_fraction                  0.90          +/-0.0027    +/-0.270       0.50      54.0%
--     deploy_surge_catchup                  0.35          +/-0.0011    +/-0.105       0.90      11.7%
--     energy_demand_factor_expensive        0.35          +/-0.0011    +/-0.105       0.60      17.5%
--     energy_demand_factor_peak             0.50          +/-0.0015    +/-0.150       0.60      25.0%
--     forecast_horizon_min                    30          +/-0.0900    +/-9.000      80.00      11.3%
--
-- Those five are **every** row in the catalog carrying a non-NULL `agent_max_drift_pct` — measured, not
-- assumed, which is what lets V2 assert the 5%-of-envelope floor over the whole column rather than over
-- a named list.
--
-- `deploy_peak_fraction` could move **0.54% of its envelope per promotion** — about 185 promotions to
-- cross it, against a promoter gated on n>=5 runs and n>=2 seeds per cell. **A cap that cannot be
-- reached in any realistic number of promotions is a disable switch wearing a cap's name**, which is
-- the same defect shape as `0325`'s charge-only gate and `0415`'s overloaded status word.
--
-- ══ §2 SO THE DECISION: SET 30, AND CHANGE NO CODE ════════════════════════════
--
-- Five rows go from `0.30` to `30`. Nothing else changes. This is deliberately the smallest possible
-- fix, and it is the right one for three reasons:
--
--   1. **It honours the convention rather than adding an exception to it.** Changing the consumer's
--      divisor would make `agent_max_drift_pct` the only `_pct` key in the catalog read as a fraction,
--      and the next reader would have to know that.
--   2. **It is almost certainly the author's intent.** `0.30` written to two decimals is how one writes
--      30%; 0.3% would be written `0.3`, and nobody designs a 0.3% drift cap.
--   3. **The data is the tunable surface and the code is not.** CLAUDE.md's own discipline throughout
--      this catalog is that bounds are DATA with their derivation in the description.
--
-- ══ §3 AND THE WRITE PATH STILL DOES NOT GET DRIFT — NOW FOR MEASURED REASONS ══
--
-- `0414` §3 left drift out of `ottoq_dial_clamp` because the unit was ambiguous. The unit is now
-- decided, so that reason is spent — and drift **still must not** go on the agent write path, for two
-- stronger reasons measured today:
--
-- **(a) There is no incumbent to drift FROM.** Of the six agent-writable dials: **zero global rows**,
-- **three depot rows in total**, and **1,366 run-scoped rows**. Every agent write is run-scoped and
-- every run starts from the catalog default, so there is no previous value the agent is moving away
-- from. Drift is a constraint on *change*, and a dial written fresh each run does not change — it is
-- simply set. **Applying a drift cap here would be measuring a delta against a number nobody wrote.**
--
-- **(b) It would clamp 859 of 1,366 observed agent writes.** Against the catalog default as a stand-in
-- incumbent, agent writes exceed 30% on `deploy_surge_catchup` (95 of 154, max drift 186%),
-- `energy_demand_factor_expensive` (120 of 198, 129%), `energy_demand_factor_peak` (253 of 329, 80%),
-- `forecast_horizon_min` (105 of 105, 200%) and `deploy_peak_fraction` (16 of 310, 44%). The agent
-- uses its **whole envelope** — `deploy_peak_fraction` spans exactly 0.5 to 1.0 — which is what a
-- bounded-authority envelope is for. **That is emphatically not a no-op, so it is not a safe change,
-- and it would be a behaviour change dressed as a hardening.**
--
-- **A trap avoided on the way, worth recording.** The first version of that measurement compared agent
-- writes to the GLOBAL row and reported `would_exceed_30pct = 0` for all six — which looked like a
-- clean no-op and would have justified adding the cap. It was **vacuous**: there is no global row, so
-- every comparison was against NULL. Fifth vacuous-denominator trap of this branch, after `0413` §2's
-- `occurred_at`, `0324` §1's censored exposure, `0322` §8's inflated denominator and `0415` §1(c)'s
-- overloaded status. **A zero that comes from NULL is not a zero.**
--
-- ══ §4 WHY `forces_recert` IS FALSE ═══════════════════════════════════════════
--
-- `agent_max_drift_pct` is read by exactly two functions, neither on the decide path:
-- `ottoq_agent_dial_envelope` (which only advertises it to the agent) and `ottoq_promote_dials`.
-- **`ottoq_dial_promotion_ledger` holds zero rows** — the promoter has never enacted or dry-run a
-- promotion — so no dial value, decision, event or booking has ever been shaped by this column. V3
-- asserts both the reader set and the empty ledger; if either changes, the classification is wrong and
-- the migration aborts.
--
-- ══ §5 WHAT THE CAP WILL ACTUALLY DO THE FIRST TIME IT ENGAGES ════════════════
--
-- The promoter's drift branch is guarded by `IF v_incumbent IS NOT NULL AND
-- COALESCE(agent_max_drift_pct,0) > 0`, and the incumbent is looked up at depot-or-global scope only.
-- With zero global rows, that means **the cap engages today for exactly one dial**:
-- `energy_demand_factor_peak`, whose twin-depot incumbent is **0.53**. After this migration a promotion
-- of that dial is confined to **0.53 +/- 0.159 = [0.371, 0.689]**, then further clamped to its agent
-- envelope `[0.3, 0.9]`. That is a real, reachable, sensible bound — roughly a quarter of the envelope
-- per promotion.
--
-- **And the one dial where a multiplicative cap could not work is already excluded by design.**
-- `energy_reserve_shave` carries `agent_max_drift_pct = NULL`, and its depot incumbent is **0** — 30%
-- of zero is zero, so a multiplicative cap would forbid the only value the agent ever writes to it
-- (1.0, on all 270 of its writes). Whoever left that column NULL was right, and this migration does
-- not disturb it.
--
-- ══ §6 WHAT I DELIBERATELY DID NOT ADD ════════════════════════════════════════
--
-- **No CHECK constraint forbidding a sub-1 value.** It would have caught exactly this defect, and I
-- considered it. But a `_pct` below 1 is legitimate elsewhere in this very catalog —
-- `p99_burn_pct_per_min` stores `0.25` and means a quarter of a percentage point per minute — so a
-- blanket floor would be **a bound invented from one incident**, which is the mistake `0413` §5 and
-- `0414` §3 both refused. The guard instead goes where this catalog puts every other derivation: in
-- the row's own `description`, naming the scale and the divisor so the next reader cannot misread it.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. Exactly five rows carry the fraction, and energy_reserve_shave is NOT one of them.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE agent_max_drift_pct = 0.30;
  IF v_n <> 5 THEN
    RAISE EXCEPTION '0416 P1: expected 5 dials at agent_max_drift_pct=0.30, found % -- re-derive '
                    'before rewriting the value', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key='energy_reserve_shave' AND agent_max_drift_pct IS NULL;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0416 P1: energy_reserve_shave no longer has a NULL drift cap. Its incumbent is 0, '
                    'so a multiplicative cap would forbid every value the agent writes -- see §5';
  END IF;

  -- P2. THE CONSUMER STILL DIVIDES BY 100. If someone "fixed" the code instead, this migration would
  --     multiply the cap by 10,000. Comment-stripped: prosrc carries comments.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_promote_dials'
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                        '--[^' || chr(10) || ']*','','g')
         LIKE '%agent_max_drift_pct / 100.0%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0416 P2: ottoq_promote_dials no longer divides agent_max_drift_pct by 100. The '
                    'convention this migration relies on has changed -- do NOT apply';
  END IF;

  -- P3. THE forces_recert=FALSE PREMISE: the promoter has never run, so nothing was shaped by the cap.
  SELECT count(*) INTO v_n FROM public.ottoq_dial_promotion_ledger;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0416 P3: ottoq_dial_promotion_ledger holds % rows, so a promotion HAS been shaped '
                    'by the frozen cap and forces_recert must be TRUE -- reclassify', v_n;
  END IF;

  RAISE NOTICE '0416 preflight: 5 fraction rows, reserve_shave NULL, consumer divides by 100, promoter never ran';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE FIX: the VALUE, on the catalog's own 0-100 scale. No code changes.
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.ottoq_policy_param_catalog
   SET agent_max_drift_pct = 30,
       description = description ||
         ' 0416: agent_max_drift_pct corrected 0.30 -> 30. It is a PERCENT on the catalog''s 0-100 '
         'scale, like reserve_margin_pct 15 and sensor_health_clean_pct 90, and its sole consumer '
         'ottoq_promote_dials reads it as abs(incumbent) * (pct / 100.0). Stored as 0.30 it meant '
         '0.3%, capping a promotion of this dial at well under one percent of its agent envelope -- a '
         'freeze wearing a cap''s name. It bounds the PROMOTER moving a persistent depot/global value '
         'and nothing else: the agent''s own per-run writes have no incumbent to drift from (zero '
         'global rows, 1,366 run-scoped), so db/migrations/0416 §3 deliberately leaves the write path '
         'uncapped.'
 WHERE agent_max_drift_pct = 0.30;

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0416_the_drift_cap_was_a_fraction_in_a_percent_column_so_it_froze_the_dial_it_was_meant_to_bound',
  false,
  'Corrects agent_max_drift_pct from the fraction 0.30 to the percent 30 on five dials, honouring the '
  'catalog convention every other _pct key follows and that ottoq_promote_dials already implements '
  'with /100.0. No code changes. FALSE because the column is read only by ottoq_promote_dials and '
  'ottoq_agent_dial_envelope (an advertiser), and ottoq_dial_promotion_ledger holds zero rows -- the '
  'promoter has never run, so no dial value, decision, event or booking was ever shaped by the frozen '
  'cap. Both facts asserted in V3. Deliberately does NOT extend drift to the agent write path: there '
  'is no incumbent (zero global rows, 1,366 run-scoped writes) and it would clamp 859 of them.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_cap   numeric;
  v_inc   numeric;
BEGIN
  -- V1. Five rows now read 30, none reads 0.30, and reserve_shave is still NULL.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog WHERE agent_max_drift_pct = 30;
  IF v_n <> 5 THEN
    RAISE EXCEPTION '0416 V1: % dials at 30, expected 5', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog WHERE agent_max_drift_pct = 0.30;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0416 V1: % dials still carry the fraction 0.30', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key='energy_reserve_shave' AND agent_max_drift_pct IS NULL;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0416 V1: energy_reserve_shave''s drift cap is no longer NULL; its incumbent is 0 '
                    'and a multiplicative cap would forbid every value the agent writes';
  END IF;

  -- V2. THE CAP IS NOW REACHABLE. For every capped dial the allowance must be at least 5% of its own
  --     agent envelope -- the property that distinguishes a bound from a freeze, and the whole point
  --     of this migration. (At 0.30 every one of them was under 0.6%.)
  SELECT count(*) INTO v_n
    FROM public.ottoq_policy_param_catalog c
   WHERE c.agent_max_drift_pct IS NOT NULL
     AND c.default_value IS NOT NULL
     AND c.agent_min_value IS NOT NULL AND c.agent_max_value IS NOT NULL
     AND c.agent_max_value > c.agent_min_value
     AND abs(c.default_value) * (c.agent_max_drift_pct/100.0)
         < 0.05 * (c.agent_max_value - c.agent_min_value);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0416 V2: % capped dial(s) still allow less than 5%% of their own envelope per '
                    'promotion -- that is a freeze, not a cap', v_n;
  END IF;

  -- V3. THE forces_recert=FALSE PREMISE, both halves.
  SELECT count(*) INTO v_n FROM public.ottoq_dial_promotion_ledger;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0416 V3: the promotion ledger is no longer empty (% rows); FALSE is not earned', v_n;
  END IF;
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND p.proname NOT IN ('ottoq_promote_dials','ottoq_agent_dial_envelope')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                        '--[^' || chr(10) || ']*','','g') LIKE '%agent_max_drift_pct%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0416 V3: % unexpected reader(s) of agent_max_drift_pct. If any is on the decide '
                    'path, forces_recert must be TRUE', v_n;
  END IF;

  -- V4. THE FIRST DIAL THE CAP WILL ACTUALLY BIND, computed rather than asserted from the header:
  --     energy_demand_factor_peak is the only capped dial with a depot/global incumbent, so it is the
  --     only one whose drift branch can engage at all today.
  SELECT c.agent_max_drift_pct, p.param_value INTO v_cap, v_inc
    FROM public.ottoq_policy_param_catalog c
    JOIN public.ottoq_policy_params p ON p.param_key = c.param_key
   WHERE c.param_key = 'energy_demand_factor_peak'
     AND p.scope_type = 'depot' AND p.scope_id = '11111111-1111-1111-1111-111111111111'::uuid;
  IF v_cap IS NULL OR v_inc IS NULL THEN
    RAISE WARNING '0416 V4: energy_demand_factor_peak has no twin-depot incumbent, so no capped dial '
                  'can bind today -- the cap is correct but dormant';
  ELSE
    RAISE NOTICE '0416 V4: energy_demand_factor_peak incumbent %, promotions now confined to % .. %',
                 v_inc, round(v_inc - v_inc*(v_cap/100.0), 4), round(v_inc + v_inc*(v_cap/100.0), 4);
  END IF;

  RAISE NOTICE '0416 verify: five caps at 30, none left as a fraction, reserve_shave still NULL, every '
               'cap now worth at least 5%% of its envelope, promoter still unrun, no new readers';
END $post$;

COMMIT;
