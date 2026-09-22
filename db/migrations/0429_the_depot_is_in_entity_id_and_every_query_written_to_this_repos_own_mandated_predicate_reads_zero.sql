-- migration-version: 20260922171450
-- migration-name:    the_depot_is_in_entity_id_and_every_query_written_to_this_repos_own_mandated_predicate_reads_zero
--
-- 0429  **Ten event types emit `p_entity_type := 'depot', p_entity_id := p_depot_id` and never pass
--       `p_depot_id`, so 17,817 depot events carry `depot_id IS NULL` — and rule 8 *mandates*
--       `WHERE depot_id = '11111111-…'` on every depot-predicated measurement. The house style and the
--       engine's own telemetry are in direct conflict, and the house style loses silently.** Diagnosed in
--       `db/checks/0344` (G155).
--
--       The cost was not a wrong number. `twin.staging_overflow` is the depot's own *"I am out of room"*
--       signal, and the question it answers — **how many vehicles can this depot comfortably stage, sort and
--       orchestrate**, which is rule 8's stated goal — looked unanswered for weeks while its answer
--       accumulated **3,128** times.
--
--       `forces_recert` **FALSE**, and §3 earns it rather than asserting it.
--
-- ══ §1 SCOPE: `entity_type='depot'` ONLY, BECAUSE THERE THE ENTITY *IS* THE DEPOT ══
--
-- `db/checks/0344` §4 said the fix was *"one argument: pass `p_depot_id` at the emit site."* **That was wrong
-- by two orders of magnitude** — it is ten event types, not one site:
--
--     twin.weather_tick 3,473 · twin.bess_dispatch 3,473 · twin.staging_overflow 3,240 ·
--     twin.recharge_stranded 2,372 · ottoq.bay_reservation_replanned 1,895 · twin.deploy_gate_summary 1,332 ·
--     twin.bay_credit_none 1,010 · twin.deploy_pressure_fasttrack 586 ·
--     ottoq.bay_reservation_activated_early 405 · twin.grid_voltage_sag 3
--
-- **And the partition is perfectly clean, which is what makes a central default the right shape rather than a
-- shortcut: an event type either ALWAYS passes `depot_id` or NEVER does.** Three types always do
-- (`ottoq.arrival_forecast` 4,063, `ottoq.indepot_approvals_decided` 1,124,
-- `ottoq.rider_flag_serviced_in_depot` 96). So this is not ten independent oversights to patch ten times and
-- then forget on the eleventh emitter; it is one missing default in the one writer they all go through.
--
-- **The identity holds, measured, not assumed** — over all 23,072 `entity_type='depot'` events:
--
--     entity_id naming something that is not a depot .......... 0
--     depot_id set AND disagreeing with entity_id ............. 0   (of 5,283 already-attributed rows)
--
-- So for this entity type the default **reproduces exactly what the correct emitters already do**, and it
-- still refuses to guess: the `EXISTS` against `depots` means an `entity_type='depot'` event whose
-- `entity_id` is not a depot leaves the column NULL rather than taking a fabricated value. There is no FK on
-- `ottoq_events.depot_id` to catch that for us — checked.
--
-- ══ §2 WHAT IS DELIBERATELY *NOT* FIXED, AND IT IS THE LARGER POPULATION ═════
--
-- **`entity_type='vehicle'` carries 17,842 unattributed events — MORE than the depot case — and this
-- migration leaves every one of them alone.** Led by `twin.oem_webhook_emitted` (9,380, 100% null),
-- `twin.service_completed` (4,178, 100%), `twin.vehicle_arrived` (2,432, 100%) and `fleet.arrival_delayed`
-- (1,071, 100%).
--
-- **The line is identity versus inference.** For `entity_type='depot'`, `entity_id` **is** the depot — filling
-- the column restates a fact already in the row. For a vehicle, the only central source is
-- `vehicles.home_depot_id`, which is where the vehicle *lives*, not where the event *happened*. On one site
-- those coincide, which is exactly why inferring it here would be invisible until a second site exists and
-- then wrong retroactively across the whole archive. **A default that is right only because rule 8 forbids a
-- second site is not a default, it is a latent defect.** Each of those emit sites has to pass the depot it
-- actually occurred at; filed as G158.
--
-- Note the one that is *not* in that class: `vehicle.state_changed` misses **258 of 247,345 (0.1%)**. A 100%
-- miss is a missing argument; a 0.1% miss is a conditional path, and a different investigation.
--
-- `system` (3,913), `structure` (75), `policy_param` (1) and 4 `sim_run` events legitimately have no depot.
-- The assertion function in (B) says so rather than leaving a reader to wonder.
--
-- ══ §3 `forces_recert` FALSE, EARNED ON THREE LEGS, AND P3 ASSERTS THE FIRST ══
--
-- `events` is one of the fourteen atoms, so the reflex is TRUE. The reflex is wrong here, and the reason is
-- worth stating because it is the same mistake in miniature as everything else on this branch — **"`events`
-- is an atom" is not the same claim as "the atom reads this column."**
--
--   1. **`h_evt` digests `event_type | entity_id | sim_clock_at` and nothing else.** Read from the live
--      `ottoq_determinism_pair` source, not remembered. **P3 asserts it**, so if a future change widens the
--      atom this file's classification fails loudly instead of ageing into a lie.
--   2. **No engine or harness reader filters `ottoq_events` on `depot_id`.** Of the fifteen functions that
--      read the table and mention the column, the four with a `depot_id` predicate on it are all audit or
--      reporting paths (`ottoq_compute_audit_trail_completeness`, `ottoq_generate_incident_report`,
--      `ottoq_replay_window`, the `ottoq_oem_dashboard_summary` view); every other reader keys on
--      `sim_run_id`.
--   3. **The one AFTER INSERT trigger that reads `NEW.depot_id` cannot be reached by this population.**
--      `ottoq_auto_generate_incident_report` short-circuits when the depot's slug is `benchmark%`, then
--      returns unless `severity='safety_critical'`. **Zero of the 17,817 are safety_critical** (the maximum is
--      `critical`, 366 on `twin.deploy_gate_summary`) and neither entity depot is the benchmark depot
--      (`nashville-flagship`, `grid-0169-smoke`). P3b asserts the severity leg, because that is the one a
--      future event type could violate — and if it ever does, filling the column would make the trigger
--      **skip** a report it currently generates, which is the trigger's own stated intent but would move
--      `h_evt` by removing an `incident.report_generated` event.
--
-- ══ §4 NO BACKFILL, AND NOT AS A JUDGEMENT CALL ═══════════════════════════════
--
-- `ottoq_events` rejects UPDATE and DELETE by trigger — `trg_ottoq_events_block_mutation` raises
-- *"ottoq_events is append-only"* unless `ottoq.retention` is set. **So a backfill would mean defeating an
-- append-only guard to edit signed history**, which is the `0329` lesson at its sharpest: the fingerprint was
-- sound and the evidence moved underneath it. Not doing it.
--
-- Nor is it needed. These rows are `class='engine'` — run-scoped working data — so the gap self-heals within
-- a run or two, and `0344` documents reading the historical rows through `entity_id`.
--
-- ══ §7 THE FIRST ATTEMPT TIMED OUT, AND THE CAUSE WAS IN MY OWN VERIFICATION ══
--
-- Recorded rather than quietly fixed, because the construction is dangerous and reads as ordinary SQL.
--
-- **V2 originally wrote `SELECT depot_id INTO … FROM ottoq_events WHERE event_id =
-- public.ottoq_record_event(…)`** — calling the writer inside the predicate. `ottoq_record_event` is
-- **VOLATILE**, so the planner is not permitted to fold it to a constant and may re-evaluate it **once per
-- row scanned**. On a table of this size that is one INSERT per existing row, from a three-line test.
--
-- **It rolled back cleanly and nothing landed** — verified afterwards: no `supabase_migrations` row, no
-- `ottoq_record_event` change, no instrument, no `0429_pre` snapshot, no lineage row. The whole-file
-- transaction is what made a runaway test harmless, which is the argument for the APPLYING.md shape.
--
-- Fixed by capturing the returned id into a variable first. V3 also called the instrument **twice** —
-- doubling a full-table aggregate for no extra information — now one call with a FILTER.
--
-- **And the attribution is measured, not assumed, because the double call was the more obvious suspect.**
-- `EXPLAIN ANALYZE` on the instrument's aggregate reads **2,938 ms over 775,287 events** (parallel seq scan,
-- one worker). So two calls is ~6 s against a 60 s budget and was never the timeout; 775,287 volatile
-- re-evaluations, each an INSERT plus two triggers, is. **The cheap suspect was the wrong one, and one
-- EXPLAIN separated them** — the same discipline this branch keeps arriving at from the other direction.
--
-- **THE STANDING TEST: never put a VOLATILE function in a WHERE clause.** Assign it, then predicate on the
-- assignment. And note the shape it shares with this branch's other findings: the statement was *correct* —
-- it does exactly what it says — and its cost was invisible in the reading.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is live ──
DO $$
DECLARE v_null int; v_types int;
BEGIN
  SELECT count(*), count(DISTINCT event_type) INTO v_null, v_types
    FROM public.ottoq_events WHERE entity_type='depot' AND depot_id IS NULL;
  IF v_null = 0 THEN
    RAISE EXCEPTION '0429 P1: no unattributed depot events -- either somebody fixed this or the ledger was '
                    'purged. Re-derive db/checks/0344 before applying.';
  END IF;
  RAISE NOTICE '0429 P1: % unattributed depot events across % event types', v_null, v_types;
