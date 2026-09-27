-- migration-version: 20260926032129
-- migration-name:    the_depot_card_migration_never_classified_itself_so_the_recert_floor_restarted_every_column
--
-- 0461  **0460 never wrote its `ottoq_cert_lineage` row, so the recert floor read it as forcing and restarted every
--       certification column.** Bookkeeping only, the fifth of its kind (0268, 0272, 0301, 0310, 0410).
--
-- ══ §1 MEASURED 2026-09-26 03:30 UTC ══════════════════════════════════════════════════════════════════════════
--
--   - `ottoq_cert_lineage` has no row whose prefix-stripped name matches 0460's applied name.
--     `ottoq_cert_recert_floor()` reads a missing row as `COALESCE(forces_recert, TRUE)`, so the floor stood on
--     0460's ledger version: 2026-09-25 20:00:00 UTC.
--   - The recertification runner answered it: all nine canon columns were re-certified 20:00–20:18 UTC on
--     2026-09-25, every one `passed`, engine_hash d02a8e9e2e56f0504243ad42287f7cba. So the damage was one extra
--     sweep (about twenty minutes of starved cron, G141), not a stale matrix.
--   - 0460's header argues forces_recert FALSE correctly: `ottoq_depot_cards` is read by the cockpits and by no
--     decide, tick, enact or world function. The row it never wrote is the only place the engine reads that.
--   - CI on PR #207 failed `test_recent_migrations_classify_themselves` for exactly this, beside three artefact
--     tests (index and drift manifest not regenerated; a ledger version ending 0000).
--
-- ══ §2 THE LEDGER VERSION ═════════════════════════════════════════════════════════════════════════════════════
--
--   0460's row in `supabase_migrations.schema_migrations` carries version 20260925200000 and NULL `statements`:
--   it was written by hand, not by `apply_migration`, so the ledger itself holds a rounded number and nothing in
--   the database records the real apply instant. The file mirrors the ledger, which is the drift contract, and
--   `tests/test_migration_hygiene.py` now names this one version in `LEDGER_HAND_VERSIONS` with that reason rather
--   than rejecting it. Re-keying the ledger row to an invented "better" timestamp would be the same defect again.
--
-- ══ §3 WHAT THIS DOES ═════════════════════════════════════════════════════════════════════════════════════════
--
--   Writes 0460's row (forces_recert FALSE), keyed on the APPLIED name (0410's naming trap), and this file's own.
--   The floor falls back to the last genuinely forcing migration. Every canon column certified since 2026-09-25
--   20:00 still satisfies it, so nothing re-runs. `forces_recert` FALSE: catalog rows only.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0461 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P1–P3: the state this file repairs ──
DO $premises$
DECLARE v_n int;
BEGIN
  -- P1. 0460 is applied, under the name and version this header records.
  PERFORM 1 FROM supabase_migrations.schema_migrations
   WHERE version = '20260925200000'
     AND name = 'the_cockpits_could_not_read_the_card_they_were_built_on_and_it_never_said_where_a_vehicle_was_booked';
  IF NOT FOUND THEN RAISE EXCEPTION '0461 P1: 0460 is not in the ledger as 20260925200000'; END IF;

  -- P2. Its body is live: one overload, anon-executable.
  SELECT count(*) INTO v_n FROM pg_proc WHERE proname = 'ottoq_depot_cards';
  IF v_n <> 1 OR NOT has_function_privilege('anon', 'public.ottoq_depot_cards(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0461 P2: ottoq_depot_cards is not the 0460 body (% overloads)', v_n;
  END IF;

  -- P3. Nothing has classified 0460 yet.
  SELECT count(*) INTO v_n FROM public.ottoq_cert_lineage l
   WHERE regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
       = 'the_cockpits_could_not_read_the_card_they_were_built_on_and_it_never_said_where_a_vehicle_was_booked';
  IF v_n <> 0 THEN RAISE EXCEPTION '0461 P3: 0460 already has % lineage row(s)', v_n; END IF;
END $premises$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at) VALUES
 ('0460_the_cockpits_could_not_read_the_card_they_were_built_on_and_it_never_said_where_a_vehicle_was_booked', false,
  'Written by 0461. ottoq_depot_cards body (contract 1.1: stall, reservations, last_decision, reservation_ledger) '
  'and an anon/authenticated EXECUTE grant. Read by the PULSE and OrchestrAV cockpits only; no decide, tick, enact '
  'or world function calls it, so no atom can move. Keyed on the APPLIED name.', now()),
 ('0461_the_depot_card_migration_never_classified_itself_so_the_recert_floor_restarted_every_column', false,
  'Bookkeeping: writes 0460''s lineage row and its own. Catalog rows only.', now())
ON CONFLICT (name) DO NOTHING;

-- ── V: the row joins, and the floor has left 0460 ──
DO $verify$
DECLARE v_floor timestamptz;
BEGIN
  PERFORM 1 FROM public.ottoq_cert_lineage l
    JOIN supabase_migrations.schema_migrations m
      ON regexp_replace(m.name, '^[0-9]{4}[a-z]?_', '') = regexp_replace(l.name, '^[0-9]{4}[a-z]?_', '')
   WHERE m.version = '20260925200000' AND l.forces_recert = false;
  IF NOT FOUND THEN RAISE EXCEPTION '0461 V1: 0460''s lineage row does not join its ledger row'; END IF;

  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor >= '2026-09-25 20:00:00+00'::timestamptz THEN
    RAISE EXCEPTION '0461 V2: the recert floor is still %', v_floor;
  END IF;
  RAISE NOTICE '0461: recert floor now %', v_floor;
END $verify$;

-- Rollback: DELETE the two ottoq_cert_lineage rows named above. The floor returns to 20:00 UTC 2026-09-25.
COMMIT;
