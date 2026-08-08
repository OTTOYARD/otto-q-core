-- migration-version: 20260808182226
-- migration-name:    a_run_owns_its_rows
--
-- 0022_a_run_owns_its_rows.sql
-- ============================================================================
-- A RUN OWNS ITS ROWS, AND DELETING A RUN CANNOT SILENTLY ERASE THEM
-- ============================================================================
--
-- 0020 fixed WHICH ROW a run writes (run-scoped uniqueness on visit_key). It did
-- not fix WHETHER A ROW STILL HAS A RUN. This migration fixes the second half.
--
-- ══ WHAT WAS ACTUALLY WRONG, MEASURED, NOT ASSUMED ══
--
--   SELECT conrelid::regclass FROM pg_constraint
--    WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass;   -->  0 rows
--
--   `public` holds 226 foreign keys. Not one points at the run table. This was
--   never "ottoq_visit_needs is missing an FK" — NO TABLE HAS EVER HAD ONE.
--   `ottoq_sim_runs` has had a primary key on `sim_run_id` the whole time, so the
--   parent was always available. It was simply never referenced.
--
--   190 columns in `public` carry a run id (`sim_run_id`, `run_id`,
--   `owning_sim_run_id`, `source_run_id`). 124,444 rows across 147 tables point
--   at a run that no longer exists.
--
-- ══ WHY `ottoq_purge_prior_runs` MANUFACTURES ORPHANS RATHER THAN CLEARING THEM ══
--
--   Read the pre-image (snapshotted below). Two structural facts:
--
--   (1) THE CHILD DELETE CANNOT REACH AN ORPHAN. It is scoped by a subquery on
--       the very parent row it is about to delete:
--           DELETE FROM public.%I
--            WHERE sim_run_id IN (SELECT sim_run_id FROM ottoq_sim_runs WHERE ...)
--       An orphan's run id is not in `ottoq_sim_runs`, so it never matches.
--       Once a row is orphaned no purge can ever reach it again. The population
--       is monotonic — it only grows.
--
--   (2) IT IS THE ORPHAN FACTORY. Children are deleted in a per-table loop whose
--       every failure is caught and swallowed into `v_failed` (non-fatal by
--       design). The parent `DELETE FROM ottoq_sim_runs` then runs
--       UNCONDITIONALLY, outside that loop. So every row in a table that was not
--       enumerated, errored, or was skipped is orphaned by the same call.
--       Not hypothetical: `site_energy_snapshots` holds 27,163 orphans across
--       477 dead run ids — that loop running 477 times against a table it cannot
--       see, because the enumeration is
--           WHERE column_name='sim_run_id' AND table_name LIKE 'ottoq%'
--       and `site_energy_snapshots` is not named `ottoq*`.
--
-- ══ THE LEAK IS LIVE RIGHT NOW, AND IT IS THE SAME SHAPE AS 0020's ══
--
--   `ottoq_build_decision_frame(p_depot_id)` takes NO run parameter and reads:
--       FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id
--       ORDER BY se.timestamp DESC LIMIT 1
--   Measured at the time of writing, the newest row for BOTH depots is an ORPHAN:
--       depot 1111…  28,789 rows, newest row belongs to dead run 29b72b2b…
--       depot 2222…   5,825 rows, newest row belongs to dead run 6256a99f…
--   That function feeds `ottoq_capture_decision_snapshot`, `ottoq_api_twin_get_state`
--   and `ottoq_score_run` — the decision recorder, the cockpit API and the scorer
--   are all being served a dead run's grid import, tariff and peak demand.
--
--   `ottoq_twin_snapshot` defends itself with a sim-time window instead of a run
--   id. Every demo run starts at 08:00 CST, so the windows overlap and foreign
--   rows outnumber a run's own rows better than 2:1 inside its own window, with
--   no run tiebreak on `ORDER BY timestamp DESC LIMIT 1`.
--
--   This is 0020's failure exactly: one key space shared across runs, resolved
--   silently in favour of the wrong run.
--
-- ══ WHY `ON DELETE NO ACTION` AND NOT `CASCADE` ══
--
--   CASCADE would make every one of these tables disappear the instant a run row
--   is deleted — silently, with no receipt, across 44 tables at once. That is a
--   worse bug than the one being fixed, and this project has already been one
--   command away from it: `ottoq_stall_bookings.stall_id` is ON DELETE CASCADE
--   and 13 booking rows sat one statement from being erased with no trace.
--
--   NO ACTION does the opposite. A run row REFUSES to be deleted while its rows
--   still exist. Deletion stops being a side effect and becomes a deliberate,
--   ordered act with a row count. The purge is rewritten to do exactly that:
--   clear children first, from a registry that cannot miss a table, then delete
--   the parent — and abort loudly if any child sweep fails, instead of walking
--   into the parent delete and orphaning what it could not clear.
--
--   `vehicles.owning_sim_run_id` is the ONE exception, and gets ON DELETE SET
--   NULL. A vehicle row is legitimately permanent — only the stamp is not. 116
--   vehicles carry a stamp pointing at 7 dead runs. Deleting those rows would
--   delete the fleet; the stamp is what must go, not the vehicle.
--
-- ══ NOTHING IS DESTROYED. EVERYTHING IS CLASSIFIED FIRST. ══
--
--   Three classes, recorded permanently in `ottoq_run_scope_registry`:
--
--     engine   44 tables whose rows must die with their run. FK, NO ACTION.
--              Existing orphans are COPIED ROW-FOR-ROW into
--              `p0022_orphan_quarantine` (whole row as jsonb) and only then
--              deleted. Reversible; nothing is lost.
--     stamp     1 column — `vehicles.owning_sim_run_id`. FK, SET NULL. The 116
--              stale (vehicle, run) pairs are quarantined before the stamp is
--              cleared. No vehicle row is touched.
--     evidence  everything else — 144 scratch/proof tables, `ottoq_run_archives`,
--              `ottoq_schema_snapshots`, and the purge's own keep-patterns.
--              These EXIST IN ORDER TO OUTLIVE THEIR RUN. Giving them an FK
--              would be the actual mistake. They get NO constraint, are NEVER
--              purged, and are NOT touched by this migration. `p0016_*`,
--              `p0017_*`, `p0018_*`, `p0019_*`, `cert0020_*` are all in here.
--
-- ══ TWO THINGS THIS MIGRATION DELIBERATELY DOES NOT DO ══
--
--   1. `ottoq_events` keeps its 2 orphans. House rule 3 is "never touch
--      ottoq_events" — it is the append-only flight recorder. Its FK is added
--      NOT VALID: PostgreSQL still enforces it on every future insert and on
--      every parent delete, so no NEW orphan can be created, but the two
--      existing rows are left as history rather than rewritten. Declared, not
--      hidden.
--
--   2. 111,818 rows carry a NULL run id (108,026 of them in `ottoq_events`).
--      That is a SECOND, SEPARATE hole — `WHERE sim_run_id IN (...)` is never
--      true for NULL, so the purge can never reach them, which is a capacity
--      risk in a table that once ate 9.1 GB of 11 GB. An FK does not fix it
--      (FKs permit NULL) and mass-deleting 108k event rows on a hunch is exactly
--      the kind of unearned action this migration exists to stop. It is recorded
--      in the registry and reported by the drift guard. It is NOT actioned here.
--
-- ══ ROLLBACK ══
--   Single transaction. Any assertion failure rolls back every part of it.
--   After COMMIT: the constraints are named `fk_%_sim_run` / `fk_vehicles_owning_sim_run`
--   and can be dropped; every quarantined row can be reinserted from
--   `p0022_orphan_quarantine.row_json`; the three replaced routines have their
--   pre-images in `ottoq_schema_snapshots` under label '0022_pre'.
-- ============================================================================

