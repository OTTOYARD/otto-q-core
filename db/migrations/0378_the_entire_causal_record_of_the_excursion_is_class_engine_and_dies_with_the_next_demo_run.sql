-- migration-version: 20260920134500
-- migration-name:    the_entire_causal_record_of_the_excursion_is_class_engine_and_dies_with_the_next_demo_run
--
-- 0378  EVERY NUMBER IN `db/checks/0271` LIVES IN A `class='engine'` TABLE. CAPTURE
--       THE PLANNING DEFECT INTO EVIDENCE BEFORE THE NEXT RUN DELETES IT.
--
-- Capture trigger plus backfill. No tick-path function is rewritten, so
-- `forces_recert` **FALSE** -- the same classification `0364` carries for the same
-- reason, an AFTER-INSERT capture trigger writing to a `class='evidence'` table that
-- no certification atom reads.
--
-- ══ 1. WHAT 0271 FOUND, IN ONE PARAGRAPH ════════════════════════════════════
--
-- G89 said "nothing asserts the sum". **It is computed every tick.**
-- `ottoq_energy_orchestrate` does
-- `v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch)`
-- -- the battery's own draw subtracted, kW for kW -- and publishes it as a
-- `charge_cap_kw` command. What G89 got right is narrower: **no RULE asserts it.** The
-- orchestrator publishes; it does not refuse. Every one of the run's **1,260**
-- `charge_cap_kw` commands carries `"advisory": true`.
--
-- And the excursion had a specific cause, which is a planning defect rather than a
-- missing constraint:
--
--   v_demand_target := v_service_max * factor                    -- 2,500 x 0.9 = 2,250
--   IF policy energy_reserve_shave >= 0.5 THEN
--     v_demand_target := COALESCE(ottoq_bess_reserve_target(...), v_demand_target)
--
-- **The override has no `LEAST(v_service_max, ...)`.** `ottoq_bess_reserve_target`
-- binary-searches for the lowest grid-import ceiling the battery can hold over the
-- forecast horizon; `lo` is the minimum forecast net load and `hi` the maximum, and it
-- returns `hi` when the battery cannot shave. **That is a CAPABILITY answer, not a
-- PERMISSION** -- and with SoC at 13.81% against a ~10% floor the available energy is
-- ~0, so it degenerates to the forecast peak. At the excursion tick it returned
-- **2,802** against a **2,500** contract, producing a **1,762 kW** EV cap where the
-- contract-derived arithmetic (2,250 - 72 + 0 - 968) gives **1,210**.
--
-- Measured over the run: **16 of 1,260** demand targets exceeded `service_max_kw`,
-- worst **2,959** (459 over), while the **median was 1,048** -- so the override
-- normally tightens the target by more than half and is a good mechanism. It loosens
-- past the contract only when the battery is empty and demand is high, which is
-- precisely when that must not happen.
--
-- ══ 2. WHY A NEW TABLE AND NOT A TIER ON 0374's LEDGER ══════════════════════
--
-- `ottoq_site_power_excursion_ledger` records **metered** instants -- its
-- `total_import_kw` is a meter reading, asserted in `0374`'s P5 to reconstruct from
-- components in 8,050 of 8,050 snapshots. A planned target is a different quantity,
-- and putting one into a column named `total_import_kw` would be precisely the
-- name-does-not-match-the-quantity defect of G87 (`stranded_recharges`) and G90
-- (`peak_demand_kw_15min`) -- two findings this repo already carries, and one I spent
-- `0375` correcting in my own code. So: a separate, narrower ledger.
--
-- ══ 3. WHY A TRIGGER AND NOT A TICK-PATH CALL ═══════════════════════════════
--
-- `0374` wired its detector into `ottoq_sim_decide_and_dispatch`, which made it
-- `forces_recert TRUE`. This needs nothing of the kind: the condition is decidable
-- from the inserted row alone (`reason->>'demand_target'` against the depot's
-- `service_max_kw`), so an AFTER-INSERT trigger on `ottoq_energy_commands` sees it at
-- the moment it happens. Cheaper, no rewrite of a certified function, and the same
-- pattern `0364` established.
--
-- **Deliberately NOT captured here: the "EV drew more than the published cap" finding**
-- (26 of 1,260, worst 205.0 kW). That comparison pairs a cap against a LATER snapshot,
-- so it is not decidable from the inserted row and a trigger would have to guess the
-- pairing. It belongs in a view over two sources, and `0271` §2 holds the measurement
-- until one exists. Naming what is not built is the point of saying so.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
BEGIN
  IF to_regclass('public.ottoq_site_power_plan_ledger') IS NOT NULL THEN
    RAISE EXCEPTION '0378 P1: ottoq_site_power_plan_ledger already exists';
  END IF;
  IF to_regclass('public.ottoq_energy_commands') IS NULL THEN
    RAISE EXCEPTION '0378 P1: ottoq_energy_commands is missing -- nothing to capture from';
  END IF;
  RAISE NOTICE '0378 P1: ready';
