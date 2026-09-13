-- migration-version: 20260913231758
-- migration-name:    0271_the_outbound_command_stream_is_the_only_stream_without_provenance
--
-- 0271  THE OUTBOUND COMMAND STREAM IS THE ONLY STREAM WITHOUT PROVENANCE
--
-- ---------------------------------------------------------------------------
-- WHAT THE FLEET API ACTUALLY RETURNS TODAY
--
-- public.ottoq_fleet_pending_commands is the outbound surface: the thing a
-- fleet operator or an OEM backend polls to collect OTTO-Q's instructions for
-- its vehicles. It is the only reader of ottoq_vehicle_commands that faces
-- outward. Its provenance test, installed by 0151, is:
--
--     WHERE c.status = 'issued' AND c.sim_run_id IS NULL
--
-- Measured 2026-09-13 against the live engine:
--
--   ottoq_vehicle_commands rows                     794,745
--   ... with sim_run_id IS NULL                           5
--   ... status = 'issued'                               412
--   ... status = 'issued' AND sim_run_id IS NULL           4   <- all the API can return
--
-- And those four rows are:
--
--   4 x command_type 'stage', issued_by 'decide_tick', 2026-07-26,
--   depot = OTTOYARD Nashville Flagship, depots.feed_mode = 'sim'
--
-- They are twin output. Every row the production fleet API is capable of
-- returning is simulation. 0151's title -- "the fleet API returns only
-- production commands" -- is false, and was false the day it was written: the
-- four rows it classified as production are the same four rows, and it
-- classified them that way because they have no run stamp, not because they
-- came from the real world.
--
-- ---------------------------------------------------------------------------
-- WHY sim_run_id CANNOT BE THE TEST, IN EITHER DIRECTION
--
-- 1. A MISSING RUN STAMP IS NOT PRODUCTION. It is a row written before the
--    stamping discipline existed, or by a path that forgot. All five unstamped
--    rows in this database are at feed_mode='sim' depots but one.
--
-- 2. A PRESENT RUN STAMP IS NOT SIMULATION. The production orchestration loop
--    (P1) runs as ottoq_sim_runs rows with run_by='production_live', and
--    ottoq.ottoq_emit_vehicle_command stamps sim_run_id := p_run for whoever
--    calls it. Measured: 8 production_live runs, 259 commands, 152 of them
--    still 'issued'. Not one of them is visible to the fleet API, and the
--    better the production loop works the emptier that API gets. The filter
--    is self-defeating by construction.
--
-- 3. EVERY OTHER STREAM IN THIS DATABASE ALREADY SOLVED THIS. ottoq_events and
--    ottoq_telemetry_packets both carry data_source on the row ('production' /
--    'twin'). CLAUDE.md 2.8 makes that co-existence pattern explicit: sim and
--    production rows share a table and are told apart by a column, which is
--    what lets the metrics layer treat them identically. The outbound command
--    stream -- the one stream that can reach real hardware -- is the only one
--    that never got the column, and sim_run_id IS NULL is the workaround that
--    grew in its place.
--
-- ---------------------------------------------------------------------------
-- THE FIX: 0073'S RULE, ON THE ROW, STAMPED BY A TRIGGER
--
-- 0073 established the rule and 0228 propagated it to the event and SDR
-- streams: the depot's feed says what a row is.
--
--     feed_mode = 'external' -> 'production',  everything else -> 'twin'
--
-- This migration gives ottoq_vehicle_commands the same column, stamped by a
-- BEFORE trigger that overwrites whatever the caller supplied, so provenance
-- cannot be forged by the writer. The API then filters on the column.
--
-- COST IS ZERO ROWS REWRITTEN. The column is added NOT NULL DEFAULT 'twin',
-- which since PG11 is a catalog-only change (attmissingval, no table rewrite)
-- on a 395 MB / 794,745-row table. 'twin' is also the correct fail-closed
-- default for an outbound production surface: an unlabelled row is not served.
-- The backfill to 'production' is then exactly the set of rows at external
-- depots -- one row today.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not try to distinguish a twin
-- run pointed at a real depot from the production loop pointed at the same
-- depot. Under this rule both stamp 'production', and that is the safe
-- reading: a command written into a real depot's queue may reach real
-- hardware regardless of which loop produced it. The live hazard that follows
-- from it is asserted below (A6) and recorded here rather than silently fixed:
-- the depot named "P2 Ledger-Only Proof Rig (retired test fixture)" carries
-- feed_mode='external'. A retired test fixture must not be labelled external.
-- It has zero commands today; A6 refuses to apply if that ever stops being
-- true, so the hazard cannot turn into a leak without this migration noticing.
--
-- forces_recert = FALSE, and it is checked rather than asserted by hand: both
-- h_cmd producers (ottoq_determinism_pair and ottoq_ab_arm_atoms) build the
-- command hash from an explicit six-column list --
--   issued_at|vehicle_id|command_type|stall_id|status|reason_code
-- -- with no SELECT * and no to_jsonb(c), so a new column cannot enter the
-- certified verdict. P5 below pins that, and the pair's own prosrc pin
-- 8a35b8c874fed154cc216140faec0274 is re-checked unchanged at the end.
--
-- data_source is not a run reference, so it is out of the run-scope registry's
-- scope (227 rows, all of them run/tick references). A7 asserts the registry
-- is unchanged rather than leaving that as an assumption.
-- ---------------------------------------------------------------------------