BEGIN;

SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '30s';

-- ---------------------------------------------------------------------------
-- §0  ARM RETENTION + SNAPSHOT EVERY ROUTINE THIS FILE REPLACES (house rule 1)
-- ---------------------------------------------------------------------------
-- Transaction-local. Without it the append-only guards refuse the quarantine
-- deletes. It evaporates at COMMIT.
SELECT set_config('ottoq.retention', 'on', true);

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0022_pre', 'function', 'public', p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('ottoq_purge_prior_runs','ottoq_build_decision_frame','ottoq_twin_snapshot');

-- ---------------------------------------------------------------------------
-- §1  THE REGISTRY — the classification, made permanent and machine-readable
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_run_scope_registry (
  table_schema  text    NOT NULL,
  table_name    text    NOT NULL,
  column_name   text    NOT NULL,
  class         text    NOT NULL CHECK (class IN ('engine','stamp','evidence','run_ledger')),
  note          text,
  registered_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (table_schema, table_name, column_name)
);

COMMENT ON TABLE public.ottoq_run_scope_registry IS
'Every column in the database that carries a simulation run id, and what it means. '
'engine = must die with its run (FK, ON DELETE NO ACTION, purged children-first). '
'stamp = the row is permanent but the run pointer is not (FK, ON DELETE SET NULL). '
'evidence = deliberately outlives its run; NO FK and NEVER purged. '
'run_ledger = the run table itself and its permanent per-run records. '
'ottoq_purge_prior_runs is driven by this table, so a new run-scoped table that is '
'not registered here is caught by ottoq_check_run_scope_registry() instead of '
'silently becoming the next orphan factory.';

