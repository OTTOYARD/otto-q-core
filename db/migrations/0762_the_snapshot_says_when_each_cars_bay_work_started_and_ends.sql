-- migration-version: 20261021022543
-- migration-name:    the_snapshot_says_when_each_cars_bay_work_started_and_ends
--
-- 0762  **The snapshot says when each car's bay work started and when it ends.** (G480)
--       Chase, 2026-10-20 9:05 PM CT: "Wash bays are robotic too. Car pulls in and the machine moves back and forth
--       over it several times to wash and rinse and blow dry before vehicle leave." The twin times a wash bay's work
--       (0746; wash_lane_physics is 2 at the twin depot since 9:10 PM CT, 02:10:59 UTC on 2026-10-21). The renderer
--       (ottoyarddepot-sim) plays the bay's rollover machine for that time, so it must know the times. The snapshot
--       did not publish them.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-20 9:15-9:24 PM CT, 02:15-02:24 UTC on 2026-10-21) ══════════════════════════
--
--   public.ottoq_twin_snapshot is what the renderer reads every poll. For each car it gives the state, the stall, the
--   charge and the open visit's atoms. A car's bay work has no time on any of them:
--     - On run c6ec017d, 17 exterior washes and 14 deep cleans were done. Each atom carries a done_at and no started_at
--       or ends_at. Only the cleaning arm's interior tidies carry both (0758).
--     - The twin's own times are on the car. The bay door that seats a car changes its state, so last_state_change is
--       when it entered the bay. Its timer is config.service_ends_at, which twin.ottoq_sim_time_bay_work rewrites from
--       the work's minutes (0746). Both are on the sim clock: the vehicles' last_state_change at the twin depot reads
--       2026-10-20 22:01:21.874455 UTC, c6ec017d's final sim clock to the microsecond.
--   So the renderer cannot tell a wash that started 10 sim-seconds ago from one that ends in 10, and cannot fit the
--   machine's passes into the seat.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Always on. One key on each car in the snapshot's fleet list, `bay_seat`:
--     - for a car in a wash, detail or service bay: {since: last_state_change, ends_at: config.service_ends_at};
--     - JSON null for every other car.
--   Both are on the sim clock, like every time in the snapshot, and both go out as strict ISO 8601, which every browser
--   parses (Safari refuses the database's own text form, "2026-10-21 02:30:00+00"). The timer is cast by a new helper,
--   public.ottoq_try_timestamptz(text), which gives null for a value that is not a timestamp, so a malformed timer can
--   never end the snapshot (the snapshot's own rule for est_min).
--   Not changed: anything the engine decides or the twin does. No engine function reads the snapshot. Its one caller,
--   ottoq_t4_coverage, reads other keys.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   - P0: nothing in flight.
--   - P1: not already applied. The snapshot is the body read (prosrc md5 9677506f). The helper does not exist yet.
--   - The pre-image goes to ottoq_schema_snapshots as '0762_pre'.
--   - The anchor matches exactly once.
--   - V1: the body less its insertion is its pre-image.
--   - V2: the insertion, as written, runs over every car in the depot table (nothing is written), and the helper gives
--     null for an empty string, a word, a date that does not exist and a time that does not exist, and the same instant
--     for a timestamp in the database's own text form.
--   - V3: the snapshot of the twin depot's newest run carries `bay_seat` on every car, null on every car in no bay.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. The snapshot is a read. No atom, decision, booking or event
--   changes.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0762_pre'; then the helper
--   public.ottoq_try_timestamptz(text) is unused and may be removed;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0762_the_snapshot_says_when_each_cars_bay_work_started_and_ends'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0762 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied, and the body as read ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0762_the_snapshot_says_when_each_cars_bay_work_started_and_ends') THEN
    RAISE EXCEPTION '0762 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_twin_snapshot(uuid)'))
     IS DISTINCT FROM '9677506f209abc4db0c39bc1fbb0a440' THEN
    RAISE EXCEPTION '0762 P1: public.ottoq_twin_snapshot is not the body read (md5 9677506f)';
  END IF;
  IF to_regprocedure('public.ottoq_try_timestamptz(text)') IS NOT NULL THEN
    RAISE EXCEPTION '0762 P1: public.ottoq_try_timestamptz(text) already exists';
  END IF;
END $premises$;