SET LOCAL statement_timeout = '10min';

-- ===========================================================================
-- PRE-FLIGHT: the defect, asserted before it is fixed
-- ===========================================================================
CREATE TEMP TABLE pg_temp_0271_before AS
SELECT array_agg(command_id ORDER BY command_id) AS ids,
       count(*)                                  AS n
  FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000);

DO $pre$
DECLARE
  v_n int; v_before record; v_twin int; v_stamped int; v_pl int;
BEGIN
  -- P1: exactly one arity, and it is the function this migration read.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_fleet_pending_commands';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0271 P1: expected 1 arity of ottoq_fleet_pending_commands, found %', v_n;
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ottoq_fleet_pending_commands')
     IS DISTINCT FROM 'b8af618b8c9b820db749858690e0375d' THEN
    RAISE EXCEPTION '0271 P1: ottoq_fleet_pending_commands is not the body this migration was written against';
  END IF;

  -- P2: refuse to double-apply.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_vehicle_commands'
                AND column_name='data_source') THEN
    RAISE EXCEPTION '0271 P2: ottoq_vehicle_commands.data_source already exists';
  END IF;

  -- P3: THE CONVICTION. Everything the production API can return is twin.
  SELECT * INTO v_before FROM pg_temp_0271_before;
  IF v_before.n = 0 THEN
    RAISE EXCEPTION '0271 P3: the API returns nothing at all -- the before/after comparison would prove nothing';
  END IF;
  SELECT count(*) INTO v_twin
    FROM public.ottoq_vehicle_commands c
    LEFT JOIN public.depots d ON d.id = c.depot_id
   WHERE c.command_id = ANY (v_before.ids)
     AND COALESCE(d.feed_mode,'(none)') <> 'external';
  IF v_twin <> v_before.n THEN
    RAISE EXCEPTION '0271 P3: % of % rows the API returns are twin -- expected all of them; '
                    'the premise of this migration does not hold', v_twin, v_before.n;
  END IF;

  -- P4: and the run stamp is not what separates them. Every issued command
  -- that carries a run id is also at a non-external depot, so the old filter
  -- excluded those for a reason it never actually tested.
  SELECT count(*) INTO v_stamped
    FROM public.ottoq_vehicle_commands c
    LEFT JOIN public.depots d ON d.id = c.depot_id
   WHERE c.status='issued' AND c.sim_run_id IS NOT NULL
     AND COALESCE(d.feed_mode,'(none)') = 'external';
  IF v_stamped <> 0 THEN
    RAISE EXCEPTION '0271 P4: % issued commands at external depots carry a run id; '
                    'read them before changing the predicate', v_stamped;
  END IF;
  SELECT count(*) INTO v_pl
    FROM public.ottoq_vehicle_commands c
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id AND r.run_by = 'production_live'
   WHERE c.status = 'issued';
  IF v_pl = 0 THEN
    RAISE EXCEPTION '0271 P4: no issued production_live commands found -- point 2 of the header is stale, re-measure';
  END IF;
  RAISE NOTICE '0271 P4: % issued commands from production_live runs, none of them visible to the fleet API', v_pl;

  -- P5: no h_cmd producer can see a new column. Positive form first -- all
  -- three name their six columns -- because a negative-only check would also
  -- pass if the producers vanished.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_determinism_pair','ottoq_determinism_pair_replay','ottoq_ab_arm_atoms')
     AND p.prosrc ~ 'issued_at::text\|\|''\|''\|\|vehicle_id::text';
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0271 P5: expected 3 h_cmd producers naming their columns explicitly, found %', v_n;
  END IF;
  -- and nothing else takes the whole row. Two exemptions, both by name and
  -- both earned in the dry run of this file:
  --   ottoq_ack_vehicle_command does SELECT * INTO v_cmd -- a %ROWTYPE read
  --     that hashes nothing and widens harmlessly;
  --   the to_jsonb(c) arm only means anything for a function that reads THIS
  --     table, so the table predicate is part of the test. Without it the
  --     first dry run tripped on twin.ottoq_grid_fixture_create, which has a
  --     to_jsonb(c) over an unrelated alias and never touches commands.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public','ottoq','twin')
       AND p.prosrc ~ 'ottoq_vehicle_commands'
       AND p.proname <> 'ottoq_ack_vehicle_command'
       AND (p.prosrc ~ 'to_jsonb\s*\(\s*c\s*\)'
         OR p.prosrc ~* 'select\s+\*[^;]{0,60}from\s+(public\.)?ottoq_vehicle_commands')) THEN
    RAISE EXCEPTION '0271 P5: a function takes the whole ottoq_vehicle_commands row; '
                    'adding a column could change a hash and forces_recert is not FALSE';
  END IF;

  RAISE NOTICE '0271 pre-flight: API returns % rows, all twin', v_before.n;