-- (1a) ENGINE — named explicitly, because the list is the reviewable artifact.
--      These are exactly the tables the old purge was *supposed* to clear, plus
--      the four it could never see because they are not named `ottoq*`.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
SELECT 'public', t, 'sim_run_id', 'engine', 'run-scoped working data; must not outlive its run'
FROM (VALUES
  ('ottoq_visit_needs'),('ottoq_vehicle_commands'),('ottoq_tick_reservations'),
  ('ottoq_grid_snapshots'),('ottoq_weather_snapshots'),('ottoq_external_proposals'),
  ('ottoq_energy_commands'),('ottoq_cuopt_fire_log'),('ottoq_events'),('ottoq_dr_calls'),
  ('ottoq_solar_output'),('ottoq_decisions'),('ottoq_comms_messages'),
  ('ottoq_variability_cards'),('ottoq_bay_binding_witness'),('ottoq_ocpp_messages'),
  ('ottoq_telemetry_packets'),('ottoq_itinerary_legs'),('ottoq_stall_bookings'),
  ('ottoq_event_state_anchor'),('ottoq_vehicle_dispatches'),('ottoq_vehicle_itineraries'),
  ('ottoq_oem_webhook_log'),('ottoq_deploy_log'),('ottoq_vehicle_wear'),
  ('ottoq_tick_clock_log'),('ottoq_wear_tick_status'),('ottoq_cuopt_deferrals'),
  ('ottoq_decision_snapshots'),('ottoq_rider_cleaning_flags'),('ottoq_variability_profiles'),
  ('ottoq_ops_approvals'),('ottoq_feed_activations'),('ottoq_tick_invariance_arms'),
  ('ottoq_cil_adoptions'),('ottoq_ab_runs'),('ottoq_vehicle_incidents'),
  ('ottoq_energy_plan'),('ottoq_t4_coverage_samples'),('ottoq_wave_plan'),
  -- the four the name pattern `LIKE 'ottoq%'` could never reach:
  ('site_energy_snapshots'),('cuopt_invocation_log'),('ocpp_sessions'),('space_conflict_ledger')
) AS v(t)
ON CONFLICT DO NOTHING;

-- (1b) STAMP — the vehicle row is permanent; the run pointer on it is not.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','vehicles','owning_sim_run_id','stamp',
        'the fleet row is permanent; only the run stamp may dangle. FK is ON DELETE SET NULL')
ON CONFLICT DO NOTHING;

-- (1c) RUN LEDGER — the parent and the permanent per-run records.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','ottoq_sim_runs','sim_run_id','run_ledger','the run table itself'),
       ('public','ottoq_run_archives','sim_run_id','run_ledger',
        'the permanent per-run record; its whole job is to outlive the run')
ON CONFLICT DO NOTHING;

-- (1d) EVIDENCE — everything else that carries a run id, swept from the
--      catalogue. These outlive their runs BY DESIGN. No FK, never purged.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
SELECT c.table_schema, c.table_name, c.column_name, 'evidence',
       'certification / scratch evidence: deliberately outlives its run'
  FROM information_schema.columns c
  JOIN pg_class rc  ON rc.relname = c.table_name
  JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
 WHERE rc.relkind = 'r'
   AND c.table_schema IN ('public','proof_0015')
   AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- §2  QUARANTINE — copy every orphan out whole, THEN delete it. Never destroy.
-- ---------------------------------------------------------------------------
-- Deliberately NOT `ottoq`-prefixed, so starting a run can never purge it.
CREATE TABLE IF NOT EXISTS public.p0022_orphan_quarantine (
  q_id        bigserial PRIMARY KEY,
  quarantined_at timestamptz NOT NULL DEFAULT now(),
  src_table   text  NOT NULL,
  src_column  text  NOT NULL,
  dead_run_id uuid  NOT NULL,
  row_json    jsonb NOT NULL
);

COMMENT ON TABLE public.p0022_orphan_quarantine IS
'Whole-row jsonb copies of every orphaned row removed by migration 0022, taken '
'BEFORE the delete. Reversible: each row can be reinserted into src_table from '
'row_json. Not ottoq-prefixed so a run start cannot purge it.';

DO $quarantine$
DECLARE
  r record; n_copied bigint; n_deleted bigint;
  v_tot_copied bigint := 0; v_tot_deleted bigint := 0;
