-- migration-version: PENDING
-- migration-name:    the_calendar_keeps_the_exclusion_that_binds_and_sheds_the_one_it_subsumes
--
-- 0602  **The stall calendar carries three EXCLUDE constraints on one key, and one of them can never refuse a row the
--       strongest one would not refuse first. It costs a GiST descent on every booking write and 194-203 MB of index. This
--       drops that one and rebuilds the calendar's bloated indexes.** Overnight review 2026-09-30 (G312). NEEDS CHASE'S
--       SIGN-OFF: db/checks/0203 filed this on 2026-09-13 and held it for a deliberate window, because it removes an
--       exclusion constraint from the one table CLAUDE.md protects by name.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_stall_bookings` is the calendar: its EXCLUDE constraint makes double-booking physically impossible (CLAUDE.md
--   Part 1 rule 6, "never remove either side"). It carries three, with one key, EXCLUDE USING gist (sim_run_id WITH =,
--   stall_id WITH =, during WITH &&), differing only in WHERE:
--       no_overlap     state IN (held, active)
--       no_overlap_v2  state IN (held, active, done)              AND booked_at >= 2026-08-02 03:19 UTC
--       no_overlap_v3  state IN (held, active, done, interrupted) AND booked_at >= 2026-08-02 03:19 UTC
--   v2's rows are a subset of v3's (same key, same booked_at bound, {held,active,done} within {held,active,done,
--   interrupted}), so any pair v2 would refuse, v3 refuses. That is logic, not data: no row set makes v2 load-bearing
--   (db/checks/0203 §2). v1 is different, and stays: its one region v3 does not cover, rows booked before the bound, is
--   empty today (0 rows, 2026-09-30) but a back-dated insert could fill it.
--
--   Why now: the research wing's test days are too slow to fit a night (lead 1 of the overnight review; night 1's arm 3,
--   85a5d396, 144 ticks in 1,309.8 s, and the engine's own decision latency per tick rising 5.7x across the day). The
--   calendar is on that path: on 2026-09-30 its indexes held 82,053 pages (641 MB) for 12,215 rows in a 16 MB heap, v2
--   24,858 pages and v3 26,791; v2 has been descended 5,088,982 times and can reject nothing. A plain REINDEX is the only
--   rebuild an exclusion index allows (0203 §1: CONCURRENTLY is refused for exclusion constraints), and it blocks calendar
--   writes while it runs, so it belongs in an apply window between runs, which is where this runs.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) DROP CONSTRAINT ottoq_stall_bookings_no_overlap_v2. v1 and v3 stay, byte for byte (P1 pins both definitions).
--   (b) REINDEX TABLE public.ottoq_stall_bookings: every remaining index rebuilt from the live rows.
--   No function changes. Every reader that names a constraint names v3, in a comment (0203; re-read 2026-09-30).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the three constraints are exactly the three measured (definitions pinned), v2's predicate is
--   the subset described, nothing is booked before the bound, and this has not been applied. The three definitions go to
--   `ottoq_schema_snapshots` as '0602_pre'.
--   V1: v1 and v3 are still there, unchanged, and v2 is gone. V2: executed, not argued: two overlapping 'done' rows for
--   one stall in one run (the case v2 was written for) are refused, by v3, inside a subtransaction that rolls back.
--   V3: the table's indexes are at most a tenth of their size before the rebuild.
--   Executed by tests/test_calendar_exclusion_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no function changes and no row the calendar accepts or refuses
--   changes (V2). A rebuilt index can change which plan a query takes, which matters only to a query whose ORDER BY is not
--   total; the canon's own determinism pairs are the check on that, and applying this in the same window as 0573/0574
--   (which recertify anyway) makes the question moot.
--
-- ROLLBACK: ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap_v2
--             EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
--             WHERE (state = ANY (ARRAY['held','active','done']) AND booked_at >= '2026-08-02 03:19:00+00'::timestamptz);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0602_the_calendar_keeps_the_exclusion_that_binds_and_sheds_the_one_it_subsumes'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0602 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the three constraints measured, the subset, nothing before the bound, not yet applied ──
DO $premises$
DECLARE
  v_defs jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0602_the_calendar_keeps_the_exclusion_that_binds_and_sheds_the_one_it_subsumes') THEN
    RAISE EXCEPTION '0602 P1: already applied';
  END IF;
  SELECT jsonb_object_agg(conname, pg_get_constraintdef(oid)) INTO v_defs
    FROM pg_constraint WHERE conrelid = 'public.ottoq_stall_bookings'::regclass AND contype = 'x';
  IF v_defs IS DISTINCT FROM jsonb_build_object(
       'ottoq_stall_bookings_no_overlap',
       'EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE ((state = ANY (ARRAY[''held''::text, ''active''::text])))',
       'ottoq_stall_bookings_no_overlap_v2',
       'EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE (((state = ANY (ARRAY[''held''::text, ''active''::text, ''done''::text])) AND (booked_at >= ''2026-08-02 03:19:00+00''::timestamp with time zone)))',
       'ottoq_stall_bookings_no_overlap_v3',
       'EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&) WHERE (((state = ANY (ARRAY[''held''::text, ''active''::text, ''done''::text, ''interrupted''::text])) AND (booked_at >= ''2026-08-02 03:19:00+00''::timestamp with time zone)))') THEN
    RAISE EXCEPTION '0602 P1: the calendar''s exclusion constraints are not the three measured on 2026-09-30: %', v_defs;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_stall_bookings WHERE booked_at < '2026-08-02 03:19:00+00') THEN
    RAISE EXCEPTION '0602 P1: rows are booked before the 2026-08-02 bound; re-read db/checks/0203 before shedding anything';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0602_pre', 'constraint', 'public', c.conname, pg_get_constraintdef(c.oid), md5(pg_get_constraintdef(c.oid))
  FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_stall_bookings'::regclass AND c.contype = 'x';

CREATE TEMP TABLE m0602_before ON COMMIT DROP AS
SELECT pg_indexes_size('public.ottoq_stall_bookings'::regclass) AS idx_bytes;

-- ── (a) shed the subsumed one ──
ALTER TABLE public.ottoq_stall_bookings DROP CONSTRAINT ottoq_stall_bookings_no_overlap_v2;

-- ── (b) rebuild the rest ──
REINDEX TABLE public.ottoq_stall_bookings;

-- ── V1: v1 and v3 unchanged, v2 gone ──
DO $v1$
DECLARE
  v_now jsonb;
  v_pre jsonb;
BEGIN
  SELECT jsonb_object_agg(conname, pg_get_constraintdef(oid)) INTO v_now
    FROM pg_constraint WHERE conrelid = 'public.ottoq_stall_bookings'::regclass AND contype = 'x';
  SELECT jsonb_object_agg(object_name, definition) INTO v_pre
    FROM public.ottoq_schema_snapshots
   WHERE label = '0602_pre' AND object_name IN ('ottoq_stall_bookings_no_overlap', 'ottoq_stall_bookings_no_overlap_v3');
  IF v_now IS DISTINCT FROM v_pre THEN
    RAISE EXCEPTION '0602 V1: the calendar now carries % where v1 and v3 were %', v_now, v_pre;
  END IF;
END $v1$;

-- ── V2: two overlapping 'done' rows for one stall in one run are still refused ──
DO $v2$
DECLARE
  v_run uuid;
  v_stall uuid;
  v_veh uuid;
  v_by text;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  SELECT s.id INTO v_stall FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY s.id LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_stall IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0602 V2: no run, stall and vehicle to probe the calendar with';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, v_stall, v_veh, 'staging', tstzrange('2000-01-01 00:00+00', '2000-01-01 01:00+00', '[)'), 'done'),
           (v_run, v_stall, v_veh, 'staging', tstzrange('2000-01-01 00:30+00', '2000-01-01 01:30+00', '[)'), 'done');
    RAISE EXCEPTION 'm0602_admitted';
  EXCEPTION
    WHEN exclusion_violation THEN
      GET STACKED DIAGNOSTICS v_by = CONSTRAINT_NAME;
      IF v_by IS DISTINCT FROM 'ottoq_stall_bookings_no_overlap_v3' THEN
        RAISE EXCEPTION '0602 V2: the overlap was refused by %, not v3', v_by;
      END IF;
    WHEN raise_exception THEN
      RAISE EXCEPTION '0602 V2: the calendar admitted two overlapping done bookings for one stall';
  END;
END $v2$;

-- ── V3: the rebuild took the bloat out ──
DO $v3$
BEGIN
  IF pg_indexes_size('public.ottoq_stall_bookings'::regclass) > (SELECT idx_bytes FROM m0602_before) / 10
     AND (SELECT idx_bytes FROM m0602_before) > 64 * 1024 * 1024 THEN
    RAISE EXCEPTION '0602 V3: the calendar''s indexes are % bytes after the rebuild, from %',
      pg_indexes_size('public.ottoq_stall_bookings'::regclass), (SELECT idx_bytes FROM m0602_before);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0602_the_calendar_keeps_the_exclusion_that_binds_and_sheds_the_one_it_subsumes', false, false,
  'G312, overnight review 2026-09-30; filed by db/checks/0203 on 2026-09-13. Drops ottoq_stall_bookings_no_overlap_v2, '
  'whose rows are a subset of no_overlap_v3''s on the same key (it can refuse nothing v3 does not), and REINDEXes the '
  'calendar (641 MB of index for 12,215 rows on 2026-09-30). v1 and v3 stay unchanged; V2 proves an overlapping pair is '
  'still refused, by v3. No function changes. Chase''s sign-off required (CLAUDE.md rule 6).', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