-- ── the helper: a timestamp, or null ──
CREATE FUNCTION public.ottoq_try_timestamptz(p_text text) RETURNS timestamptz
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog
AS $fn$
-- 0762 (G480): the value as a timestamp, or NULL when it is not one. A reader that must never raise (the snapshot)
-- casts a timer it did not write through this.
BEGIN
  IF p_text IS NULL OR btrim(p_text) = '' THEN
    RETURN NULL;
  END IF;
  RETURN p_text::timestamptz;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_try_timestamptz(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_try_timestamptz(text) TO service_role;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0762_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure;

-- ── the patch: one key per car ──
DO $patch$
DECLARE
  c_old CONSTANT text := $o1$          'soc', ROUND(v.current_soc::numeric, 1), 'stall_id', v.current_stall_id,
$o1$;
  c_new CONSTANT text := $n1$          'soc', ROUND(v.current_soc::numeric, 1), 'stall_id', v.current_stall_id,
          -- 0762 (G480): a car in a wash, detail or service bay carries its seat there: when it entered the bay (the
          -- bay door changes its state) and when the twin's timer ends its work (config.service_ends_at, which 0746
          -- times by the work). Both are on the sim clock. The renderer plays the bay's robot inside this window.
          -- The timer goes through public.ottoq_try_timestamptz, so a malformed one is null and cannot end the
          -- snapshot. NULL for a car in no bay.
          'bay_seat', CASE WHEN v.current_state::text IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
                           THEN jsonb_build_object(
                                  'since', v.last_state_change,
                                  'ends_at', public.ottoq_try_timestamptz(v.config ->> 'service_ends_at'))
                      END,
$n1$;
  v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0762: the snapshot anchor matches % times, not 1', n;
  END IF;
  v_def := replace(v_def, c_old, c_new);
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_twin_snapshot(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0762: the snapshot is not stored as patched';
  END IF;

  -- V1: the body less its insertion is its pre-image
  IF md5(replace((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_twin_snapshot(uuid)'::regprocedure), c_new, c_old))
     IS DISTINCT FROM '9677506f209abc4db0c39bc1fbb0a440' THEN
    RAISE EXCEPTION '0762 V1: the snapshot less its insertion is not its pre-image';
  END IF;

  -- V2: the insertion, as written, over every car (its key and value are what lie between the anchor's line and the
  -- next key's comma). A wrong name, type or cast would otherwise surface only on the next poll, and fail every poll.
  EXECUTE 'SELECT count(*) FROM public.vehicles v WHERE jsonb_build_object('
          || rtrim(substr(c_new, length(c_old) + 1), E',\n ') || ') IS NOT NULL'
    INTO n;
  IF n IS DISTINCT FROM (SELECT count(*)::int FROM public.vehicles) THEN
    RAISE EXCEPTION '0762 V2: the insertion did not run over every car (% of %)', n, (SELECT count(*) FROM public.vehicles);
  END IF;
  IF public.ottoq_try_timestamptz('') IS NOT NULL OR public.ottoq_try_timestamptz('null') IS NOT NULL
     OR public.ottoq_try_timestamptz('2026-02-30 10:00:00+00') IS NOT NULL
     OR public.ottoq_try_timestamptz('2026-10-21 25:61:00+00') IS NOT NULL
     OR public.ottoq_try_timestamptz(NULL) IS NOT NULL
     OR public.ottoq_try_timestamptz('2026-10-21 02:30:00.5+00') IS DISTINCT FROM '2026-10-21T02:30:00.5Z'::timestamptz THEN
    RAISE EXCEPTION '0762 V2: public.ottoq_try_timestamptz does not give null for a non-timestamp and the instant for a timestamp';
  END IF;
END $patch$;

-- ── V3: the twin depot's newest run, through the snapshot ──
DO $v3$
DECLARE v_run uuid; v_snap jsonb; v_cars int; v_keyed int; v_bad int;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RETURN;
  END IF;
  v_snap := public.ottoq_twin_snapshot(v_run);
  SELECT count(*), count(*) FILTER (WHERE e ? 'bay_seat'),
         count(*) FILTER (WHERE (e ->> 'state') NOT IN ('in_wash_bay', 'in_detail_bay', 'in_service_bay')
                                AND jsonb_typeof(e -> 'bay_seat') IS DISTINCT FROM 'null')
    INTO v_cars, v_keyed, v_bad
    FROM jsonb_array_elements(COALESCE(v_snap -> 'fleet' -> 'vehicles', '[]'::jsonb)) e;
  IF v_cars = 0 OR v_keyed <> v_cars OR v_bad <> 0 THEN
    RAISE EXCEPTION '0762 V3: % cars, % with bay_seat, % in no bay with a seat', v_cars, v_keyed, v_bad;
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0762_the_snapshot_says_when_each_cars_bay_work_started_and_ends', false, false,
        'G480. public.ottoq_twin_snapshot publishes bay_seat on each car: for a car in a wash, detail or service bay, '
        'when it entered the bay (last_state_change) and when the twin''s timer ends its work (config.service_ends_at, '
        'timed by the work since 0746), both on the sim clock, the timer through the new public.ottoq_try_timestamptz; '
        'null for every other car. The renderer plays the wash bay''s rollover machine inside that window. A read: no '
        'engine function reads the snapshot.',
        now());

COMMIT;