BEGIN
  FOR r IN
    SELECT table_name AS t, column_name AS c
      FROM public.ottoq_run_scope_registry
     WHERE class = 'engine'
       AND table_name <> 'ottoq_events'   -- house rule 3: history is not rewritten
     ORDER BY table_name
  LOOP
    EXECUTE format(
      'INSERT INTO public.p0022_orphan_quarantine (src_table, src_column, dead_run_id, row_json)
         SELECT %1$L, %2$L, o.%3$I, to_jsonb(o) FROM public.%4$I o
          WHERE o.%3$I IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = o.%3$I)',
      r.t, r.c, r.c, r.t);
    GET DIAGNOSTICS n_copied = ROW_COUNT;

    IF n_copied > 0 THEN
      EXECUTE format(
        'DELETE FROM public.%1$I o
          WHERE o.%2$I IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = o.%2$I)',
        r.t, r.c);
      GET DIAGNOSTICS n_deleted = ROW_COUNT;

      -- copied and deleted must agree exactly, or we are losing rows unrecorded
      IF n_deleted <> n_copied THEN
        RAISE EXCEPTION '0022 quarantine mismatch on %: copied %, deleted %',
          r.t, n_copied, n_deleted;
      END IF;
      v_tot_copied  := v_tot_copied  + n_copied;
      v_tot_deleted := v_tot_deleted + n_deleted;
      RAISE NOTICE '0022 quarantined % orphan row(s) from %', n_deleted, r.t;
    END IF;
  END LOOP;

  -- the STAMP class: quarantine the (vehicle, dead run) pair, then clear the
  -- stamp only. The vehicle row itself is never touched.
  --
  -- `trg_ottoq_vehicles_state_change` is AFTER INSERT OR UPDATE with no WHEN
  -- clause, and its 0015 skip-list covers only updated_at / current_soc_updated_at
  -- / last_state_change. Clearing `owning_sim_run_id` is therefore a "real" diff
  -- to it, and it would write 116 `vehicle.state_changed` events — each asserting
  -- a state change in which NO STATE CHANGED. Repairing a dangling pointer is not
  -- fleet motion, and logging it as motion is the exact failure this file exists
  -- to close, so the trigger is suspended for this one statement and restored
  -- immediately. Re-enablement is asserted in §7 (A9).
  --
  -- The other four are safe and were read, not assumed: `log_vehicle_state_change`
  -- and `sync_stall_occupancy` both no-op unless current_state / current_stall_id
  -- move; `ottoq_trg_log_deploy` has a WHEN clause on current_state. Only
  -- `update_timestamp` acts, bumping `updated_at` on the 116 repaired rows.
  ALTER TABLE public.vehicles DISABLE TRIGGER trg_ottoq_vehicles_state_change;

  INSERT INTO public.p0022_orphan_quarantine (src_table, src_column, dead_run_id, row_json)
  SELECT 'vehicles', 'owning_sim_run_id', v.owning_sim_run_id,
         jsonb_build_object('id', v.id, 'owning_sim_run_id', v.owning_sim_run_id,
                            'current_state', v.current_state)
    FROM public.vehicles v
   WHERE v.owning_sim_run_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = v.owning_sim_run_id);
  GET DIAGNOSTICS n_copied = ROW_COUNT;

  UPDATE public.vehicles v SET owning_sim_run_id = NULL
   WHERE v.owning_sim_run_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = v.owning_sim_run_id);
  GET DIAGNOSTICS n_deleted = ROW_COUNT;

  ALTER TABLE public.vehicles ENABLE TRIGGER trg_ottoq_vehicles_state_change;

  IF n_deleted <> n_copied THEN
    RAISE EXCEPTION '0022 stamp quarantine mismatch: copied %, cleared %', n_copied, n_deleted;
  END IF;
  RAISE NOTICE '0022 cleared % stale vehicle run-stamp(s); 0 vehicle rows deleted', n_deleted;

  RAISE NOTICE '0022 quarantine total: % row(s) copied, % row(s) removed',
    v_tot_copied + n_copied, v_tot_deleted + n_deleted;
END
$quarantine$;

-- ---------------------------------------------------------------------------
-- §3  THE CONSTRAINTS — the thing that has never existed
-- ---------------------------------------------------------------------------
-- Two tables carry ~2k rows with no leading index on sim_run_id. Without one,
-- every parent delete re-scans them per deleted run row. Cheap to fix now.
CREATE INDEX IF NOT EXISTS idx_ocpp_sessions_sim_run
  ON public.ocpp_sessions (sim_run_id);
CREATE INDEX IF NOT EXISTS idx_ottoq_event_state_anchor_sim_run
  ON public.ottoq_event_state_anchor (sim_run_id);