END $p1$;

DO $p2$
DECLARE v_over int; v_total int; v_advisory int;
BEGIN
  --: Assert the defect is real in live data before building an instrument for it.
  SELECT count(*) FILTER (WHERE (c.reason->>'demand_target')::numeric > d.service_max_kw),
         count(*),
         count(*) FILTER (WHERE (c.reason->>'advisory')::boolean IS TRUE)
    INTO v_over, v_total, v_advisory
    FROM public.ottoq_energy_commands c
    JOIN public.depots d ON d.id = c.depot_id
   WHERE c.command_type = 'charge_cap_kw'
     AND c.reason->>'demand_target' IS NOT NULL
     AND d.service_max_kw IS NOT NULL;

  IF v_total = 0 THEN
    RAISE WARNING '0378 P2: no charge_cap_kw commands carrying a demand_target survive -- '
                  'a purge has already taken them; the trigger still installs';
  ELSE
    RAISE NOTICE '0378 P2: % of % surviving caps exceed service_max_kw; % marked advisory',
                 v_over, v_total, v_advisory;
  END IF;
END $p2$;

-- ══ 4. THE LEDGER ═══════════════════════════════════════════════════════════

CREATE TABLE public.ottoq_site_power_plan_ledger (
  plan_id                   bigserial PRIMARY KEY,
  --: NO FOREIGN KEYS. ottoq_energy_commands and ottoq_sim_runs are both
  --: class='engine' and purged; registry check (b) wants an FK from engine/stamp only.
  sim_run_id                uuid,
  depot_id                  uuid NOT NULL,
  --: The command this was decided from. Dedup key.
  command_id                uuid NOT NULL,
  tick_seq                  bigint,
  --: WALL domain, copied from the column it comes from.
  issued_at                 timestamptz,
  finding                   text NOT NULL CHECK (finding IN ('plan_over_contract')),
  --: The contract, and the two targets: what the contract-derived formula gives, and
  --: what the unclamped override actually used. Keeping both is the whole point --
  --: either one alone hides the substitution.
  service_max_kw            numeric NOT NULL,
  demand_factor             numeric,
  contract_derived_target_kw numeric,
  demand_target_kw          numeric NOT NULL,
  target_excess_kw          numeric NOT NULL,
  --: What the site was told it could draw, and the terms that produced it.
  published_charge_cap_kw   numeric,
  base_load_kw              numeric,
  solar_kw                  numeric,
  --: `advisory` frozen at capture, because it is the fact that makes the cap
  --: non-binding and a later change to that flag must not rewrite history.
  advisory                  boolean,
  reserve_shave_on          boolean,
  captured_at               timestamptz NOT NULL DEFAULT now(),
  source_kind               text NOT NULL DEFAULT 'live'
);

CREATE UNIQUE INDEX ottoq_site_power_plan_ledger_command_uq
  ON public.ottoq_site_power_plan_ledger (command_id);
CREATE INDEX ottoq_site_power_plan_ledger_depot_idx
  ON public.ottoq_site_power_plan_ledger (depot_id, issued_at DESC);