END $pre$;

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

-- (a) the column. NOT NULL DEFAULT 'twin' is catalog-only on PG11+ -- no
--     rewrite of 395 MB -- and fail-closed: an unlabelled row is never served.
ALTER TABLE public.ottoq_vehicle_commands
  ADD COLUMN data_source text NOT NULL DEFAULT 'twin';

ALTER TABLE public.ottoq_vehicle_commands
  ADD CONSTRAINT ottoq_vehicle_commands_data_source_check
  CHECK (data_source IN ('production','twin'));

COMMENT ON COLUMN public.ottoq_vehicle_commands.data_source IS
  '0271: provenance of the outbound command, stamped from depots.feed_mode by '
  'ottoq_vehicle_commands_provenance (0073''s rule, propagated by 0228). '
  'Never set by the caller. ottoq_fleet_pending_commands serves ''production'' only.';

-- (b) the backfill: 0073's rule over history.
UPDATE public.ottoq_vehicle_commands c
   SET data_source = 'production'
  FROM public.depots d
 WHERE d.id = c.depot_id AND d.feed_mode = 'external';

-- (c) the stamp. The caller does not get a vote.
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_commands_stamp_provenance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- 0271: 0073's rule on the row. NEW.data_source is overwritten
  -- unconditionally, so whoever writes the command cannot forge its
  -- provenance. A command with no resolvable depot is not at a real depot and
  -- fails closed to 'twin'.
  NEW.data_source := COALESCE(
    (SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
       FROM public.depots d
      WHERE d.id = NEW.depot_id),
    'twin');
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS ottoq_vehicle_commands_provenance ON public.ottoq_vehicle_commands;
CREATE TRIGGER ottoq_vehicle_commands_provenance
  BEFORE INSERT OR UPDATE OF depot_id ON public.ottoq_vehicle_commands
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_vehicle_commands_stamp_provenance();