DO $fk$
DECLARE r record; v_name text; v_made int := 0;
BEGIN
  FOR r IN
    SELECT table_name AS t, column_name AS c
      FROM public.ottoq_run_scope_registry
     WHERE class = 'engine' ORDER BY table_name
  LOOP
    v_name := 'fk_' || r.t || '_sim_run';
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = v_name AND conrelid = ('public.'||r.t)::regclass) THEN
      IF r.t = 'ottoq_events' THEN
        -- NOT VALID: enforced on every future write and on every parent delete,
        -- but the 2 historical orphans are left in place. See header.
        EXECUTE format(
          'ALTER TABLE public.%1$I ADD CONSTRAINT %2$I FOREIGN KEY (%3$I)
             REFERENCES public.ottoq_sim_runs (sim_run_id) ON DELETE NO ACTION NOT VALID',
          r.t, v_name, r.c);
      ELSE
        EXECUTE format(
          'ALTER TABLE public.%1$I ADD CONSTRAINT %2$I FOREIGN KEY (%3$I)
             REFERENCES public.ottoq_sim_runs (sim_run_id) ON DELETE NO ACTION',
          r.t, v_name, r.c);
      END IF;
      v_made := v_made + 1;
    END IF;
  END LOOP;

  -- the one SET NULL, and the only one
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'fk_vehicles_owning_sim_run'
                    AND conrelid = 'public.vehicles'::regclass) THEN
    ALTER TABLE public.vehicles
      ADD CONSTRAINT fk_vehicles_owning_sim_run FOREIGN KEY (owning_sim_run_id)
      REFERENCES public.ottoq_sim_runs (sim_run_id) ON DELETE SET NULL;
    v_made := v_made + 1;
  END IF;

  RAISE NOTICE '0022 added % foreign key(s) to ottoq_sim_runs', v_made;
END
$fk$;

-- ---------------------------------------------------------------------------
-- §4  THE DRIFT GUARD — a new run-scoped table cannot hide
-- ---------------------------------------------------------------------------
-- `severity` matters. 'block' = a corruption risk that must stop a purge:
-- a registered engine table with no FK, or an FK that has become CASCADE.
-- Neither can appear by accident. 'warn' = an unregistered run-scoped column,
-- which is what EVERY new certification/scratch table looks like on the day it
-- is created. Blocking on those would mean the next `cert0023_*` table someone
-- creates stops the purge — and the purge is what run start calls, so that
-- would take the START engine down. Warnings ride out in the purge receipt
-- where a human sees them; they do not stop the engine.
CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
RETURNS TABLE (table_schema text, table_name text, column_name text, problem text, severity text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
  -- (a) a run-scoped column that nobody has classified
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','proof_0015')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name)
  UNION ALL
  -- (b) an engine/stamp table that lost its foreign key, or went missing.
  --     `to_regclass` (not a ::regclass cast) is deliberate: the cast RAISES on a
  --     dropped table, and since ottoq_purge_prior_runs calls this guard, one
  --     dropped scratch table would have made every run start fail. Evidence
  --     tables are scratch and do get dropped; this must stay total.
  SELECT g.table_schema, g.table_name, g.column_name,
         CASE WHEN to_regclass(g.table_schema||'.'||g.table_name) IS NULL
              THEN 'registered engine/stamp table no longer exists'
              ELSE 'engine/stamp table has no FK to ottoq_sim_runs' END,
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.contype = 'f'
          AND k.conrelid = to_regclass(g.table_schema||'.'||g.table_name)
          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
  UNION ALL
  -- (c) any FK to the run table that has become CASCADE — history one command
  --     from silent erasure. Read from the catalogue directly so it also catches
  --     a CASCADE on a table nobody registered.
  SELECT n.nspname::text, c.relname::text, 'sim_run_id'::text,
         'FK to ottoq_sim_runs is ON DELETE CASCADE — history can be silently erased',
         'block'
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE k.contype = 'f'
     AND k.confrelid = 'public.ottoq_sim_runs'::regclass
     AND k.confdeltype = 'c';
$fn$;

COMMENT ON FUNCTION public.ottoq_check_run_scope_registry() IS
'Returns one row per run-scoping defect: an unclassified run-scoped column, an '
'engine/stamp table missing its FK, or an FK that has become ON DELETE CASCADE. '
'Zero rows is the healthy state. Note this guard is about ORPHANS, not NULLs: '
'111,818 rows carry a NULL run id (108,026 in ottoq_events) and remain unreachable '
'by the purge. That is a separate, declared hole — see migration 0022 header.';

-- ---------------------------------------------------------------------------
-- §5  THE PURGE — children first, from the registry, and never silently
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $function$
DECLARE
  r record; v_n bigint; v_total bigint := 0; v_runs int;
  v_doomed uuid[]; v_block int; v_engine int; v_cleared jsonb := '{}'::jsonb;
  v_warn jsonb;
BEGIN
  -- (1) ARM. Without this the append-only guards refuse every DELETE below.
  --     Transaction-local: it evaporates at COMMIT.
  PERFORM set_config('ottoq.retention', 'on', true);

  -- (2) REFUSE TO RUN BLIND. The old version enumerated tables with
  --     `table_name LIKE 'ottoq%'`, which is why site_energy_snapshots
  --     accumulated 27,163 orphans it could never see. If anything carrying a
  --     run id is unclassified, stop — do not delete a parent we cannot fully
  --     clear.
  SELECT count(*) FILTER (WHERE severity = 'block'),
         COALESCE(jsonb_agg(table_name || '.' || column_name)
                  FILTER (WHERE severity = 'warn'), '[]'::jsonb)
    INTO v_block, v_warn
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s). Run SELECT * FROM ottoq_check_run_scope_registry();', v_block;
  END IF;

  SELECT count(*) INTO v_engine FROM public.ottoq_run_scope_registry WHERE class='engine';
  IF v_engine = 0 THEN
    RAISE EXCEPTION 'purge refused: run-scope registry holds no engine tables';
  END IF;

  -- (3) Decide what is going ONCE, up front, as a value. The old version scoped
  --     each child DELETE by a subquery on the parent row it was about to
  --     delete, which is why an orphan could never be reached.
  SELECT array_agg(sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs
   WHERE sim_run_id <> p_keep_run
     AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'kept', p_keep_run, 'rows_purged', 0,
      'prior_runs_deleted', 0, 'cleared_by_table', v_cleared,
      'unregistered_run_scoped', v_warn, 'retention_armed', true);
  END IF;

  -- (4) CHILDREN FIRST, every engine table, NO exception swallowed. A failure
  --     here must abort the whole purge: continuing to the parent delete is
  --     precisely what manufactured the orphans.
  FOR r IN
    SELECT table_name AS t, column_name AS c
      FROM public.ottoq_run_scope_registry
     WHERE class = 'engine' ORDER BY table_name
  LOOP
    EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
      USING v_doomed;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
    IF v_n > 0 THEN
      v_cleared := v_cleared || jsonb_build_object(r.t, v_n);
    END IF;
  END LOOP;

  -- (5) The parent. `vehicles.owning_sim_run_id` is ON DELETE SET NULL, so the
  --     fleet's stamps clear themselves here without a single vehicle row being
  --     deleted. Every other FK is NO ACTION: if step (4) missed anything this
  --     statement RAISES instead of orphaning it.
  DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed);
  GET DIAGNOSTICS v_runs = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true, 'kept', p_keep_run, 'rows_purged', v_total,
    'prior_runs_deleted', v_runs, 'cleared_by_table', v_cleared,
    'evidence_preserved', (SELECT count(*) FROM public.ottoq_run_scope_registry WHERE class='evidence'),
    'unregistered_run_scoped', v_warn, 'retention_armed', true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- §6  THE READ LEAK — a run-scoped read must not resolve to another run
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_current_sim_run_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
  SELECT sim_run_id FROM public.ottoq_sim_runs
   ORDER BY (status = 'running') DESC,
            COALESCE(started_at, '-infinity'::timestamptz) DESC,
            sim_run_seq DESC
   LIMIT 1;
