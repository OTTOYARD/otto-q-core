-- migration-version: 20260920123000
-- migration-name:    two_legal_decisions_summed_past_the_service_contract_and_the_meter_that_would_have_seen_it_is_not_read
--
-- 0374  THE SITE ALREADY METERS 2,738.8 kW AGAINST A 2,500 kW SERVICE CONTRACT,
--       STORES IT IN A COLUMN, AND NOTHING READS THAT COLUMN.
--
-- Fixes the measurable half of G89. Scope: the twin depot
-- 11111111-1111-1111-1111-111111111111 (rule 8). MEASURED ONLY -- this file changes
-- no assignment, refuses nothing, and does not touch EN.001.
--
-- ══ 1. WHAT G89 SAID, AND THE THREE THINGS MEASURING IT SHARPENED ═══════════
--
-- G89 was filed as "two independently legal decisions summed to 239 kW over the
-- depot's declared service maximum", reconstructed by hand. Re-measured before
-- building anything, it is all true and three things about it are sharper than the
-- finding as written:
--
-- (a) **NOTHING NEEDED RECONSTRUCTING. The total is already a stored column.**
--     `site_energy_snapshots.grid_import_kw` IS the site total, and it reads
--     **2,738.80** on run `5b37ee46` at 2026-09-19 06:56:09 UTC. Measured across
--     all 8,050 snapshots on this depot, `grid_import_kw` equals
--     `GREATEST(ev - bess_output + building + lighting - solar, 0)` in **8,050 of
--     8,050** with a worst residual of **0.10 kW**. So this file adds no arithmetic
--     of its own: it reads the twin's own meter. That is deliberate -- `db/checks/0264`
--     is the night's lesson that a census of mine disagreeing with the engine's own
--     reading is a defect in the census, and the way not to repeat it is not to
--     compute a second opinion.
--
-- (b) **THE MECHANISM, WHICH G89 GAVE AS ARITHMETIC, IS AN INCOMPLETE METER.**
--     EN.001.grid_capacity_ceiling is the one rule that names `service_max_kw`, and
--     it does compare against it. But its load term is
--     `ottoq_depot_current_demand_kw` -> `twin.ottoq_sim_compute_charger_load_kw`,
--     which is `SUM(ocpp_sessions.last_meter_value->>'power_kw')` **and nothing
--     else**. BESS charging and base load are not in it. So the rule asks
--     "EV_now + EV_requested <= service_max_kw" -- a true question, correctly
--     answered, about a quantity that is not the site's load. At the excursion:
--     EV **1,691.8** (under its own 1,800 nameplate, so EN.001 passed and was right
--     to) + BESS **charging at 968** (`bess_output_kw = -968`, within
--     EN.003.bess_limits, the only rule `bess_dispatch` evaluates, which checks the
--     battery's own envelope) + base **79** = **2,738.8**. Both legal. Sum illegal.
--     **No rule anywhere takes the sum as its subject.**
--
-- (c) **THE INCIDENCE IS 1 IN 8,050, AND THAT IS NOT REASSURANCE -- IT IS THE
--     SHAPE OF AN UNGUARDED TAIL.** The honest rate first: **1 of 8,050 snapshots
--     over the contract, across 1 of 9 runs, worst excess 238.8 kW.** But read the
--     distribution rather than the rate:
--
--       0-300 kW    6,229        1,202-1,494     34
--       301-600       883        1,515-1,714     15
--       600-893       777        1,800-2,700    ** 0 **
--       900-1,198     111        2,739            1
--
--     **Buckets 7, 8 and 9 are empty.** The site never operates between 1,714 and
--     2,739 kW. It does not climb toward the cap and occasionally cross it; it sits
--     comfortably below and then takes a single ~1,000 kW step clean over. A
--     discontinuity of a megawatt in a metered load is not how demand builds -- it
--     is the signature of a second decision ADDING, and ~1,000 kW is the BESS
--     charge magnitude (min `bess_output_kw` on this depot is -1,200). So the
--     rarity is the rarity of the COINCIDENCE, not evidence of anything preventing
--     it. Nothing prevents it. A 1-in-8,050 event that opens the utility's breaker
--     is an unguarded tail, not an acceptable residual.
--
-- ══ 2. WHY THIS FILE MEASURES AND DOES NOT ENFORCE ══════════════════════════
--
-- Making EN.001's meter see the full site load would change which actions are
-- feasible. Per CLAUDE.md 2.9a the L1 shield defines the feasible set, so widening
-- it is a change to the problem definition and not a bug fix -- and per the
-- blind-spot promotion doctrine an instrument lands MEASURED first and ENFORCED
-- only after a round shows what it would have refused. 0370 is tonight's precedent
-- and this file is deliberately its twin in shape.
--
-- **AND THE ENFORCEMENT DECISION IS GENUINELY NOT MINE, because the right answer is
-- probably not "refuse".** The excursion's own remedy is already named in EN.001's
-- other branch: `engage_bess_or_defer`. At the excursion the BESS was CHARGING at
-- 968 kW -- it was the load. A shield that refused the EV session would be refusing
-- the wrong party; the cheap fix is to defer or throttle the battery, which is an
-- energy-policy decision about arbitrage against demand charges, not a safety
-- veto. That trade is Chase's, and the ledger this file installs is what makes it
-- an informed one instead of a guess.
--
-- **AND IT IS THE CONSTRUCT CLAUDE.md 2.5 SAYS cuOpt CANNOT EXPRESS.** A shared
-- site power cap over concurrent activities is a cumulative resource, one of the
-- four load-bearing constructs R-12 established are absent from cuOpt 26.08. This
-- excursion is that construct's absence, observed on a real run rather than argued
-- from a vendor doc -- so it belongs in the CP-SAT case, and it is the first
-- measured instance of it.
--
-- ══ 3. THE LEDGER IS EVIDENCE, NOT ENGINE, AND THAT IS THE WHOLE POINT ══════
--
-- `site_energy_snapshots` is registered `class='engine'`. Correct for it -- 1,139
-- snapshots per run is working data -- but it means **every excursion this depot
-- has ever had is deleted by the next demo run.** The one on `5b37ee46` survives
-- only because no run has started since. "How often has this site exceeded its
-- service contract" is therefore a question no surviving table can answer, and
-- that is exactly the 0231 fragility that 0340 and 0364 closed for model calls and
-- proposal outcomes. This is the third instance, built the same way: append-only,
-- `class='evidence'`, and **no foreign key to `ottoq_sim_runs`**, because
-- `ottoq_check_run_scope_registry` check (b) requires an FK of `engine`/`stamp`
-- only, and an enforcing FK on evidence can only block the purge or, as CASCADE,
-- erase what check (c) forbids erasing.
--
-- Two tiers are recorded, and the second is not padding:
--   * `excursion`  -- over the declared cap. The event, the alarm, the finding.
--   * `high_water` -- over `p_warn_frac` of it. Without this tier a purge leaves no
--     trace of how close the site ran, so the NEXT excursion looks as isolated as
--     this one did and the tail can never be characterised. At the default 0.60 it
--     is **16 rows in 8,050** on this depot, so the cost of keeping the tail is
--     nil. 0.60 rather than 0.80 for two reasons: at 0.80 (2,000 kW) exactly one
--     snapshot qualifies and it is the excursion itself, which would leave the
--     tier untested on the only data that exists; and 60% of a service contract is
--     where 15-minute demand billing starts to matter, independently of safety.
--
-- ══ 4. APPLY ORDER AND GATE ═════════════════════════════════════════════════
--
-- forces_recert **TRUE**: it adds a per-tick call to `ottoq_sim_decide_and_dispatch`
-- on every arm. Wired ABOVE the policy branch, beside 0367's reclaimer and 0370's
-- claim detector, for the reason 0367 recorded -- what the world IS forms part of
-- the problem definition, so every A/B arm must see the same reading of it.
-- Preconditions: no `ottoq_sim_runs` row `running` or `paused`, no cert pair live.
-- Verified 0 live runs at 12:28 UTC.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_live int;
BEGIN
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0374 P1: % sim run(s) running or paused -- this file rewrites '
                    'ottoq_sim_decide_and_dispatch; wait for the run to end', v_live;
  END IF;
  RAISE NOTICE '0374 P1: no live run';
END $p1$;

DO $p2$
BEGIN
  IF to_regclass('public.ottoq_site_power_excursion_ledger') IS NOT NULL THEN
    RAISE EXCEPTION '0374 P2: ottoq_site_power_excursion_ledger already exists -- '
                    'this file creates it; reconcile before applying';
  END IF;
  RAISE NOTICE '0374 P2: the ledger does not yet exist';
END $p2$;

DO $p3$
BEGIN
  --: The cap is READ from the existing function, never re-derived. Rule 5.
  IF to_regprocedure('public.ottoq_effective_charge_cap_kw(uuid,uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0374 P3: ottoq_effective_charge_cap_kw(uuid,uuid,timestamptz) is '
                    'missing -- this file reads the site cap from it and must not '
                    'invent a second definition of the cap';
  END IF;
  IF to_regprocedure('public.ottoq_record_event(text,text,text,text,uuid,uuid,jsonb,text,text,text,uuid)') IS NULL
     AND to_regproc('public.ottoq_record_event') IS NULL THEN
    RAISE EXCEPTION '0374 P3: ottoq_record_event is missing -- the alarm has no emitter';
  END IF;
  RAISE NOTICE '0374 P3: the cap function and the event emitter are both present';
END $p3$;

DO $p4$
DECLARE v_cols int;
BEGIN
  SELECT count(*) INTO v_cols FROM information_schema.columns
   WHERE table_schema='public' AND table_name='site_energy_snapshots'
     AND column_name IN ('grid_import_kw','total_ev_charging_kw','bess_output_kw',
                         'building_load_kw','lighting_load_kw','solar_generation_kw');
  IF v_cols <> 6 THEN
    RAISE EXCEPTION '0374 P4: site_energy_snapshots carries % of the 6 component '
                    'columns this file reads', v_cols;
  END IF;
  RAISE NOTICE '0374 P4: all six component columns present';
END $p4$;

DO $p5$
DECLARE v_n int; v_ok int; v_worst numeric; v_charging int;
BEGIN
  --: THE ASSERTION THIS WHOLE FILE RESTS ON. The detector reads `grid_import_kw`
  --: as the site total instead of summing the parts itself. If that column is not
  --: the total, every row this ledger ever writes is about the wrong quantity.
  SELECT count(*),
         count(*) FILTER (WHERE abs(s.grid_import_kw
                 - GREATEST(s.total_ev_charging_kw - s.bess_output_kw
                            + s.building_load_kw + s.lighting_load_kw
                            - s.solar_generation_kw, 0)) <= 0.5),
         max(abs(s.grid_import_kw
                 - GREATEST(s.total_ev_charging_kw - s.bess_output_kw
                            + s.building_load_kw + s.lighting_load_kw
                            - s.solar_generation_kw, 0)))
    INTO v_n, v_ok, v_worst
    FROM public.site_energy_snapshots s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';

  IF v_n = 0 THEN
    RAISE NOTICE '0374 P5: no snapshots on the twin depot -- identity not testable '
                 'here, and the detector is written to read the stored total either way';
  ELSIF v_ok <> v_n THEN
    RAISE EXCEPTION '0374 P5: grid_import_kw is NOT the site total -- it reconstructs '
                    'from components in only % of % snapshots (worst residual % kW). '
                    'The detector must not read it as the total until this is understood.',
                    v_ok, v_n, round(v_worst,2);
  ELSE
    RAISE NOTICE '0374 P5: grid_import_kw is the site total in % of % snapshots '
                 '(worst residual % kW)', v_ok, v_n, round(v_worst,2);
  END IF;

  --: And the sign convention the payload's `bess_charging_kw` depends on.
  SELECT count(*) INTO v_charging FROM public.site_energy_snapshots s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND s.bess_output_kw < 0;
  IF v_n > 0 AND v_charging = 0 THEN
    RAISE WARNING '0374 P5: no snapshot on this depot has bess_output_kw < 0, so the '
                  'charging-is-negative convention is untested here';
  ELSE
    RAISE NOTICE '0374 P5: bess_output_kw < 0 (charging) in % snapshots', v_charging;
  END IF;
END $p5$;

DO $p6$
DECLARE v_src text;
BEGIN
  --: The finding this file records must still be TRUE at apply time. If someone has
  --: already widened EN.001's meter, the file's own commentary is stale and should
  --: be rewritten rather than shipped.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw';
  IF v_src IS NULL THEN
    RAISE WARNING '0374 P6: twin.ottoq_sim_compute_charger_load_kw not found -- cannot '
                  'confirm EN.001 meter scope';
  ELSIF v_src ILIKE '%bess%' THEN
    RAISE EXCEPTION '0374 P6: EN.001''s load meter now mentions BESS -- section 1(b) of '
                    'this file may be stale; re-measure before applying';
  ELSE
    RAISE NOTICE '0374 P6: EN.001''s meter is still EV-only, so the gap this file '
                 'measures is real at apply time';
  END IF;
END $p6$;

-- ══ 1. THE LEDGER ═══════════════════════════════════════════════════════════

CREATE TABLE public.ottoq_site_power_excursion_ledger (
  excursion_id      bigserial PRIMARY KEY,
  --: NO FOREIGN KEYS, deliberately. site_energy_snapshots and ottoq_sim_runs are
  --: both class='engine' and purged; check (b) wants an FK from engine/stamp only.
  sim_run_id        uuid,
  depot_id          uuid NOT NULL,
  --: The snapshot this reading came from. Dedup key -- one ledger row per metered
  --: instant, however many ticks observe it.
  snapshot_id       uuid NOT NULL,
  sim_clock         timestamptz,
  --: 'excursion' = over the declared cap. 'high_water' = over p_warn_frac of it,
  --: kept so a purge cannot erase how close the site ran and leave the next
  --: excursion looking as isolated as the first one did.
  severity_tier     text NOT NULL CHECK (severity_tier IN ('excursion','high_water')),
  --: The stored meter reading, not a sum of my own. See P5.
  total_import_kw   numeric NOT NULL,
  cap_kw            numeric NOT NULL,
  --: Positive only in the 'excursion' tier; negative headroom is what a
  --: high_water row carries, so both tiers read off one column without a CASE.
  excess_kw         numeric NOT NULL,
  warn_kw           numeric NOT NULL,
  --: Attribution, so a reader can tell WHICH concurrent decision added the load
  --: without going back to a table the purge has since emptied.
  ev_charging_kw    numeric,
  bess_output_kw    numeric,
  bess_charging_kw  numeric,
  base_load_kw      numeric,
  solar_kw          numeric,
  --: Which declared cap bound: the utility service contract, or a tighter active
  --: demand-response call. Frozen at capture because both are mutable.
  cap_source        text,
  --: The largest single contributor at this instant, precomputed because the
  --: question "what pushed us over" is the first one anybody asks.
  dominant_component text,
  detected_at       timestamptz NOT NULL DEFAULT now(),
  --: 'live' = the tick detector wrote it as it happened; 'backfill' = reconstructed
  --: later from surviving snapshots. A reader must be able to tell them apart.
  source_kind       text NOT NULL DEFAULT 'live'
);

--: One row per metered instant. site_energy_snapshots.id is a primary key, so this
--: is sufficient on its own and needs no run-scoped COALESCE idiom.
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_snapshot_uq
  ON public.ottoq_site_power_excursion_ledger (snapshot_id);
CREATE INDEX ottoq_site_power_excursion_ledger_depot_idx
  ON public.ottoq_site_power_excursion_ledger (depot_id, detected_at DESC);
CREATE INDEX ottoq_site_power_excursion_ledger_run_idx
  ON public.ottoq_site_power_excursion_ledger (sim_run_id) WHERE sim_run_id IS NOT NULL;

COMMENT ON TABLE public.ottoq_site_power_excursion_ledger IS
'0374, measuring G89. One row per metered instant at which this site''s TOTAL grid import crossed its declared cap (tier excursion) or p_warn_frac of it (tier high_water). Exists because the total was already stored and never read: site_energy_snapshots.grid_import_kw read 2,738.80 kW on run 5b37ee46 at 2026-09-19 06:56:09 UTC against depots.service_max_kw 2,500, and no rule in the engine takes the site total as its subject. EN.001.grid_capacity_ceiling does name service_max_kw, but its load term is twin.ottoq_sim_compute_charger_load_kw = SUM(ocpp_sessions power) and nothing else, so BESS charging and base load are invisible to it: at the excursion EV 1,691.8 (under its own 1,800 nameplate) + BESS CHARGING at 968 + base 79 = 2,738.8, each decision legal under the one rule that judges it. MEASURED ONLY per 2.9a blind-spot promotion -- writes no assignment and does not touch EN.001 -- and the enforcement choice is deliberately left open because refusing the EV session would be refusing the wrong party: at the excursion the battery was the load, and EN.001''s own other branch already names the remedy, engage_bess_or_defer. THE RATE IS 1 IN 8,050 SNAPSHOTS AND THAT IS NOT REASSURANCE: the distribution has NOTHING between 1,714 and 2,739 kW, so the site does not climb to the cap and cross it, it takes one ~1,000 kW step clean over -- the BESS charge magnitude -- which means the rarity is the rarity of the coincidence and nothing prevents it. Registered class=evidence with NO foreign key to ottoq_sim_runs or site_energy_snapshots, both of which are class=engine and purged: check (b) requires an FK for engine/stamp only, and an enforcing FK on evidence can only block ottoq_purge_prior_runs or, as CASCADE, erase what check (c) forbids erasing. Append-only (override: ottoq.site_power_ledger_unlock=on). Reads the STORED meter rather than summing components itself, asserted in P5 to reconstruct in 8,050 of 8,050 snapshots at a worst residual of 0.10 kW, because db/checks/0264 is the lesson that a census of ours disagreeing with the engine''s own reading is a defect in the census. This is also the first MEASURED instance of the cumulative-resource construct CLAUDE.md 2.5 records as absent from cuOpt 26.08.';

CREATE OR REPLACE FUNCTION public.ottoq_site_power_excursion_ledger_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.site_power_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_site_power_excursion_ledger is append-only: % refused. Set '
    'ottoq.site_power_ledger_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_site_power_excursion_ledger_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_site_power_excursion_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_power_excursion_ledger_append_only();

-- ══ 2. THE DETECTOR ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ottoq.ottoq_detect_site_power_excursion(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_sim_clock  timestamptz,
  --: 0.60 rather than 0.80: at 0.80 exactly one snapshot on this depot qualifies
  --: and it is the excursion itself, which would leave the high_water tier
  --: untested on the only data that exists. 60% of a service contract is also
  --: where 15-minute demand billing starts to matter, independently of safety.
  p_warn_frac  numeric DEFAULT 0.60)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cap      numeric;
  v_cap_src  text;
  v_warn     numeric;
  v_snap     public.site_energy_snapshots%ROWTYPE;
  v_tier     text;
  v_dom      text;
  v_charging numeric;
  v_base     numeric;
  v_written  int := 0;
BEGIN
  IF p_depot_id IS NULL THEN
    RETURN jsonb_build_object('skipped','no_depot');
  END IF;

  --: THE CAP IS READ, NEVER RE-DERIVED. ottoq_effective_charge_cap_kw is
  --: LEAST(service_max_kw, tightest active DR call) and is already the
  --: externally-declared site cap. A second definition of the cap in this file
  --: would be a second thing to keep in step -- rule 5.
  v_cap := public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock);

  --: NULL means no declared cap and is NOT zero. db/checks/0056 records the two
  --: depots where service_max_kw is NULL and EN.001's gate is therefore absent;
  --: this detector is absent there for the same reason rather than reporting every
  --: tick as infinitely over.
  IF v_cap IS NULL THEN
    RETURN jsonb_build_object('skipped','no_declared_cap','depot_id',p_depot_id);
  END IF;

  v_cap_src := CASE
    WHEN v_cap < (SELECT d.service_max_kw FROM public.depots d WHERE d.id = p_depot_id)
      THEN 'dr_call' ELSE 'service_max_kw' END;
  v_warn := v_cap * p_warn_frac;

  --: The snapshot for THIS tick already exists: twin.ottoq_sim_advance_site_energy
  --: is reached from ottoq_sim_advance_tick_world, which ottoq_demo_metronome calls
  --: at its line 100, before decide_and_dispatch at line 108. Checked against
  --: pg_proc rather than assumed -- G82 is what assuming a caller costs.
  --: Run-scoped by the 0020/0124 zero-uuid idiom so production rows (NULL run)
  --: match a NULL run.
  SELECT s.* INTO v_snap
    FROM public.site_energy_snapshots s
   WHERE s.depot_id = p_depot_id
     AND (p_sim_clock IS NULL OR s.timestamp <= p_sim_clock)
     AND COALESCE(s.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
   ORDER BY s.timestamp DESC, s.id
   LIMIT 1;

  IF v_snap.id IS NULL THEN
    RETURN jsonb_build_object('skipped','no_snapshot_at_or_before_clock');
  END IF;

  IF v_snap.grid_import_kw > v_cap THEN
    v_tier := 'excursion';
  ELSIF v_snap.grid_import_kw > v_warn THEN
    v_tier := 'high_water';
  ELSE
    RETURN jsonb_build_object('tier',NULL,'total_kw',v_snap.grid_import_kw,
                              'cap_kw',v_cap,'headroom_kw',round(v_cap - v_snap.grid_import_kw,1));
  END IF;

  --: Charging is bess_output_kw < 0 (asserted in P5). Surfaced as a positive
  --: magnitude because "the battery drew 968 kW" is the sentence a reader needs,
  --: and a sign convention is exactly the kind of thing that gets misread once the
  --: run is gone.
  v_charging := GREATEST(-COALESCE(v_snap.bess_output_kw, 0), 0);
  v_base     := COALESCE(v_snap.building_load_kw,0) + COALESCE(v_snap.lighting_load_kw,0);

  v_dom := CASE
    WHEN COALESCE(v_snap.total_ev_charging_kw,0) >= GREATEST(v_charging, v_base) THEN 'ev_charging'
    WHEN v_charging >= v_base THEN 'bess_charging'
    ELSE 'base_load' END;

  INSERT INTO public.ottoq_site_power_excursion_ledger (
    sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
    total_import_kw, cap_kw, excess_kw, warn_kw,
    ev_charging_kw, bess_output_kw, bess_charging_kw, base_load_kw, solar_kw,
    cap_source, dominant_component, source_kind)
  VALUES (
    p_sim_run_id, p_depot_id, v_snap.id, COALESCE(p_sim_clock, v_snap.timestamp), v_tier,
    v_snap.grid_import_kw, v_cap, round(v_snap.grid_import_kw - v_cap, 2), v_warn,
    v_snap.total_ev_charging_kw, v_snap.bess_output_kw, v_charging, v_base,
    v_snap.solar_generation_kw,
    v_cap_src, v_dom, 'live')
  ON CONFLICT (snapshot_id) DO NOTHING;

  v_written := CASE WHEN FOUND THEN 1 ELSE 0 END;

  --: The alarm fires for a true excursion only. A high_water row is tail data, not
  --: an incident, and an event per warm tick would be noise that trains a reader to
  --: ignore the channel. Inside its own handler: an alarm that breaks a tick is
  --: worse than the condition it reports.
  IF v_tier = 'excursion' AND v_written = 1 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type   := 'ottoq_engine',
        p_actor_id     := 'site_power_excursion_detector',
        p_event_type   := 'ottoq.site_power_excursion',
        p_entity_type  := 'depot',
        p_entity_id    := p_depot_id,
        p_depot_id     := p_depot_id,
        p_payload      := jsonb_build_object(
                            'total_import_kw', v_snap.grid_import_kw,
                            'cap_kw', v_cap,
                            'cap_source', v_cap_src,
                            'excess_kw', round(v_snap.grid_import_kw - v_cap, 2),
                            'ev_charging_kw', v_snap.total_ev_charging_kw,
                            'bess_charging_kw', v_charging,
                            'base_load_kw', v_base,
                            'dominant_component', v_dom,
                            'snapshot_id', v_snap.id,
                            'sim_clock', p_sim_clock),
        p_severity     := 'critical',
        p_ingest_source := 'production',
        p_data_source  := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,
        p_sim_run_id   := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0374 site_power_excursion alarm: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('tier',v_tier,'written',v_written,
                            'total_kw',v_snap.grid_import_kw,'cap_kw',v_cap,
                            'excess_kw',round(v_snap.grid_import_kw - v_cap,2),
                            'dominant_component',v_dom,'snapshot_id',v_snap.id);
END;
$function$;

COMMENT ON FUNCTION ottoq.ottoq_detect_site_power_excursion(uuid,uuid,timestamptz,numeric) IS
'0374 (G89). Per-tick detector recording the instants at which this site''s TOTAL grid import crossed its declared cap, into ottoq_site_power_excursion_ledger (class=evidence). MEASURED ONLY: writes no assignment, refuses nothing, and does not touch EN.001.grid_capacity_ceiling -- whose load meter is EV-only, which is why a 2,738.8 kW total passed every rule the engine has. Reads the STORED total (site_energy_snapshots.grid_import_kw) rather than summing components, and reads the cap from ottoq_effective_charge_cap_kw rather than re-deriving it: two second opinions are two things to keep in step. NULL cap means no declared cap and is skipped, not treated as zero (db/checks/0056). Two tiers: excursion (over cap, raises ottoq.site_power_excursion) and high_water (over p_warn_frac, ledger row only) -- the second exists so a purge cannot erase how close the site ran, since without it the next excursion looks as isolated as the first one did. Deduped on snapshot_id, so re-observing one metered instant cannot inflate a count.';

-- ══ 3. WIRE IT ON THE PATH THAT ACTUALLY RUNS ═══════════════════════════════
-- Part B is derived verbatim from pg_get_functiondef of the live
-- public.ottoq_sim_decide_and_dispatch(uuid), with ONE block added above the policy
-- branch. Written out in full rather than patched, because that is the only way a
-- CREATE OR REPLACE can be reviewed against what it replaces.
-- ── the added block is marked 0374 ──

CREATE OR REPLACE FUNCTION public.ottoq_sim_decide_and_dispatch(p_sim_run_id uuid)
 RETURNS TABLE(out_dispatched integer, out_charge_assigned integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_decide ottoq_decide_tick_result;
  v_is_benchmark boolean; v_redeployed int := 0;
  v_tick_minutes numeric; v_k text;
  v_fire_hb timestamptz; v_hb_window int; v_seat int; /* 0261 */
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;
  v_tick_minutes := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                             (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0);

  SELECT EXISTS (SELECT 1 FROM depots d WHERE d.id = v_run.depot_id AND d.slug LIKE 'benchmark%') INTO v_is_benchmark;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0367 (G82): THE RESERVATION RECLAIMER, ON THE PATH THAT ACTUALLY RUNS.
  -- 0360 wired this into ottoq_sim_advance_tick. ottoq_demo_metronome -- the
  -- live engine, cron job 12 -- calls ottoq_sim_advance_tick_world and
  -- ottoq_sim_decide_and_dispatch DIRECTLY and never calls advance_tick, so the
  -- reclaimer had never run on a metronome-driven run. Measured before this
  -- migration: 38 release-eligible reservations standing on the twin depot,
  -- unchanged across a tick boundary, some 45 sim-minutes past expiry.
  -- It runs HERE, above the policy branch, so every arm of an A/B gets the same
  -- world: reservation hygiene is part of the problem definition, not the policy
  -- (the C5 / 0146 argument about the L1 shield, applied to the calendar).
  -- Never allowed to abort the tick: the function returns ok:false rather than
  -- raising, and this handler is the second line of that same defence.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM public.ottoq_release_unusable_reservations(
              p_sim_run_id, v_run.sim_clock_current, v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0367 release_unusable_reservations: % %', SQLSTATE, SQLERRM;
  END;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0370 (G85): COUNT THE CALENDAR CLAIMS PHYSICAL REALITY HAS ALREADY
  -- OVERRULED. MEASURED ONLY -- this detector changes no assignment.
  -- CLAUDE.md rule 6 says space_conflict_ledger "records every calendar claim
  -- overruled by physical reality". It records the ones discovered AT ASSIGNMENT
  -- TIME (assignment_refused_occupied, 25 rows on run 5b37ee46) and one
  -- displacement. It did not record a claim that is ALREADY contradicted while it
  -- stands: 59 live perimeter_hold bookings named a staging stall a DIFFERENT
  -- vehicle was sitting in, 0 of them present in the ledger by booking id.
  -- Per 2.9a's blind-spot promotion doctrine this lands MEASURED first. Acting on
  -- it -- rebooking the holder before it travels -- is an assignment change and
  -- is deliberately not in this migration.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM ottoq.ottoq_detect_contradicted_claims(
              p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0370 detect_contradicted_claims: % %', SQLSTATE, SQLERRM;
  END;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0374 (G89): RECORD THE INSTANTS THE SITE'S *TOTAL* LOAD CROSSED ITS
  -- DECLARED CAP. MEASURED ONLY -- this detector changes no assignment.
  -- EN.001.grid_capacity_ceiling is the one rule naming service_max_kw, and its
  -- load term is twin.ottoq_sim_compute_charger_load_kw = SUM(ocpp_sessions
  -- power) and nothing else. So on run 5b37ee46 the site metered 2,738.8 kW
  -- against a 2,500 kW contract -- EV 1,691.8 (under its own 1,800 nameplate)
  -- + BESS CHARGING at 968 + 79 base -- and every rule that judged a piece of it
  -- passed, correctly, because no rule takes the sum as its subject.
  -- It runs HERE, above the policy branch, for 0367's reason: what the world IS
  -- belongs to the problem definition, so every A/B arm reads it identically.
  -- Widening EN.001's meter would change the feasible set and is deliberately
  -- NOT in this file -- and the remedy is probably to defer the battery rather
  -- than refuse a vehicle, which is Chase's call to make on this evidence.
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    PERFORM ottoq.ottoq_detect_site_power_excursion(
              p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0374 detect_site_power_excursion: % %', SQLSTATE, SQLERRM;
  END;


  IF v_run.policy IS NULL OR v_run.policy = 'otto_q' THEN
    BEGIN
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('inbound_forecast', ottoq_inbound_forecast(v_run.depot_id, 60))
       WHERE sim_run_id = p_sim_run_id;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'inbound_forecast attach: %', SQLERRM;
    END;
    -- A SATISFIED NEED IS A DONE NEED, AND IT IS RESOLVED FIRST.
    -- Runs ahead of every planner below so nothing books a charger against a
    -- need the car no longer has. A charge atom left open on a car already at
    -- its target is what sent nine vehicles to chargers in run c99e4435 with
    -- 0.00 kWh to deliver. OTTO-Q decides satisfaction; the twin only reports
    -- state. Never allowed to abort the tick.
    BEGIN
      PERFORM ottoq.ottoq_close_satisfied_charge_needs(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close satisfied charge needs: %', SQLERRM;
    END;
    /* 0261: THE PROPOSER SEAT. Seat 0 -- the default, and every run that has ever
       existed -- is the block below, untouched. A non-zero seat is set run-scoped
       by ottoq_ab_pair only (CHECK ottoq_policy_params_proposer_seat_run_scoped);
       it replaces OTTO-Q's proposers with ONE baseline proposer and leaves the
       disposer -- ottoq_decide_tick, the shield, the calendar -- exactly as it is.
       The policy is what proposes; the kernel disposes. */
    v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0)::int;
    IF v_seat = 0 THEN
    BEGIN
      PERFORM ottoq_reoptimize_reservation_book(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reservation reopt: %', SQLERRM;
    END;

    -- ════════════════════════════════════════════════════════════════════════
    -- P6 FIX 2 — DECIDE-BEAT cuOpt FIRE, CONDITIONAL. net.http_post only QUEUES
    -- a row; the pg_net worker cannot transmit until THIS transaction COMMITS,
    -- and ottoq_decide_tick runs a few lines below, inside it. So a fire from
    -- here lands one full tick late by construction. It is NOT deleted, because
    -- this function is also the only route to cuOpt for callers with no fire
    -- beat (twin.ottoq_world_advance, ottoq_api_otto_q_decide, probe ticks).
    -- Stand down ONLY while a healthy FIRE beat is demonstrably running.
    -- ════════════════════════════════════════════════════════════════════════
    v_hb_window := GREATEST(5, ottoq_policy_get(p_sim_run_id, 'cuopt_fire_beat_heartbeat_s', 60)::int);
    BEGIN
      v_fire_hb := (v_run.payload->>'cuopt_fire_beat_at')::timestamptz;
    EXCEPTION WHEN OTHERS THEN v_fire_hb := NULL;
    END;
    IF v_fire_hb IS NULL OR v_fire_hb < now() - make_interval(secs => v_hb_window) THEN
      BEGIN PERFORM ottoq_cuopt_refresh(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    -- ════════════════════════════════════════════════════════════════════════
    -- P7 2026-08-03 — RIGHT OF FIRST REFUSAL ON DECIDE-BEAT ARRIVALS.
    --
    -- The metronome alternates FIRE and DECIDE beats. A vehicle that reaches the
    -- gate during a DECIDE beat is placed by the local greedy path inside THIS
    -- transaction, so no FIRE beat ever sees it and cuOpt cannot compete for it.
    -- Measured on the phase-9 cert: 113 arrivals, 57 gate candidates -- the
    -- coin-flip you would predict from the beat split, not a solver problem.
    --
    -- This holds such a vehicle out of the greedy cursor for EXACTLY ONE decide
    -- tick so the next FIRE beat can offer it. The hold releases the instant a
    -- cuopt proposal exists (first refusal, never veto) and UNCONDITIONALLY at
    -- the next decide tick via ottoq_cuopt_defer_roll -- so if cuOpt abstains,
    -- greedy assigns next tick with no condition attached. Capped at
    -- cuopt_first_refusal_max_defers (default 1) per vehicle per run; set it to
    -- 0 to disable. Never aborts the tick.
    -- ════════════════════════════════════════════════════════════════════════
    BEGIN
      PERFORM ottoq_cuopt_first_refusal_arm(p_sim_run_id, COALESCE(v_run.tick_count,0));
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cuopt first-refusal arm: %', SQLERRM;
    END;

    PERFORM ottoq_l2_optimize_assignments(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    BEGIN PERFORM ottoq_service_priority_propose(p_sim_run_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    ELSE
      BEGIN PERFORM public.ottoq_l2_propose_seat(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, v_seat);
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'proposer seat % failed: %', v_seat, SQLERRM; END;
    END IF;
  END IF;
  v_decide := CASE v_run.policy
    WHEN 'greedy' THEN ottoq_greedy_tick(p_sim_run_id)
    WHEN 'fifo'   THEN ottoq_fifo_tick(p_sim_run_id)
    WHEN 'manual' THEN ottoq_manual_tick(p_sim_run_id)
    ELSE               ottoq_decide_tick(p_sim_run_id)
  END;

  IF v_run.policy IS DISTINCT FROM 'greedy' THEN
    v_redeployed := ottoq_sim_auto_dispatch_tick(p_sim_run_id, v_run.sim_clock_current, v_tick_minutes);
  END IF;

  BEGIN
    PERFORM ottoq_itin_close_travel_legs(p_sim_run_id, v_run.sim_clock_current, 20);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close travel legs: %', SQLERRM;
  END;

  BEGIN
    PERFORM ottoq_sweep_stranded_deployments(p_sim_run_id, v_run.sim_clock_current, 45);

  BEGIN
    PERFORM ottoq_release_expired_bookings(p_sim_run_id, v_run.sim_clock_current);
    PERFORM ottoq_place_unplaced_vehicles(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
    PERFORM ottoq.ottoq_react_to_refusals(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'placement reconcile: %', SQLERRM;
  END;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'stranded deploy sweep: %', SQLERRM;
  END;

  IF COALESCE(v_run.run_by,'') NOT IN ('benchmark', 'cert_harness')  -- 0105: cert runs quiesce the LLM proposer
     AND NOT v_is_benchmark
     AND v_run.policy IS NOT DISTINCT FROM 'otto_q'
     AND ottoq_policy_get(p_sim_run_id, 'orchestrator_agent_enabled', 1) > 0  -- 0112: deterministic-only sessions quiesce the agent
     AND ottoq_policy_get(p_sim_run_id, 'agent_solver_chain_enabled', 0) < 1  -- 0332: chain fire beats own the agent entrance
     AND ( (COALESCE(v_run.tick_count,0) % 3) = 0
           OR ottoq_orchestrator_trigger(v_run.depot_id) ) THEN
    BEGIN
      SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name='ottoq_anon_key' LIMIT 1;
      IF v_k IS NOT NULL THEN
        PERFORM net.http_post(
          url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_k,'apikey',v_k),
          body := jsonb_build_object('depot_id', v_run.depot_id, 'sim_run_id', p_sim_run_id),
          timeout_milliseconds := 20000);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='ottoq_orchestrator', p_event_type:='twin.sim_tick_advanced',
    p_entity_type:='system', p_payload:=jsonb_build_object('sim_run_id',p_sim_run_id,'sim_clock',v_run.sim_clock_current,
      'policy',v_run.policy,'decisions_built',v_decide.requests_built,'enacted',v_decide.enacted,
      'redeployed',v_redeployed,'completed',(v_run.status='completed')),
    p_severity:='debug', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  out_dispatched:=v_decide.enacted; out_charge_assigned:=v_decide.requests_built;
  RETURN NEXT;
END;
$function$
;

-- ══ 4. REGISTRY ═════════════════════════════════════════════════════════════

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_site_power_excursion_ledger', 'sim_run_id', 'evidence',
        '0374 (G89): the durable record of every instant this site''s TOTAL grid import crossed '
        'its declared cap. Evidence, not engine: the total is already stored in '
        'site_energy_snapshots.grid_import_kw -- 2,738.80 kW against a 2,500 kW service contract '
        'on run 5b37ee46 -- but that table is class=engine and the next demo run deletes it, so '
        '"how often has this site exceeded its service contract" was answerable from no surviving '
        'table. Third instance of the 0231 fragility after 0340 (model calls) and 0364 (proposal '
        'outcomes). Carries NO foreign key to ottoq_sim_runs or site_energy_snapshots, '
        'deliberately: check (b) asks for one from engine/stamp only, and an enforcing FK on '
        'evidence could only block ottoq_purge_prior_runs or, as CASCADE, erase the history '
        'check (c) forbids erasing.');

-- ══ 5. THE EVENT ════════════════════════════════════════════════════════════

INSERT INTO public.ottoq_event_types_catalog
  (event_type, category, description, emitter, default_severity, introduced_in)
VALUES
  ('ottoq.site_power_excursion', 'system_event',
   'The site''s TOTAL metered grid import exceeded its declared cap (utility service contract, or a tighter active demand-response call). Not raised by any rule: EN.001.grid_capacity_ceiling names service_max_kw but meters EV charging only, so a total of 2,738.8 kW against a 2,500 kW contract -- EV 1,691.8 under its own nameplate plus BESS charging at 968 plus 79 base -- passed every check the engine has. Payload names the dominant component, because the cheap remedy is usually to defer the battery rather than refuse a vehicle.',
   'ottoq.ottoq_detect_site_power_excursion', 'critical', '0374')
ON CONFLICT (event_type) DO NOTHING;

-- ══ 6. THE READER ═══════════════════════════════════════════════════════════
-- A ledger nobody can query is a ledger nobody checks. And per 0341 -- whose first
-- view silently reported 515 of 1,676 rows and bucketed the other 1,161 nowhere --
-- the tiers are asserted to SUM to the row count, in the view itself, so a class
-- added later cannot go missing quietly.

CREATE OR REPLACE VIEW public.ottoq_site_power_ledger AS
SELECT l.depot_id,
       count(*)                                                       AS readings,
       count(*) FILTER (WHERE l.severity_tier = 'excursion')          AS excursions,
       count(*) FILTER (WHERE l.severity_tier = 'high_water')         AS high_water,
       --: 0341's assertion, as a column rather than a promise: these two must sum
       --: to `readings` or a tier has been added without a reader.
       (count(*) FILTER (WHERE l.severity_tier = 'excursion')
        + count(*) FILTER (WHERE l.severity_tier = 'high_water')) = count(*)
                                                                      AS tiers_sum_to_readings,
       count(DISTINCT l.sim_run_id)                                   AS runs_seen,
       count(DISTINCT l.sim_run_id) FILTER (WHERE l.severity_tier = 'excursion')
                                                                      AS runs_with_excursion,
       max(l.cap_kw)                                                  AS cap_kw,
       round(max(l.total_import_kw), 1)                               AS worst_total_kw,
       round(max(l.excess_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_excess_kw,
       round(avg(l.total_import_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS mean_total_when_over,
       --: What pushed it over, which is the first question and the one that decides
       --: whether enforcement should refuse a vehicle or defer a battery.
       mode() WITHIN GROUP (ORDER BY l.dominant_component)
         FILTER (WHERE l.severity_tier = 'excursion')                 AS usual_dominant_component,
       round(max(l.bess_charging_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_bess_charging_kw,
       count(*) FILTER (WHERE l.source_kind = 'live')                 AS live_rows,
       count(*) FILTER (WHERE l.source_kind = 'backfill')             AS backfilled_rows,
       max(l.sim_clock)                                               AS last_reading_sim_clock,
       max(l.detected_at)                                             AS last_detected_at
  FROM public.ottoq_site_power_excursion_ledger l
 GROUP BY l.depot_id;

COMMENT ON VIEW public.ottoq_site_power_ledger IS
'0374 (G89). The per-depot answer to "how often has this site exceeded its declared power cap, and what pushed it over" -- a question no surviving table could answer before, because the total lives in site_energy_snapshots (class=engine, purged by the next demo run). tiers_sum_to_readings is 0341''s lesson as a column rather than a promise: 0341''s predecessor view silently reported 515 of 1,676 rows and bucketed the other 1,161 nowhere, so a tier added later must not be able to go missing quietly -- if that column reads false, a reader has been added to the table and not to this view. usual_dominant_component is load-bearing for the enforcement decision this file deliberately does not make: at the only excursion measured, the BESS was CHARGING at 968 kW, so a shield that refused the EV session would have refused the wrong party.';

-- ══ 7. BACKFILL THE SURVIVING EVIDENCE ══════════════════════════════════════
-- The excursion on run 5b37ee46 survives only because no demo run has started
-- since. Once one does it is gone, and the instrument would begin life with no
-- record of the event that motivated it. Written as source_kind='backfill' so it is
-- never mistaken for live capture, and computed by the same predicates the detector
-- uses so the two cannot disagree.

INSERT INTO public.ottoq_site_power_excursion_ledger (
  sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
  total_import_kw, cap_kw, excess_kw, warn_kw,
  ev_charging_kw, bess_output_kw, bess_charging_kw, base_load_kw, solar_kw,
  cap_source, dominant_component, source_kind)
SELECT s.sim_run_id, s.depot_id, s.id, s.timestamp,
       CASE WHEN s.grid_import_kw > d.service_max_kw THEN 'excursion' ELSE 'high_water' END,
       s.grid_import_kw, d.service_max_kw,
       round(s.grid_import_kw - d.service_max_kw, 2), d.service_max_kw * 0.60,
       s.total_ev_charging_kw, s.bess_output_kw,
       GREATEST(-COALESCE(s.bess_output_kw,0), 0),
       COALESCE(s.building_load_kw,0) + COALESCE(s.lighting_load_kw,0),
       s.solar_generation_kw,
       --: Backfill attributes to the service contract only. A DR call's window is
       --: not reconstructable for a past instant without re-reading purged
       --: run-scoped rows, and guessing it would put a wrong cap in an evidence
       --: table -- the one place a guess is least recoverable.
       'service_max_kw',
       CASE
         WHEN COALESCE(s.total_ev_charging_kw,0)
              >= GREATEST(GREATEST(-COALESCE(s.bess_output_kw,0),0),
                          COALESCE(s.building_load_kw,0)+COALESCE(s.lighting_load_kw,0))
           THEN 'ev_charging'
         WHEN GREATEST(-COALESCE(s.bess_output_kw,0),0)
              >= COALESCE(s.building_load_kw,0)+COALESCE(s.lighting_load_kw,0)
           THEN 'bess_charging'
         ELSE 'base_load' END,
       'backfill'
  FROM public.site_energy_snapshots s
  JOIN public.depots d ON d.id = s.depot_id
 WHERE d.service_max_kw IS NOT NULL
   AND s.grid_import_kw > d.service_max_kw * 0.60
ON CONFLICT (snapshot_id) DO NOTHING;

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p7$
DECLARE v_reg int; v_cat int; v_rows int; v_exc int; v_sum boolean;
BEGIN
  SELECT count(*) INTO v_reg FROM public.ottoq_run_scope_registry
   WHERE table_name='ottoq_site_power_excursion_ledger' AND class='evidence';
  IF v_reg <> 1 THEN
    RAISE EXCEPTION '0374 P7: registry row missing or duplicated (% rows)', v_reg;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                  WHERE c.conrelid='public.ottoq_site_power_excursion_ledger'::regclass
                    AND c.contype='f') THEN
    RAISE NOTICE '0374 P7: no foreign key on the ledger, as evidence requires';
  ELSE
    RAISE EXCEPTION '0374 P7: the ledger has a foreign key -- evidence must not, or '
                    'the purge either blocks or cascades';
  END IF;

  SELECT count(*) INTO v_cat FROM public.ottoq_event_types_catalog
   WHERE event_type='ottoq.site_power_excursion';
  IF v_cat <> 1 THEN
    RAISE EXCEPTION '0374 P7: event type not registered in the catalog';
  END IF;

  SELECT readings, excursions, tiers_sum_to_readings
    INTO v_rows, v_exc, v_sum
    FROM public.ottoq_site_power_ledger
   WHERE depot_id='11111111-1111-1111-1111-111111111111';

  IF v_rows IS NULL THEN
    RAISE WARNING '0374 P7: the backfill wrote no row for the twin depot -- check '
                  'whether a demo run has already purged site_energy_snapshots';
  ELSIF NOT v_sum THEN
    RAISE EXCEPTION '0374 P7: tiers do not sum to readings (% rows) -- 0341''s defect '
                    'reproduced in a new view', v_rows;
  ELSE
    RAISE NOTICE '0374 P7: backfill wrote % readings on the twin depot, % of them '
                 'excursions, tiers sum', v_rows, v_exc;
  END IF;
END $p7$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0374_two_legal_decisions_summed_past_the_service_contract_and_the_meter_that_would_have_seen_it_is_not_read', true,
  'Evidence: public.ottoq_site_power_excursion_ledger (class=evidence, append-only, no FK) plus '
  'ottoq.ottoq_detect_site_power_excursion, a per-tick detector recording instants at which the '
  'site TOTAL grid import crossed its declared cap or 60% of it. MEASURED ONLY per 2.9a blind-spot '
  'promotion; no assignment changes and EN.001 is untouched. Exists because the total was already '
  'stored and never read: site_energy_snapshots.grid_import_kw read 2,738.80 kW against '
  'service_max_kw 2,500 on run 5b37ee46, EV 1,691.8 (under its 1,800 nameplate) + BESS CHARGING at '
  '968 + 79 base, each decision legal under the one rule that judges it, because EN.001 meters '
  'ocpp_sessions power only. Adds a per-tick call to ottoq_sim_decide_and_dispatch above the '
  'policy branch on every arm, so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