END $$;

-- ── P2: the IDENTITY this default rests on. If entity_id can name something that is not a depot, or can
-- disagree with an explicitly-passed depot_id, then this is an inference and not an identity, and section 2's
-- whole argument collapses.
DO $$
DECLARE v_not_depot int; v_disagree int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.depots d WHERE d.id = e.entity_id)),
         count(*) FILTER (WHERE e.depot_id IS NOT NULL AND e.depot_id <> e.entity_id)
    INTO v_not_depot, v_disagree
    FROM public.ottoq_events e WHERE e.entity_type='depot' AND e.entity_id IS NOT NULL;
  IF v_not_depot <> 0 THEN
    RAISE EXCEPTION '0429 P2: % depot-entity events name an entity_id that is not a depot -- the identity '
                    'this default rests on does not hold. Do NOT apply; the fix belongs at the emit sites.',
                    v_not_depot;
  END IF;
  IF v_disagree <> 0 THEN
    RAISE EXCEPTION '0429 P2: % depot-entity events carry a depot_id that DISAGREES with entity_id -- the '
                    'two columns mean different things and this default would be wrong.', v_disagree;
  END IF;
  RAISE NOTICE '0429 P2: identity holds -- 0 non-depot entity_ids, 0 disagreements';
END $$;

-- ── P3: forces_recert FALSE is EARNED HERE, NOT ASSERTED IN PROSE.
-- Leg 1: the events atom must not digest depot_id. If a future change widens h_evt, this fails loudly.
DO $$
DECLARE v_expr text;
BEGIN
  SELECT substr(p.prosrc, position('''h_evt''' in p.prosrc), 600) INTO v_expr
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_expr IS NULL OR position('''h_evt''' in v_expr) = 0 THEN
    RAISE EXCEPTION '0429 P3: could not locate the h_evt expression -- re-derive before classifying this '
                    'migration as forces_recert FALSE';
  END IF;
  IF v_expr LIKE '%depot_id%' THEN
    RAISE EXCEPTION '0429 P3: the events atom NOW DIGESTS depot_id. This migration changes that column, so '
                    'it forces a recert -- change the lineage row to TRUE and re-read section 3.';
  END IF;
  RAISE NOTICE '0429 P3: h_evt does not digest depot_id -- leg 1 of forces_recert FALSE holds';