$fn$;

COMMENT ON FUNCTION public.ottoq_current_sim_run_id() IS
'The run a run-blind reader should be scoped to: the running run if there is one, '
'else the most recently started. Total — returns NULL only when no run exists, in '
'which case a scoped read correctly returns nothing rather than a dead run''s row.';

-- The two leaking readers are patched surgically rather than retyped: the exact
-- pre-image is md5-checked first, so if either body is not what this migration
-- was written against, nothing is rewritten and the transaction aborts.
DO $patch$
DECLARE
  v_def text; v_new text; v_from text; v_to text; v_md5 text;
BEGIN
  ----------------------------------------------------------------- frame ------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_build_decision_frame';
  IF v_md5 <> 'd5afd7dab51cc807f3a393947faf490e' THEN
    RAISE EXCEPTION '0022 refused: ottoq_build_decision_frame body is not the audited pre-image (md5 %)', v_md5;
  END IF;
  v_from := 'FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id';
  v_to   := v_from || E'\n        AND se.sim_run_id = public.ottoq_current_sim_run_id()';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0022 refused: expected exactly one energy read in ottoq_build_decision_frame';
  END IF;
  v_new := replace(v_def, v_from, v_to);
  EXECUTE v_new;
  RAISE NOTICE '0022 run-scoped the energy read in ottoq_build_decision_frame';

  -------------------------------------------------------------- snapshot ------
  SELECT pg_get_functiondef(oid), md5(pg_get_functiondef(oid)) INTO v_def, v_md5
    FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='ottoq_twin_snapshot';
  IF v_md5 <> 'da7731faf2448a41334b6f732e2ab44a' THEN
    RAISE EXCEPTION '0022 refused: ottoq_twin_snapshot body is not the audited pre-image (md5 %)', v_md5;
  END IF;
  -- v_run is declared `ottoq_sim_runs%ROWTYPE`, so v_run.sim_run_id is in scope.
  -- The sim-time window stays; it is simply no longer the only discriminator.
  v_from := 'FROM site_energy_snapshots se WHERE se.depot_id = v_depot';
  v_to   := v_from || E'\n        AND se.sim_run_id = v_run.sim_run_id';
  IF (length(v_def) - length(replace(v_def, v_from, ''))) / length(v_from) <> 1 THEN
    RAISE EXCEPTION '0022 refused: expected exactly one energy read in ottoq_twin_snapshot';
  END IF;
  v_new := replace(v_def, v_from, v_to);
  EXECUTE v_new;
  RAISE NOTICE '0022 run-scoped the energy read in ottoq_twin_snapshot';