COMMENT ON TABLE public.ottoq_site_power_plan_ledger IS
'0378, from db/checks/0271. One row per published EV charge cap whose demand target exceeded the depot''s utility service contract -- the planning defect that caused the 2,738.8 kW excursion 0374 records. CORRECTS G89, WHICH SAID "NOTHING ASSERTS THE SUM": ottoq_energy_orchestrate computes it every tick as GREATEST(50, demand_target - base_load + solar + bess_dispatch), with the battery''s own draw subtracted kW for kW, and publishes it. What is true is narrower -- no RULE asserts it, because the orchestrator publishes rather than refuses, and all 1,260 of the run''s charge_cap_kw commands carry "advisory": true. THE DEFECT CAPTURED HERE IS AN UNCLAMPED CAPABILITY-FOR-PERMISSION SUBSTITUTION: demand_target starts as service_max_kw * factor (2,500 x 0.9 = 2,250), then, when policy energy_reserve_shave >= 0.5, is replaced outright by ottoq_bess_reserve_target(...) with no LEAST(service_max, ...). That function answers "the lowest peak my battery can hold" and returns the forecast maximum when it can hold nothing, so at 13.81% SoC it returned 2,802 against a 2,500 contract and produced a 1,762 kW cap where the contract-derived arithmetic gives 1,210. Measured on run 5b37ee46: 16 of 1,260 targets over contract, worst 2,959, MEDIAN 1,048 -- so the override normally tightens the target by more than half and is a good mechanism that fails only when the battery is empty and demand is high. Registered class=evidence with NO FK to ottoq_sim_runs or ottoq_energy_commands, both class=engine and purged: check (b) asks for an FK from engine/stamp only, and an enforcing FK on evidence can only block ottoq_purge_prior_runs or, as CASCADE, erase what check (c) forbids erasing. Append-only (override: ottoq.plan_ledger_unlock=on). Filled by an error-swallowing AFTER INSERT trigger rather than a tick-path call, because the condition is decidable from the inserted row alone -- which is why this is forces_recert FALSE where 0374 was TRUE. DOES NOT capture the separate "EV drew more than the published cap" finding (26 of 1,260, worst 205.0 kW): that pairs a cap with a later snapshot and is not decidable from one row, so it stays measured in db/checks/0271 until a view exists.';

CREATE OR REPLACE FUNCTION public.ottoq_site_power_plan_ledger_append_only()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.plan_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_site_power_plan_ledger is append-only: % refused. Set '
    'ottoq.plan_ledger_unlock=on in the session to override, and say why in a migration.',
    TG_OP USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_site_power_plan_ledger_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_site_power_plan_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_power_plan_ledger_append_only();

-- ══ 5. THE CAPTURE TRIGGER ══════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_capture_site_power_plan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_smax   numeric;
  v_target numeric;
  v_factor numeric;
BEGIN
  IF NEW.command_type <> 'charge_cap_kw' THEN RETURN NEW; END IF;

  v_target := NULLIF(NEW.reason->>'demand_target','')::numeric;
  IF v_target IS NULL THEN RETURN NEW; END IF;

  SELECT d.service_max_kw INTO v_smax FROM public.depots d WHERE d.id = NEW.depot_id;
  --: NULL service_max means no declared contract and is NOT zero -- db/checks/0056
  --: records the two depots where it is NULL and EN.001's gate is absent for the same
  --: reason. Nothing to exceed, nothing to record.
  IF v_smax IS NULL OR v_target <= v_smax THEN RETURN NEW; END IF;

  v_factor := public.ottoq_policy_get(NEW.sim_run_id, 'energy_demand_factor_peak', 0.50);

  INSERT INTO public.ottoq_site_power_plan_ledger (
    sim_run_id, depot_id, command_id, tick_seq, issued_at, finding,
    service_max_kw, demand_factor, contract_derived_target_kw, demand_target_kw,
    target_excess_kw, published_charge_cap_kw, base_load_kw, solar_kw,
    advisory, reserve_shave_on, source_kind)
  VALUES (
    NEW.sim_run_id, NEW.depot_id, NEW.command_id, NEW.tick_seq, NEW.issued_at,
    'plan_over_contract',
    v_smax, v_factor, round(v_smax * v_factor, 1), v_target,
    round(v_target - v_smax, 2), NEW.setpoint_kw,
    NULLIF(NEW.reason->>'base_load','')::numeric,
    NULLIF(NEW.reason->>'solar','')::numeric,
    (NEW.reason->>'advisory')::boolean,
    public.ottoq_policy_get(NEW.sim_run_id, 'energy_reserve_shave', 0) >= 0.5,
    'live')
  ON CONFLICT (command_id) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  --: Errors are swallowed and warned: this fires inside the tick, and a missing
  --: evidence row is a gap while a rolled-back tick is an outage. 0364's rule.
  RAISE WARNING '0378 capture_site_power_plan: % %', SQLSTATE, SQLERRM;
  RETURN NEW;
END $fn$;

COMMENT ON FUNCTION public.ottoq_capture_site_power_plan() IS
'0378 (db/checks/0271). Copies into ottoq_site_power_plan_ledger (class=evidence) every published EV charge cap whose demand_target exceeded the depot''s service_max_kw -- the unclamped capability-for-permission substitution in ottoq_energy_orchestrate that caused the excursion 0374 records. Freezes `advisory` and the demand factor at capture, because both are mutable and a live join would rewrite history. NULL service_max_kw means no declared contract and is skipped rather than treated as zero (db/checks/0056). Errors are swallowed and warned: it fires inside the tick, and a missing evidence row is a gap while a rolled-back tick is an outage.';