END $$;

-- Leg 3: the one AFTER INSERT trigger reading NEW.depot_id gates on safety_critical. Assert the affected
-- population cannot reach it. (Leg 2 -- no engine reader filters on the column -- is a source census
-- recorded in section 3; it is not asserted here because a static reader census cannot be made sound, which
-- is 0326 §6(a)'s standing finding about caller searches.)
DO $$
DECLARE v_sc int;
BEGIN
  SELECT count(*) INTO v_sc FROM public.ottoq_events
   WHERE entity_type='depot' AND depot_id IS NULL AND severity='safety_critical';
  IF v_sc <> 0 THEN
    RAISE EXCEPTION '0429 P3b: % of the affected events are safety_critical, so filling depot_id would '
                    'change whether ottoq_auto_generate_incident_report fires -- which can add or remove an '
                    'incident.report_generated EVENT and therefore move h_evt. Reclassify as TRUE.', v_sc;
  END IF;
  RAISE NOTICE '0429 P3b: 0 safety_critical in the affected population -- leg 3 holds';
END $$;

-- ── P4: nothing in flight (G141 -- a pair is invisible to ottoq_sim_runs) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0429 P4: % run(s) running/paused -- apply between runs', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid() AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN RAISE EXCEPTION '0429 P4b: a determinism pair is in flight (G141)'; END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0429_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_record_event';

-- ── (A) THE DEFAULT, IN THE ONE WRITER THEY ALL GO THROUGH ──
DO $$
DECLARE v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_record_event';
  IF v_def IS NULL THEN RAISE EXCEPTION '0429: public.ottoq_record_event not found'; END IF;

  v_anchor := E'    p_fleet_operator_id, p_depot_id,\n';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0429 (A): anchor matched % times, expected 1 -- re-derive from pg_get_functiondef',
                    v_hits;
  END IF;

  -- 0429 (G155): an explicitly-passed p_depot_id ALWAYS wins -- COALESCE order is the whole safety
  -- argument. The default applies only where entity_id IS the depot by definition, and only when that
  -- entity really is a depot, so an entity_type='depot' event naming something else leaves the column
  -- NULL rather than taking a fabricated value (there is no FK here to catch that). A vehicle's depot is
  -- deliberately NOT inferred -- see section 2.
  v_insert := E'    p_fleet_operator_id,\n'
           || E'    COALESCE(p_depot_id,\n'
           || E'             CASE WHEN p_entity_type = ''depot''\n'
           || E'                       AND EXISTS (SELECT 1 FROM public.depots d WHERE d.id = p_entity_id)\n'
           || E'                  THEN p_entity_id END),\n';

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0429 (A): byte delta % <> expected % -- refusing a substitution that did more than one '
                    'replacement', length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0429 (A): ottoq_record_event defaults depot_id from entity_id for depot events, +% bytes',
               length(v_new) - length(v_def);
END $$;

-- ── (B) THE INSTRUMENT, SO THE REMAINING GAP IS COUNTABLE RATHER THAN INVISIBLE ──
-- The defect was not that the column was empty; it was that nothing said so. This names every class,
-- including the two it deliberately does not fix.
CREATE OR REPLACE FUNCTION public.ottoq_assert_event_depot_attribution(p_sim_run_id uuid DEFAULT NULL)
RETURNS TABLE (entity_type text, attribution_class text, events bigint, unattributed bigint, verdict text)
LANGUAGE sql STABLE AS $body$
  SELECT e.entity_type,
         CASE
           WHEN e.entity_type = 'depot'   THEN 'identity'
           WHEN e.entity_type = 'vehicle' THEN 'derivable_not_inferred'
           WHEN e.entity_type IN ('system','structure','policy_param','sim_run')
                                          THEN 'no_depot_by_design'
           ELSE 'attributed_at_emit'
         END AS attribution_class,
         count(*) AS events,
         count(*) FILTER (WHERE e.depot_id IS NULL) AS unattributed,
         CASE
           WHEN e.entity_type IN ('system','structure','policy_param','sim_run')
             THEN 'NO_DEPOT_BY_DESIGN'
           WHEN count(*) FILTER (WHERE e.depot_id IS NULL) = 0
             THEN 'OK'
           WHEN e.entity_type = 'depot'
             THEN 'GAP -- pre-0429 rows only; ottoq_events is append-only so these are never backfilled. '
               || 'A non-zero count scoped to a run that STARTED after 0429 is a real regression.'
           WHEN e.entity_type = 'vehicle'
             THEN 'NOT_INFERRED BY DESIGN (G158) -- the depot is derivable from vehicles.home_depot_id, '
               || 'which is where the vehicle lives, not where the event happened. Each emit site must pass '
               || 'the depot it occurred at. Inferring it centrally is invisible on one site and wrong '
               || 'retroactively once a second exists.'
           ELSE 'GAP -- this entity type attributes at the emit site; a null is a missing argument'
         END AS verdict
    FROM public.ottoq_events e
   WHERE p_sim_run_id IS NULL OR e.sim_run_id = p_sim_run_id
   GROUP BY 1, 2
   ORDER BY count(*) FILTER (WHERE e.depot_id IS NULL) DESC, count(*) DESC;
$body$;

COMMENT ON FUNCTION public.ottoq_assert_event_depot_attribution(uuid) IS
  'G155/0429. Per entity_type: how many events carry no depot_id, and whether that is a defect. '
  'Rule 8 mandates WHERE depot_id = <twin> on every depot-predicated measurement, so an unattributed '
  'event is not a weaker number -- it silently returns ZERO and reads as "this never happens". That is how '
  'the depot''s own staging-overflow signal accumulated 3,128 twin-depot events that every capacity query '
  'missed (db/checks/0344). Pass a sim_run_id to scope it; the depot class should read OK on any run '
  'started after 0429. The vehicle class is EXPECTED to read NOT_INFERRED -- see 0429 section 2.';

-- ── V1: the default is present exactly once, and an explicit argument still wins ──
DO $$
DECLARE v_src text; v_coalesce int;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_record_event';
  v_coalesce := (length(v_src) - length(replace(v_src, 'COALESCE(p_depot_id', '')))
                / length('COALESCE(p_depot_id');
  IF v_coalesce <> 1 THEN
    RAISE EXCEPTION '0429 V1: COALESCE(p_depot_id appears % times, expected 1', v_coalesce;
  END IF;
  IF v_src NOT LIKE '%EXISTS (SELECT 1 FROM public.depots%' THEN
    RAISE EXCEPTION '0429 V1: the identity check against depots is missing -- the default would fabricate a '
                    'depot_id for an entity_type=''depot'' event naming something else, and there is no FK '
                    'on this column to catch it';
  END IF;
  RAISE NOTICE '0429 V1: default present once, identity check present';
END $$;

-- ── V2: FUNCTIONAL, on a rolled-back subtransaction. Three cases, because the COALESCE order and the
-- refusal-to-guess are the two things a source assertion cannot prove.
DO $$
DECLARE
  v_twin  uuid := '11111111-1111-1111-1111-111111111111';
  v_other uuid;
  v_id    uuid;
  v_got_default uuid; v_got_explicit uuid; v_got_refused uuid;
  v_ran boolean := false;
BEGIN
  SELECT id INTO v_other FROM public.depots WHERE id <> v_twin ORDER BY slug LIMIT 1;

  BEGIN
    -- The returned id is captured into a variable BEFORE it is used as a predicate. Writing
    -- `WHERE event_id = public.ottoq_record_event(...)` instead is what timed this migration out on its
    -- first attempt: ottoq_record_event is VOLATILE, so the planner may not fold it to a constant and
    -- re-evaluates it PER ROW SCANNED -- i.e. one INSERT into ottoq_events per existing row. See section 7.

    -- (a) depot event, no p_depot_id  -> filled from entity_id
    v_id := public.ottoq_record_event(
       p_actor_type := 'ottoq_engine', p_event_type := 'twin.staging_overflow',
       p_entity_type := 'depot', p_entity_id := v_twin,
       p_payload := jsonb_build_object('probe','0429_v2a'));
    SELECT e.depot_id INTO v_got_default FROM public.ottoq_events e WHERE e.event_id = v_id;

    -- (b) depot event WITH an explicit p_depot_id -> the argument wins, the default must not override it
    v_id := public.ottoq_record_event(
       p_actor_type := 'ottoq_engine', p_event_type := 'twin.staging_overflow',
       p_entity_type := 'depot', p_entity_id := v_twin, p_depot_id := v_other,
       p_payload := jsonb_build_object('probe','0429_v2b'));
    SELECT e.depot_id INTO v_got_explicit FROM public.ottoq_events e WHERE e.event_id = v_id;

    -- (c) entity_type='depot' but entity_id is NOT a depot -> must stay NULL, never fabricate
    v_id := public.ottoq_record_event(
       p_actor_type := 'ottoq_engine', p_event_type := 'twin.staging_overflow',
       p_entity_type := 'depot', p_entity_id := '00000000-0000-0000-0000-000000000000'::uuid,
       p_payload := jsonb_build_object('probe','0429_v2c'));
    SELECT e.depot_id INTO v_got_refused FROM public.ottoq_events e WHERE e.event_id = v_id;

    v_ran := true;
    RAISE EXCEPTION 'OTTOQ_0429_V2_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0429_V2_ROLLBACK' THEN
      RAISE EXCEPTION '0429 V2: the probe failed for the wrong reason: %', SQLERRM;
    END IF;
  END;
  -- PL/pgSQL variables are not transactional, so the three readings survive the rollback above while the
  -- three probe events do not. ottoq_events is append-only (section 4), so leaving them is not an option.
  IF NOT v_ran THEN RAISE EXCEPTION '0429 V2: the probe never completed'; END IF;

  IF v_got_default IS DISTINCT FROM v_twin THEN
    RAISE EXCEPTION '0429 V2(a): a depot event with no p_depot_id got %, expected % -- the default did not '
                    'fire, which is the entire migration', v_got_default, v_twin;
  END IF;
  IF v_got_explicit IS DISTINCT FROM v_other THEN
    RAISE EXCEPTION '0429 V2(b): an EXPLICIT p_depot_id of % was overridden to % -- the COALESCE order is '
                    'wrong and this default is now corrupting correctly-attributed events',
                    v_other, v_got_explicit;
  END IF;
  IF v_got_refused IS NOT NULL THEN
    RAISE EXCEPTION '0429 V2(c): an entity_type=''depot'' event naming a NON-depot was attributed to % -- '
                    'the default is guessing instead of restating an identity', v_got_refused;
  END IF;
  RAISE NOTICE '0429 V2: default fires (%), explicit argument wins (%), non-depot refused (NULL)',
               v_got_default, v_got_explicit;
END $$;

-- ── V3: the instrument answers, and names the class it deliberately does not fix ──
DO $$
DECLARE v_rows int; v_vehicle text;
BEGIN
  -- ONE call, not two: the instrument aggregates the whole event table, so calling it twice doubles a
  -- full scan for no information. (Also part of what timed out the first attempt.)
  SELECT count(*), max(a.verdict) FILTER (WHERE a.entity_type = 'vehicle')
    INTO v_rows, v_vehicle
    FROM public.ottoq_assert_event_depot_attribution() a;
  IF v_rows = 0 THEN RAISE EXCEPTION '0429 V3: the attribution instrument returned no rows'; END IF;
  IF v_vehicle IS NOT NULL AND v_vehicle NOT LIKE 'NOT_INFERRED%' AND v_vehicle <> 'OK' THEN
    RAISE EXCEPTION '0429 V3: the vehicle class reads "%" -- expected NOT_INFERRED or OK', v_vehicle;
  END IF;
  RAISE NOTICE '0429 V3: instrument returns % classes; vehicle reads %', v_rows, coalesce(v_vehicle,'(none)');
END $$;

-- ── LINEAGE. In the file and inside the transaction. ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0429_the_depot_is_in_entity_id_and_every_query_written_to_this_repos_own_mandated_predicate_reads_zero',
  false,
  'Defaults ottoq_events.depot_id from entity_id when entity_type=''depot'' and that entity really is a '
  'depot, fixing 17,817 unattributed depot events across TEN event types. Rule 8 mandates '
  'WHERE depot_id = <twin> on every depot-predicated measurement, so these events made every capacity query '
  'silently return ZERO -- which is how the depot''s own staging-overflow signal accumulated 3,128 twin '
  'events answering the company''s headline question while it looked unanswered (db/checks/0344, G155). '
  'db/checks/0344 said the fix was "one argument at the emit site"; it is ten event types, and the partition '
  'is perfectly clean (a type either always passes depot_id or never does), which is why one default in the '
  'single shared writer is the right shape. IDENTITY NOT INFERENCE: measured 0 of 23,072 depot-entity events '
  'name a non-depot entity_id and 0 of the 5,283 attributed rows disagree with it, and the EXISTS guard '
  'leaves the column NULL rather than fabricating a value (there is no FK here). An explicitly-passed '
  'p_depot_id always wins -- V2(b) asserts the COALESCE order, V2(c) asserts the refusal to guess. '
  'DELIBERATELY NOT FIXED: entity_type=''vehicle'' carries 17,842 unattributed events -- MORE than the depot '
  'case -- because a vehicle''s only central source is home_depot_id, where it LIVES rather than where the '
  'event happened; that inference is invisible on one site and wrong retroactively once a second exists '
  '(G158). NO BACKFILL, and not as a judgement call: ottoq_events rejects UPDATE by trigger, so a backfill '
  'would mean defeating an append-only guard to edit signed history (the 0329 lesson), and the rows are '
  'class=engine so the gap self-heals per run. forces_recert FALSE is EARNED not assumed: h_evt digests '
  'event_type|entity_id|sim_clock_at only (P3 asserts it, so a future widening fails loudly), no engine or '
  'harness reader filters this table on depot_id, and the one AFTER INSERT trigger reading NEW.depot_id '
  'gates on severity=safety_critical which 0 of the affected population is (P3b asserts it). "events is an '
  'atom" is not the same claim as "the atom reads this column".')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` FALSE — no sweep is forced, and §3 is why.
--
-- Then, on a run STARTED after the apply:
--
--   SELECT * FROM public.ottoq_assert_event_depot_attribution('<new sim_run_id>');
--
-- **The `depot` row must read `unattributed = 0` / `OK`.** The `vehicle` row is expected to read
-- `NOT_INFERRED BY DESIGN (G158)` — that is the honest state, not a failure.
--
-- And the thing this was for, now writable in the house style for the first time:
--
--   SELECT count(*), round(avg((payload->>'overflow')::numeric),1)  AS mean_in_overflow,
--          round(avg((payload->>'escalated')::numeric),1)           AS mean_past_patience
--     FROM public.ottoq_events
--    WHERE event_type='twin.staging_overflow'
--      AND depot_id='11111111-1111-1111-1111-111111111111';
--
-- Before this migration that query returned **zero rows on 3,240 events**.
--
-- **Still open and NOT closed by this file:** `0344` §3's trap — the payload's `wash_cap`/`svc_cap`/
-- `deploy_cap` are **constants** (3.00 / 2.00 / 20.00, one distinct value each, never 0), i.e. configured
-- capacity restated per event rather than remaining headroom. A reader concludes nothing was ever exhausted
-- while the same payload reports 30 vehicles in overflow. Rename them or make them mean remaining; they
-- appear in six functions, so it is not a one-line edit.
--
-- ══ APPLIED 20260922171450 (2026-09-22 17:14:50 UTC / 12:14 PM CT) ═══════════
--
-- All preconditions passed. **V2 passed all three cases, which is what this file is really about:**
-- (a) a depot event with no `p_depot_id` came back attributed to the twin depot; (b) an event carrying an
-- EXPLICIT `p_depot_id` of the benchmark depot **was not overridden** — the COALESCE order holds; (c) an
-- `entity_type='depot'` event naming a non-depot came back **NULL**, so the default restates an identity and
-- does not guess. V3 returns 10 classes with `vehicle` reading `NOT_INFERRED BY DESIGN (G158)`.
--
-- ══ §8 APPLY-CHANNEL DEVIATION, DECLARED, AND IT IS LARGER THAN THE USUAL ONE ══
--
-- **`apply_migration` timed out at 60 s on this file THREE times, and the cause is the channel, not the
-- SQL.** That is stated as a measurement, not an excuse:
--
--   * every block was timed individually — **P1 82 ms, P2 47 ms, P3b 27 ms, the V3 aggregate 1,167 ms**
--     (2,938 ms in the worst case over 775,287 events), `CREATE OR REPLACE ottoq_record_event` **12 ms**,
--     one `ottoq_record_event` + lookup **9 ms**;
--   * measured again **while a recert sweep was active** (`sweep_active=1`): the full aggregate ran in
--     **197 ms** and the function replacement in **12 ms**, so neither saturation nor the sweep explains it;
--   * the recert runner holds only `AccessShareLock` on `ottoq_cert_lineage`, which does not conflict with
--     this file's `INSERT … ON CONFLICT`, so it is not lock contention either;
--   * the third attempt stripped every comment and removed the `CREATE FUNCTION` entirely and **still**
--     timed out, which rules out payload size and the custom dollar-quote tag;
--   * **the identical statements then ran through `execute_sql` in under a second.**
--
-- **So it was applied through `execute_sql` in two ordered calls** — preconditions + snapshot + change + V1,
-- then V2 + V3 — and the `supabase_migrations` row and lineage row were written explicitly afterwards.
-- **What is lost by that route is the single enclosing transaction**, which is why the order matters and why
-- the snapshot is taken before the change: a failure in the second call would have left the change applied
-- and unverified, recoverable from `ottoq_schema_snapshots` label `0429_pre`. It did not fail.
--
-- **Three of my own attempts also rolled back cleanly and left nothing behind** — verified each time against
-- `supabase_migrations`, `pg_proc`, `ottoq_cert_lineage` and `ottoq_schema_snapshots` rather than assumed.
-- The first of those was a real defect in my own verification and is recorded in §7; the other two were not.
--
-- **The instrument in (B) was created by an earlier isolation test and therefore exists independently of the
-- ordered calls above.** It is `CREATE OR REPLACE`, so the file remains reproducible; noted because a reader
-- reconstructing history from `ottoq_schema_snapshots` would otherwise find no pre-image for it.
--
-- **THE STANDING NOTE: the apply channel is not neutral, and "it did not apply" is not the same as "it
-- failed."** Check `supabase_migrations`, the catalog and the lineage table before re-running anything —
-- all three times the answer was a clean rollback, and assuming otherwise would have produced a duplicate
-- snapshot row and a second lineage write.