-- (d) the API reads the column instead of guessing from the run stamp.
DO $edit$
DECLARE v_def text; v_a text := $a$AND c.sim_run_id IS NULL$a$; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  v_hits := (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0271: anchor "%" expected exactly once, found %', v_a, v_hits;
  END IF;
  EXECUTE replace(v_def, v_a, $b$AND c.data_source = 'production'$b$);
END $edit$;

-- ===========================================================================
-- POST: every assertion below fails on the pre-image
-- ===========================================================================
DO $post$
DECLARE
  v_before record; v_after int; v_n int; v_prod int; v_bad int;
  v_lab uuid; v_lab_veh uuid; v_sim uuid; v_sim_veh uuid; v_run uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_ds text; v_seen int;
BEGIN
  SELECT * INTO v_before FROM pg_temp_0271_before;

  -- A1: the column is there, NOT NULL, defaulted 'twin', constrained.
  SELECT count(*) INTO v_n FROM pg_attribute a
   WHERE a.attrelid='public.ottoq_vehicle_commands'::regclass
     AND a.attname='data_source' AND a.attnotnull;
  IF v_n <> 1 THEN RAISE EXCEPTION '0271 A1: data_source missing or nullable'; END IF;
  IF (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d
       JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
      WHERE a.attrelid='public.ottoq_vehicle_commands'::regclass AND a.attname='data_source')
     IS DISTINCT FROM '''twin''::text' THEN
    RAISE EXCEPTION '0271 A1: default is not the fail-closed ''twin''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid='public.ottoq_vehicle_commands'::regclass
                    AND conname='ottoq_vehicle_commands_data_source_check' AND convalidated) THEN
    RAISE EXCEPTION '0271 A1: the data_source CHECK is absent or not validated';
  END IF;

  -- A2: the backfill obeys 0073's rule, in both directions.
  SELECT count(*) INTO v_bad
    FROM public.ottoq_vehicle_commands c
    LEFT JOIN public.depots d ON d.id = c.depot_id
   WHERE (c.data_source = 'production') <> (COALESCE(d.feed_mode,'(none)') = 'external');
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0271 A2: % rows disagree with depots.feed_mode', v_bad;
  END IF;
  SELECT count(*) INTO v_prod FROM public.ottoq_vehicle_commands WHERE data_source='production';
  RAISE NOTICE '0271 A2: % of % command rows are production', v_prod,
               (SELECT count(*) FROM public.ottoq_vehicle_commands);

  -- A3: the twin rows are gone from the outbound API. Two-sided: the count
  -- moved, AND every id it used to hand out is provably twin.
  SELECT count(*) INTO v_after FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000);
  IF v_after >= v_before.n THEN
    RAISE EXCEPTION '0271 A3: API returned % rows before and % after -- the leak did not close',
                    v_before.n, v_after;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000) f
              WHERE f.command_id = ANY (v_before.ids)) THEN
    RAISE EXCEPTION '0271 A3: a formerly-returned twin command is still served';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000) f
              JOIN public.ottoq_vehicle_commands c ON c.command_id=f.command_id
              LEFT JOIN public.depots d ON d.id=c.depot_id
             WHERE COALESCE(d.feed_mode,'(none)') <> 'external') THEN
    RAISE EXCEPTION '0271 A3: the API is still serving a row from a non-external depot';
  END IF;
  RAISE NOTICE '0271 A3: outbound API % rows -> % rows, all remaining rows external-feed',
               v_before.n, v_after;

  -- A4 + A5 need one real vehicle at each kind of depot, and one real run.
  SELECT d.id INTO v_lab FROM public.depots d
   WHERE d.feed_mode='external' AND d.name NOT ILIKE '%retired%' ORDER BY d.id LIMIT 1;
  SELECT d.id INTO v_sim FROM public.depots d WHERE d.feed_mode='sim' ORDER BY d.id LIMIT 1;
  IF v_lab IS NULL OR v_sim IS NULL THEN
    RAISE EXCEPTION '0271 A4: need one external and one sim depot to prove both directions';
  END IF;
  SELECT v.id INTO v_lab_veh FROM public.vehicles v WHERE v.current_depot_id=v_lab ORDER BY v.id LIMIT 1;
  SELECT v.id INTO v_sim_veh FROM public.vehicles v WHERE v.current_depot_id=v_sim ORDER BY v.id LIMIT 1;
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.run_by='production_live' ORDER BY r.started_at DESC LIMIT 1;
  IF v_lab_veh IS NULL OR v_sim_veh IS NULL OR v_run IS NULL THEN
    RAISE EXCEPTION '0271 A4: missing a vehicle or a production_live run for the live proof';
  END IF;

  -- A4: FORGERY. The caller declares the opposite of the truth, twice, and is
  -- overruled twice.
  INSERT INTO public.ottoq_vehicle_commands
    (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by, status, data_source)
  VALUES (NULL, v_sim, v_sim_veh, 'hold', '{"probe":"0271-A4"}'::jsonb, now(), 'migration_0271', 'issued', 'production')
  RETURNING command_id INTO v_c1;
  SELECT data_source INTO v_ds FROM public.ottoq_vehicle_commands WHERE command_id=v_c1;
  IF v_ds <> 'twin' THEN
    RAISE EXCEPTION '0271 A4: a caller forged production onto a sim depot -- got %', v_ds;
  END IF;

  INSERT INTO public.ottoq_vehicle_commands
    (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by, status, data_source)
  VALUES (NULL, v_lab, v_lab_veh, 'hold', '{"probe":"0271-A4"}'::jsonb, now(), 'migration_0271', 'issued', 'twin')
  RETURNING command_id INTO v_c2;
  SELECT data_source INTO v_ds FROM public.ottoq_vehicle_commands WHERE command_id=v_c2;
  IF v_ds <> 'production' THEN
    RAISE EXCEPTION '0271 A4: a real depot''s command was mislabelled -- got %', v_ds;
  END IF;

  -- A5: THE UNBLOCKING. A command at the real depot that CARRIES a run stamp
  -- -- precisely the row the old predicate made invisible, and precisely the
  -- row the production loop writes, because emit_vehicle_command stamps
  -- whatever run it was called with.
  INSERT INTO public.ottoq_vehicle_commands
    (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by, status)
  VALUES (v_run, v_lab, v_lab_veh, 'stage', '{"probe":"0271-A5"}'::jsonb, now(), 'migration_0271', 'issued')
  RETURNING command_id INTO v_c3;

  SELECT count(*) INTO v_seen FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000) f
   WHERE f.command_id = v_c3;
  IF v_seen <> 1 THEN
    RAISE EXCEPTION '0271 A5: a run-stamped command at a real depot is still invisible to the fleet API';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000) f
              WHERE f.command_id = v_c1) THEN
    RAISE EXCEPTION '0271 A5: the forged sim row reached the outbound API';
  END IF;
  RAISE NOTICE '0271 A5: a run-stamped real-depot command is served (%); the forged sim row is not', v_c3;

  DELETE FROM public.ottoq_vehicle_commands WHERE command_id IN (v_c1, v_c2, v_c3);
  IF (SELECT count(*) FROM public.ottoq_vehicle_commands WHERE issued_by='migration_0271') <> 0 THEN
    RAISE EXCEPTION '0271: probe rows survived cleanup';
  END IF;

  -- A6: the recorded hazard has not become a leak.
  SELECT count(*) INTO v_n
    FROM public.ottoq_vehicle_commands c JOIN public.depots d ON d.id=c.depot_id
   WHERE d.feed_mode='external' AND d.name ILIKE '%retired%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0271 A6: a depot named retired carries feed_mode=external AND % commands; '
                    'the fleet API would now serve a test fixture as production', v_n;
  END IF;

  -- A7: the certified path is untouched.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair')
     IS DISTINCT FROM '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0271 A7: ottoq_determinism_pair changed -- forces_recert is not FALSE';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_run_scope_registry) <> 227 THEN
    RAISE EXCEPTION '0271 A7: the run-scope registry moved; data_source is not a run reference and should not have';
  END IF;

  RAISE NOTICE '0271: A1-A7 passed. Provenance is on the row, stamped from the depot, '
               'unforgeable by the caller, and the outbound API serves production only.';
END $post$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- Applied 2026-09-13 23:17:58 UTC as version 20260913231758 (6:17 PM CT).
--
--   ottoq_fleet_pending_commands
--     pre-image  md5(prosrc) = b8af618b8c9b820db749858690e0375d
--     post-image md5(prosrc) = 9e71576c141047b136bfd149b1626f05
--   ottoq_determinism_pair prosrc pin 8a35b8c874fed154cc216140faec0274 unchanged.
--
-- LIVE VERIFICATION AFTER APPLY, read back independently of this file's own
-- assertions:
--
--   ottoq_fleet_pending_commands(NULL,NULL,1e6)  ->  0 rows  (was 4, all twin)
--   ottoq_vehicle_commands data_source           ->  production 1, twin 794,744
--   trigger ottoq_vehicle_commands_provenance    ->  present, tgenabled = 'O'
--
-- DRY RUN. The whole file was executed byte for byte against the live database
-- inside BEGIN ... ROLLBACK before this apply, per the rule adopted at 0270:
-- dry-run the file, byte for byte, or do not claim it was dry-run. The FIRST
-- dry run FAILED, on this file's own P5:
--
--   0271 P5: a function takes the whole ottoq_vehicle_commands row
--
-- The to_jsonb(c) arm had been widened and had lost its "and this function
-- reads ottoq_vehicle_commands" predicate, so it matched
-- twin.ottoq_grid_fixture_create -- a to_jsonb(c) over an unrelated alias in a
-- function that never touches commands. The predicate is back and the reason
-- is recorded in P5 itself. Nothing was applied on that attempt.
--
-- WHAT THIS FILE FORGOT, recorded here because the omission is the interesting
-- part: it did not write its own ottoq_cert_lineage row. forces_recert is
-- COALESCE(l.forces_recert, TRUE), so no row means FORCING, and the recert
-- floor jumped from 2026-09-12 16:50:23.319089+00 to this migration's own
-- apply stamp -- restarting every certification column's streak for a change
-- that adds a column no hash reads. 0272 repairs it and ships the CI guard
-- (tests/test_migration_hygiene.py::test_recent_migrations_classify_themselves)
-- that makes the omission impossible to repeat quietly. This was the second
-- occurrence; 0268 was the first, for 0267.
-- ---------------------------------------------------------------------------