CREATE TRIGGER ottoq_capture_site_power_plan_trg
  AFTER INSERT ON public.ottoq_energy_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_capture_site_power_plan();

-- ══ 6. REGISTRY ═════════════════════════════════════════════════════════════

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_site_power_plan_ledger', 'sim_run_id', 'evidence',
        '0378 (db/checks/0271): the durable record of every published EV charge cap whose demand '
        'target exceeded the depot''s utility service contract -- the planning defect behind the '
        '2,738.8 kW excursion. Evidence, not engine: the whole causal record lives in '
        'ottoq_energy_commands, which is class=engine, so the next demo run deletes every number '
        'db/checks/0271 cites. Fourth instance of the 0231 fragility after 0340 (model calls), '
        '0364 (proposal outcomes) and 0374 (metered excursions). Carries NO foreign key to '
        'ottoq_sim_runs or ottoq_energy_commands, deliberately: check (b) asks for one from '
        'engine/stamp only, and an enforcing FK on evidence could only block '
        'ottoq_purge_prior_runs or, as CASCADE, erase the history check (c) forbids erasing.');

-- ══ 7. THE READER ═══════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.ottoq_site_power_plan_audit AS
SELECT l.depot_id,
       count(*)                                                     AS plans_over_contract,
       count(DISTINCT l.sim_run_id)                                 AS runs_seen,
       max(l.service_max_kw)                                        AS service_max_kw,
       round(max(l.demand_target_kw), 1)                            AS worst_demand_target_kw,
       round(max(l.target_excess_kw), 1)                            AS worst_excess_over_contract_kw,
       round(avg(l.target_excess_kw), 1)                            AS mean_excess_kw,
       round(max(l.contract_derived_target_kw), 1)                  AS contract_derived_target_kw,
       round(max(l.published_charge_cap_kw), 1)                     AS worst_published_cap_kw,
       --: The two facts that decide whether this is one bug or two. If every row is
       --: advisory AND reserve_shave was on, the diagnosis in 0271 holds as stated.
       count(*) FILTER (WHERE l.advisory)                           AS caps_marked_advisory,
       count(*) FILTER (WHERE l.reserve_shave_on)                   AS with_reserve_shave_on,
       (count(*) FILTER (WHERE l.advisory) = count(*))              AS all_advisory,
       (count(*) FILTER (WHERE l.reserve_shave_on) = count(*))      AS all_reserve_shave,
       count(*) FILTER (WHERE l.source_kind = 'live')               AS live_rows,
       count(*) FILTER (WHERE l.source_kind = 'backfill')           AS backfilled_rows,
       max(l.issued_at)                                             AS last_issued_at
  FROM public.ottoq_site_power_plan_ledger l
 GROUP BY l.depot_id;

COMMENT ON VIEW public.ottoq_site_power_plan_audit IS
'0378 (db/checks/0271). How often this depot PLANNED to import more than its utility service contract allows, which is a different question from 0374''s ottoq_site_power_ledger -- that one records what the meter actually read, this one records what the orchestrator authorised. Both are needed: the plan defect is what produced the metered excursion. all_advisory and all_reserve_shave are assertions rather than statistics: if either reads false, the single-cause diagnosis in db/checks/0271 §3 no longer covers every row and the file needs re-reading before it is quoted. worst_excess_over_contract_kw is the headline -- a positive number here means the engine authorised a draw its own contract forbids, and the fix is one LEAST(service_max, ...) in ottoq_energy_orchestrate, deliberately not applied because it lowers the EV charge cap in exactly the ticks where the battery is empty and demand is high, which is a throughput trade on the one depot under test.';

-- ══ 8. BACKFILL THE SURVIVING EVIDENCE ══════════════════════════════════════
-- Same predicates as the trigger, so the two cannot disagree. source_kind='backfill'
-- so a reader can always tell reconstruction from live capture.

INSERT INTO public.ottoq_site_power_plan_ledger (
  sim_run_id, depot_id, command_id, tick_seq, issued_at, finding,
  service_max_kw, demand_factor, contract_derived_target_kw, demand_target_kw,
  target_excess_kw, published_charge_cap_kw, base_load_kw, solar_kw,
  advisory, reserve_shave_on, source_kind)