END
$patch$;

-- ---------------------------------------------------------------------------
-- §7  ASSERTIONS — every claim in the header, proved before COMMIT
-- ---------------------------------------------------------------------------
DO $assert$
DECLARE
  n int; n2 int; v_run uuid; v_veh uuid; v_ok boolean; v_state text; v_sqlstate text;
BEGIN
  ---- A1  the registry is total ---------------------------------------------
  -- Both severities must be zero right now: every run-scoped column in the
  -- database has just been classified, so there is nothing to warn about either.
  SELECT count(*) FILTER (WHERE severity='block'), count(*) FILTER (WHERE severity='warn')
    INTO n, n2 FROM public.ottoq_check_run_scope_registry();
  IF n <> 0 THEN RAISE EXCEPTION 'A1 FAILED: % blocking run-scope defect(s)', n; END IF;
  IF n2 <> 0 THEN RAISE EXCEPTION 'A1 FAILED: % run-scoped column(s) left unclassified', n2; END IF;
  SELECT count(*) INTO n FROM public.ottoq_run_scope_registry;
  RAISE NOTICE 'A1 PASSED: registry covers % run-scoped column(s); 0 blocking, 0 unclassified', n;

  ---- A2  every engine + stamp column now has an FK -------------------------
  SELECT count(*) INTO n FROM public.ottoq_run_scope_registry WHERE class IN ('engine','stamp');
  SELECT count(*) INTO n2 FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass;
  IF n2 < n THEN RAISE EXCEPTION 'A2 FAILED: % constrained column(s) but only % FK(s)', n, n2; END IF;
  RAISE NOTICE 'A2 PASSED: % FK(s) now reference ottoq_sim_runs (was 0)', n2;

  ---- A3  NOT ONE of them is CASCADE, and the stamp is SET NULL -------------
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass AND confdeltype='c';
  IF n <> 0 THEN RAISE EXCEPTION 'A3 FAILED: % FK(s) to ottoq_sim_runs are ON DELETE CASCADE', n; END IF;
  SELECT confdeltype='n' INTO v_ok FROM pg_constraint WHERE conname='fk_vehicles_owning_sim_run';
  IF NOT COALESCE(v_ok,false) THEN RAISE EXCEPTION 'A3 FAILED: vehicles stamp FK is not ON DELETE SET NULL'; END IF;
  SELECT count(*) INTO n FROM pg_constraint
   WHERE contype='f' AND confrelid='public.ottoq_sim_runs'::regclass AND confdeltype='a';
  RAISE NOTICE 'A3 PASSED: 0 CASCADE; % NO ACTION; vehicles stamp = SET NULL', n;

  ---- A4  the orphans are gone from engine tables (ottoq_events declared) ---
  SELECT count(*) INTO n FROM public.ottoq_visit_needs v
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = v.sim_run_id);
  IF n <> 0 THEN RAISE EXCEPTION 'A4 FAILED: ottoq_visit_needs still holds % orphan(s)', n; END IF;
  SELECT count(*) INTO n FROM public.site_energy_snapshots e
   WHERE e.sim_run_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = e.sim_run_id);
  IF n <> 0 THEN RAISE EXCEPTION 'A4 FAILED: site_energy_snapshots still holds % orphan(s)', n; END IF;
  SELECT count(*) INTO n FROM public.vehicles v
   WHERE v.owning_sim_run_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs s WHERE s.sim_run_id = v.owning_sim_run_id);
  IF n <> 0 THEN RAISE EXCEPTION 'A4 FAILED: % vehicle(s) still carry a dead run stamp', n; END IF;
  SELECT count(*) INTO n FROM public.p0022_orphan_quarantine;
  RAISE NOTICE 'A4 PASSED: engine orphans cleared; % row(s) preserved in p0022_orphan_quarantine', n;

  ---- A5  NO ORPHAN CAN BE CREATED FROM NOW ON -----------------------------
  -- An UPDATE of an existing row, not an INSERT: it isolates the run pointer
  -- from every NOT NULL/default on the table, so a pass can only mean the FK
  -- fired. `ottoq_grid_snapshots` carries no triggers, so nothing else can
  -- raise and be mistaken for the constraint working.
  IF EXISTS (SELECT 1 FROM public.ottoq_grid_snapshots) THEN
    BEGIN
      UPDATE public.ottoq_grid_snapshots
         SET sim_run_id = '00000000-0000-0000-0000-0000000000ff'::uuid
       WHERE ctid = (SELECT ctid FROM public.ottoq_grid_snapshots LIMIT 1);
      RAISE EXCEPTION 'A5 FAILED: a row was pointed at a non-existent run and accepted';
    EXCEPTION
      WHEN foreign_key_violation THEN
        RAISE NOTICE 'A5 PASSED: pointing a row at a non-existent run is rejected (23503)';
    END;
  ELSE
    RAISE EXCEPTION 'A5 FAILED: no ottoq_grid_snapshots row available to probe';
  END IF;

  ---- A6  A RUN CANNOT BE DELETED OUT FROM UNDER ITS ROWS ------------------
  -- This is the CASCADE test done the honest way: not "is the catalogue flag
  -- right" but "does deleting a run that still has rows actually refuse".
  SELECT s.sim_run_id INTO v_run FROM public.ottoq_sim_runs s
   WHERE EXISTS (SELECT 1 FROM public.ottoq_decisions d WHERE d.sim_run_id = s.sim_run_id)
   LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE 'A6 SKIPPED: no run currently has ottoq_decisions rows';
  ELSE
    SELECT count(*) INTO n2 FROM public.ottoq_decisions WHERE sim_run_id = v_run;
    BEGIN
      DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
      RAISE EXCEPTION 'A6 FAILED: run % was deleted while % decision row(s) still referenced it', v_run, n2;
    EXCEPTION
      WHEN foreign_key_violation THEN
        RAISE NOTICE 'A6 PASSED: deleting run % refused while % row(s) reference it (23503) — NO ACTION, not CASCADE, so history cannot be silently erased', v_run, n2;
    END;
    -- and prove the refusal left the rows alone: had this been CASCADE, they
    -- would already be gone rather than the delete having been refused.
    SELECT count(*) INTO n FROM public.ottoq_decisions WHERE sim_run_id = v_run;
    IF n <> n2 THEN
      RAISE EXCEPTION 'A6 FAILED: % of % referencing row(s) disappeared during the refused delete', n2 - n, n2;
    END IF;
    RAISE NOTICE 'A6 PASSED: all % referencing row(s) survived the refused delete intact', n;
  END IF;

  ---- A7  a run-scoped read cannot return another run's rows ---------------
  -- Behavioural, not structural: call the real function and check WHICH ROW it
  -- landed on. Before this migration the newest row for both depots belonged to
  -- a dead run, and the frame served it.
  SELECT count(*) INTO n
    FROM (SELECT DISTINCT depot_id AS d FROM public.site_energy_snapshots) x
   WHERE (public.ottoq_build_decision_frame(x.d) -> 'energy' ->> 'at')::timestamptz
         IS DISTINCT FROM
         (SELECT max(se.timestamp) FROM public.site_energy_snapshots se
           WHERE se.depot_id = x.d
             AND se.sim_run_id = public.ottoq_current_sim_run_id());
  IF n <> 0 THEN
    RAISE EXCEPTION 'A7 FAILED: % depot(s) resolve the energy read to a row outside the current run', n;
  END IF;
  RAISE NOTICE 'A7 PASSED: for every depot the decision frame lands on the current run''s newest energy row, or on nothing';

  ---- A8  the purge is registry-driven and no longer enumerates by name ----
  SELECT prosrc INTO v_state FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='ottoq_purge_prior_runs';
  IF v_state NOT LIKE '%ottoq_run_scope_registry%' THEN
    RAISE EXCEPTION 'A8 FAILED: purge is not driven by the registry';
  END IF;
  IF v_state LIKE '%information_schema.columns%' THEN
    RAISE EXCEPTION 'A8 FAILED: purge still enumerates tables from the catalogue by name pattern';
  END IF;
  RAISE NOTICE 'A8 PASSED: purge clears children from the registry, then the parent';

  ---- A9  the suspended vehicles trigger was restored ----------------------
  SELECT t.tgenabled = 'O' INTO v_ok FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relname = 'vehicles' AND t.tgname = 'trg_ottoq_vehicles_state_change';
  IF NOT COALESCE(v_ok,false) THEN
    RAISE EXCEPTION 'A9 FAILED: trg_ottoq_vehicles_state_change was not re-enabled';
  END IF;
  -- and the fleet is intact: the stamp repair must not have cost a vehicle row
  SELECT count(*) INTO n FROM public.vehicles;
  IF n <> 220 THEN
    RAISE EXCEPTION 'A9 FAILED: vehicle count is %, expected the pre-migration 220', n;
  END IF;
  RAISE NOTICE 'A9 PASSED: trigger restored, all 220 vehicle rows intact';

  RAISE NOTICE '0022 assertions A1-A9 PASSED';
END
$assert$;

COMMIT;