SELECT c.sim_run_id, c.depot_id, c.command_id, c.tick_seq, c.issued_at,
       'plan_over_contract',
       d.service_max_kw,
       public.ottoq_policy_get(c.sim_run_id, 'energy_demand_factor_peak', 0.50),
       round(d.service_max_kw
             * public.ottoq_policy_get(c.sim_run_id, 'energy_demand_factor_peak', 0.50), 1),
       (c.reason->>'demand_target')::numeric,
       round((c.reason->>'demand_target')::numeric - d.service_max_kw, 2),
       c.setpoint_kw,
       NULLIF(c.reason->>'base_load','')::numeric,
       NULLIF(c.reason->>'solar','')::numeric,
       (c.reason->>'advisory')::boolean,
       public.ottoq_policy_get(c.sim_run_id, 'energy_reserve_shave', 0) >= 0.5,
       'backfill'
  FROM public.ottoq_energy_commands c
  JOIN public.depots d ON d.id = c.depot_id
 WHERE c.command_type = 'charge_cap_kw'
   AND c.reason->>'demand_target' IS NOT NULL
   AND d.service_max_kw IS NOT NULL
   AND (c.reason->>'demand_target')::numeric > d.service_max_kw
ON CONFLICT (command_id) DO NOTHING;

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p3$
DECLARE v_n int; v_worst numeric; v_adv boolean; v_rs boolean; v_reg int; v_trg int;
BEGIN
  SELECT count(*) INTO v_reg FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_site_power_plan_ledger' AND class = 'evidence';
  IF v_reg <> 1 THEN
    RAISE EXCEPTION '0378 P3: registry row missing or duplicated (%)', v_reg;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'public.ottoq_site_power_plan_ledger'::regclass
                AND contype = 'f') THEN
    RAISE EXCEPTION '0378 P3: the ledger has a foreign key -- evidence must not';
  END IF;

  SELECT count(*) INTO v_trg FROM pg_trigger
   WHERE tgrelid = 'public.ottoq_energy_commands'::regclass
     AND tgname = 'ottoq_capture_site_power_plan_trg' AND NOT tgisinternal;
  IF v_trg <> 1 THEN
    RAISE EXCEPTION '0378 P3: capture trigger not installed';
  END IF;

  SELECT plans_over_contract, worst_excess_over_contract_kw, all_advisory, all_reserve_shave
    INTO v_n, v_worst, v_adv, v_rs
    FROM public.ottoq_site_power_plan_audit
   WHERE depot_id = '11111111-1111-1111-1111-111111111111';

  IF v_n IS NULL THEN
    RAISE WARNING '0378 P3: backfill wrote nothing for the twin depot -- a purge may '
                  'already have taken ottoq_energy_commands';
  ELSE
    RAISE NOTICE '0378 P3: % plan rows, worst excess % kW, all_advisory=%, all_reserve_shave=%',
                 v_n, v_worst, v_adv, v_rs;
    IF v_worst <= 0 THEN
      RAISE EXCEPTION '0378 P3: worst excess is % -- the predicate admitted a row that '
                      'does not exceed the contract', v_worst;
    END IF;
  END IF;
END $p3$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0378_the_entire_causal_record_of_the_excursion_is_class_engine_and_dies_with_the_next_demo_run', false,
  'Capture trigger plus backfill, no tick-path function rewritten -- the classification 0364 '
  'carries for the same reason: an AFTER INSERT trigger on ottoq_energy_commands writing to a '
  'class=evidence table no certification atom reads. From db/checks/0271, which CORRECTS G89: '
  'ottoq_energy_orchestrate does compute the site sum every tick (charge_cap = demand_target - '
  'base_load + solar + bess_dispatch, battery draw subtracted kW for kW) and publishes it; what '
  'is true is that no RULE asserts it and all 1,260 published caps carry advisory=true. The '
  'captured defect is an unclamped capability-for-permission substitution: demand_target starts '
  'as service_max * 0.9 = 2,250 then is replaced outright by ottoq_bess_reserve_target with no '
  'LEAST(service_max, ...), and that function returns the forecast PEAK when the battery cannot '
  'shave -- at 13.81% SoC it returned 2,802 against a 2,500 contract. 16 of 1,260 targets over '
  'contract, worst 2,959, median 1,048. The one-line fix is deliberately NOT applied: it lowers '
  'the EV charge cap exactly when the battery is empty and demand is high, which is a throughput '
  'trade on the one depot under test.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
