-- migration-version: 20260927140742
-- migration-name:    kpi_two_counts_a_turn_when_a_car_leaves_a_service_point
--
-- 0527  **G252: KPI 2 counted a booking the car outlived as a turn, and a charge still running at the day's end as no
--       turn at all -- so a dial that sizes bookings correctly lost turns it never lost. A turn is now a car leaving a
--       service point, read from the signed event stream; the booking counts stay beside it as the audit.**
--       `db/checks/0395`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_kpi_service_point_turns` (0183) counted a turn as a booking in state `done`. 0183 was right that `released`
--   is not a turn, and took `done`/`window_elapsed_occupied` -- the window ran out with the car on the stall -- to be a
--   kept reservation, hence a completed one. It is kept, but not completed: the car stays, and nothing counts its
--   leaving. And a booking still in progress at the run's horizon is closed `run_stopped` and counts nothing. So KPI 2
--   depended on how long bookings are, not on how often a point turned over.
--   G240's experiment is the case that made it matter. Its treatment sizes charge bookings to cover the charge; its
--   arms are the same world -- the same charge sessions, deploys, trips, throughput and peak, and the same 37, 36 and 28
--   charges running at 5 PM -- yet turns per point read 1.74 -> 1.64, 1.72 -> 1.71, 1.57 -> 1.45 (0395 §1-§2): the
--   control's short windows elapse under charging cars (48-51 per arm) and count, the treatment's cover the charges
--   still running at the horizon and do not. Turns per point is a reward KPI (weight +0.3), so a guardrail of every dial
--   experiment, and its mean change of -4.66% against a 2% margin would have concluded G240 as `guardrail_breach`
--   tonight (0395 §3).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A turn is a car leaving a service point: a `vehicle.state_changed` event whose diff has `current_stall_id.from`.
--   The run's teardown, which moves every parked car off its stall to `offline` at the final clock, is excluded -- it is
--   the depot being cleared (0395 §4(a): every such departure on the reference runs, none before the end, none in the
--   first minute). `points_used` is the stalls a car left that day, the teardown included, since that is a stall that
--   was occupied; on all nine reference runs it equals the booked count, so the denominator does not move (0395 §4(b)).
--   The booking columns stay, and four are added: `bookings_done` (0183's numerator, exactly), `points_booked`,
--   `booking_turns_per_point_per_day` (0183's headline, exactly) and `left_at_teardown`. `ottoq_kpi_five_raw`'s audit
--   carries `bookings_done` and `left_at_teardown`, so the one command shows both counts (0185's rule).
--   `(e.event_type || '')` keeps the planner on the per-run index: with a bare `event_type =` it ANDs in the 1.8M-row
--   event-type index and one run takes 1.9 s instead of 82 ms (0395).
--   Runs only (`sim_run_id IS NOT NULL`): the one command, the dial metrics and the run-dial capture all read one run;
--   the unrun rows 0183's view grouped under NULL had no reader.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart left NULL (restarts) ═════════════════════════════════════════════
--
--   No certification atom reads a KPI (ottoq_determinism_pair does not mention one). It changes what every dial
--   experiment's guardrail measures, so a pair counted before it cannot be compared with one after: it restarts them.
--   Applied with 0526 (G251), which restarts them too, so they restart once.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0527 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_cols text; v_raw text;
BEGIN
  IF position('0527' IN COALESCE(obj_description('public.ottoq_kpi_service_point_turns'::regclass), '')) > 0 THEN
    RAISE EXCEPTION '0527 P2: already applied';
  END IF;
  -- the view is 0183's, column for column, so CREATE OR REPLACE can keep every column and append
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_kpi_service_point_turns'::regclass AND a.attnum > 0;
  IF v_cols IS DISTINCT FROM 'sim_run_id:uuid,day:date,turns_completed:bigint,points_used:bigint,'
       'turns_per_point_per_day:numeric,bookings_not_a_turn:bigint,released_never_occupied:bigint,'
       'released_by_teardown:bigint,released_no_show:bigint,points_with_a_turn:bigint,bookings_seen:bigint' THEN
    RAISE EXCEPTION '0527 P2: the view''s columns are not 0183''s: %', v_cols;
  END IF;
  -- its one reader is the one command; the dial metrics and the run-dial capture read that
  IF (SELECT array_agg(p.oid::regprocedure::text ORDER BY 1) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc LIKE '%ottoq_kpi_service_point_turns%')
     IS DISTINCT FROM ARRAY['ottoq_kpi_five_raw(uuid)']
     OR EXISTS (SELECT 1 FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid
                 WHERE d.refobjid = 'public.ottoq_kpi_service_point_turns'::regclass
                   AND r.ev_class <> 'public.ottoq_kpi_service_point_turns'::regclass) THEN
    RAISE EXCEPTION '0527 P2: something besides ottoq_kpi_five_raw reads the view';
  END IF;
  -- no certification atom reads a KPI
  IF pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure) ~* 'kpi' THEN
    RAISE EXCEPTION '0527 P2: the determinism pair reads a KPI; this is not forces_recert FALSE';
  END IF;
  -- the audit block is the one this file patches
  v_raw := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  IF (length(v_raw) - length(replace(v_raw, '''points_with_a_turn_max_day'', max(points_with_a_turn))', '')))
       / length('''points_with_a_turn_max_day'', max(points_with_a_turn))') <> 1 THEN
    RAISE EXCEPTION '0527 P2: ottoq_kpi_five_raw''s turns audit is not as this file expects';
  END IF;
  -- the teardown is recognisable: on the reference runs every departure at the final clock is to offline, none
  -- before it is, and nothing departs in a run's first minute
  IF EXISTS (
       SELECT 1 FROM public.ottoq_sim_runs r JOIN public.ottoq_events e ON e.sim_run_id = r.sim_run_id
        WHERE r.sim_run_id IN ('6ddd827e-b549-43cf-8154-4d1bfb20cabf', '4bc19d29-790c-4cb0-9e2e-ae090a7da57b')
          AND (e.event_type || '') = 'vehicle.state_changed' AND e.payload->'diff'->'current_stall_id'->>'from' IS NOT NULL
          AND ((e.sim_clock_at >= r.sim_clock_current) <> (e.payload->'diff'->'current_state'->>'to' IS NOT DISTINCT FROM 'offline')
               OR e.sim_clock_at <= r.sim_clock_start + interval '1 minute')) THEN
    RAISE EXCEPTION '0527 P2: a departure on a reference run is not where the teardown rule puts it';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0527_pre', 'view', 'public', 'ottoq_kpi_service_point_turns',
       pg_get_viewdef('public.ottoq_kpi_service_point_turns'::regclass, true),
       md5(pg_get_viewdef('public.ottoq_kpi_service_point_turns'::regclass, true))
UNION ALL
SELECT '0527_pre', 'function', 'public', 'ottoq_kpi_five_raw',
       pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure));

-- what the booking count read before, to prove below that bookings_done reproduces it, run by run and day by day, on
-- every operator, production and A/B-harness run held today (56); the 592 certification arms are left out only because
-- reading all 1.7M run events at once does not fit in an apply, and the booking branch is the same SQL for every run
CREATE TEMP TABLE v0527_before ON COMMIT DROP AS
SELECT t.sim_run_id, t.day, t.turns_completed, t.points_used, t.turns_per_point_per_day
  FROM public.ottoq_kpi_service_point_turns t JOIN public.ottoq_sim_runs r ON r.sim_run_id = t.sim_run_id
 WHERE r.run_by IN ('operator_demo', 'production_live', 'ab_harness');

-- ── the view ──
CREATE OR REPLACE VIEW public.ottoq_kpi_service_point_turns AS
SELECT u.sim_run_id,
       u.day,
       count(*) FILTER (WHERE u.src = 'left' AND NOT u.teardown)                                  AS turns_completed,
       count(DISTINCT u.stall_id) FILTER (WHERE u.src = 'left')                                   AS points_used,
       round(count(*) FILTER (WHERE u.src = 'left' AND NOT u.teardown)::numeric
             / GREATEST(1::bigint, count(DISTINCT u.stall_id) FILTER (WHERE u.src = 'left'))::numeric, 2)
                                                                                                  AS turns_per_point_per_day,
       count(*) FILTER (WHERE u.src = 'booked' AND u.state <> 'done')                             AS bookings_not_a_turn,
       count(*) FILTER (WHERE u.src = 'booked' AND u.release_reason = 'window_elapsed')           AS released_never_occupied,
       count(*) FILTER (WHERE u.src = 'booked' AND u.release_reason = 'run_stopped')              AS released_by_teardown,
       count(*) FILTER (WHERE u.src = 'booked' AND u.release_reason = 'no_show_grace_elapsed')    AS released_no_show,
       count(DISTINCT u.stall_id) FILTER (WHERE u.src = 'left' AND NOT u.teardown)                AS points_with_a_turn,
       count(*) FILTER (WHERE u.src = 'booked')                                                   AS bookings_seen,
       -- 0527: 0183's count, kept as the audit
       count(*) FILTER (WHERE u.src = 'booked' AND u.state = 'done')                              AS bookings_done,
       count(DISTINCT u.stall_id) FILTER (WHERE u.src = 'booked')                                 AS points_booked,
       round(count(*) FILTER (WHERE u.src = 'booked' AND u.state = 'done')::numeric
             / GREATEST(1::bigint, count(DISTINCT u.stall_id) FILTER (WHERE u.src = 'booked'))::numeric, 2)
                                                                                                  AS booking_turns_per_point_per_day,
       count(*) FILTER (WHERE u.src = 'left' AND u.teardown)                                      AS left_at_teardown
  FROM (
        -- a car leaving a stall, from the signed event stream; `|| ''` keeps the planner on the per-run index
        SELECT 'left'::text AS src, e.sim_run_id, date_trunc('day', e.sim_clock_at)::date AS day,
               (e.payload->'diff'->'current_stall_id'->>'from')::uuid AS stall_id,
               COALESCE(e.payload->'diff'->'current_state'->>'to' = 'offline', false) AS teardown,
               NULL::text AS state, NULL::text AS release_reason
          FROM public.ottoq_events e
         WHERE (e.event_type || '') = 'vehicle.state_changed' AND e.sim_run_id IS NOT NULL
           AND e.payload->'diff'->'current_stall_id'->>'from' IS NOT NULL
        UNION ALL
        SELECT 'booked', b.sim_run_id, date_trunc('day', lower(b.during))::date, b.stall_id, false, b.state, b.release_reason
          FROM public.ottoq_stall_bookings b
         WHERE b.sim_run_id IS NOT NULL
       ) u
 GROUP BY u.sim_run_id, u.day;

COMMENT ON VIEW public.ottoq_kpi_service_point_turns IS
  'Canonical KPI 2 (CLAUDE.md 2.9). A turn is a COMPLETED occupancy of a service point. 0527 (G252): counted as a car '
  'LEAVING the point -- a vehicle.state_changed event whose diff has current_stall_id.from -- except the run''s '
  'teardown, which moves every parked car to offline at the final clock (left_at_teardown). points_used is the stalls a '
  'car left that day, the teardown included. The booking count 0183 used (state = done) depended on booking length: a '
  'window that elapsed under a car that stayed counted, and a charge still running at the horizon (released '
  'run_stopped) did not, so a dial sizing bookings correctly lost turns it never lost -- G240''s arms, identical worlds, '
  'read 1.74 vs 1.64 (db/checks/0395). It stays as the audit: bookings_done and booking_turns_per_point_per_day '
  'reproduce 0183''s numerator and headline exactly, and bookings_done + bookings_not_a_turn = bookings_seen. '
  '0183: the definition before it counted state IN (done, released, interrupted), 3.72x over. Runs only; the per-point '
  'denominator (per occupied, per turned or per installed point) is still a definitional choice and is not decided '
  'here; points_with_a_turn exposes the gap.';

-- ── the one command's audit carries both counts ──
DO $patch_raw$
DECLARE
  v_def text;
  v_old text := $o$'points_with_a_turn_max_day', max(points_with_a_turn))$o$;
  v_new text := $n$'points_with_a_turn_max_day', max(points_with_a_turn),
            -- 0527 (G252): the headline counts cars leaving a point; 0183's booking count and the teardown beside it
            'bookings_done',            sum(bookings_done),
            'left_at_teardown',         sum(left_at_teardown))$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0527: audit patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_raw$;

DO $verify$
DECLARE v_view text; v_raw text; v_run uuid; v_n int := 0;
BEGIN
  v_view := pg_get_viewdef('public.ottoq_kpi_service_point_turns'::regclass, true);
  v_raw  := pg_get_functiondef('public.ottoq_kpi_five_raw(uuid)'::regprocedure);
  -- V1 (a): bookings_done, points_booked and booking_turns_per_point_per_day reproduce 0183's numerator, denominator and
  --     headline for every day of every run read a moment ago -- one run at a time, so each read stays on the run index
  FOR v_run IN SELECT DISTINCT sim_run_id FROM v0527_before LOOP
    IF EXISTS (SELECT 1 FROM v0527_before b
                 LEFT JOIN (SELECT * FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = v_run) t ON t.day = b.day
                WHERE b.sim_run_id = v_run
                  AND (t.bookings_done IS DISTINCT FROM b.turns_completed
                       OR t.points_booked IS DISTINCT FROM b.points_used
                       OR t.booking_turns_per_point_per_day IS DISTINCT FROM b.turns_per_point_per_day)) THEN
      RAISE EXCEPTION '0527 V1: run %: the booking audit does not reproduce 0183''s count', v_run;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n < 50 THEN RAISE EXCEPTION '0527 V1: only % runs compared', v_n; END IF;
  -- V1 (b): the headline reads departures, the teardown is excluded, the booking audit is there; the old 11 columns keep
  --     their names, types and order; the one command's audit carries both counts
  IF position('current_stall_id' IN v_view) = 0 OR position('offline' IN v_view) = 0
     OR position('bookings_done' IN v_view) = 0 OR position('booking_turns_per_point_per_day' IN v_view) = 0
     OR (SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
           FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_kpi_service_point_turns'::regclass AND a.attnum > 0)
        IS DISTINCT FROM 'sim_run_id:uuid,day:date,turns_completed:bigint,points_used:bigint,'
          'turns_per_point_per_day:numeric,bookings_not_a_turn:bigint,released_never_occupied:bigint,'
          'released_by_teardown:bigint,released_no_show:bigint,points_with_a_turn:bigint,bookings_seen:bigint,'
          'bookings_done:bigint,points_booked:bigint,booking_turns_per_point_per_day:numeric,left_at_teardown:bigint'
     OR position('''bookings_done'',            sum(bookings_done)' IN v_raw) = 0
     OR position('''left_at_teardown'',         sum(left_at_teardown))' IN v_raw) = 0 THEN
    RAISE EXCEPTION '0527 V1: the view or the one command is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule): forces_recert FALSE, forces_dial_restart left NULL.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0527_kpi_two_counts_a_turn_when_a_car_leaves_a_service_point', false,
  'KPI 2 only, read by the one command, the dial arm metrics and the run-dial capture; no certification atom reads a '
  'KPI. A turn is a car leaving a service point, from the event stream, teardown excluded (G252). It changes what every '
  'dial experiment''s guardrail measures, so forces_dial_restart is left NULL.', now())
ON CONFLICT (name) DO NOTHING;

-- V3: read-only over G240's three counted pairs and 6ddd827e. (a) As driven, both arms of pairs 76 and 80 read the same
--     turns per point (2.42, 2.19), and pair 78's treatment reads more per point (2.60 against 2.44, the same cars on
--     fewer stalls). (b) As booked, the six arms read 0183's 1.74/1.64, 1.72/1.71, 1.57/1.45 exactly. (c) 6ddd827e:
--     577 turns on 133 points, 106 left at the teardown. (d) The one command reads 6ddd827e in under 2 seconds.
DO $v3$
DECLARE
  v_msg text; v_t0 timestamptz; v_ms numeric; v_raw jsonb;
  v_driven text; v_booked text; v_full record;
BEGIN
  BEGIN
    SELECT string_agg(format('%s%s:%s', p.pair_id, arm.a, t.turns_per_point_per_day), ' ' ORDER BY p.pair_id, arm.a),
           string_agg(format('%s%s:%s', p.pair_id, arm.a, t.booking_turns_per_point_per_day), ' ' ORDER BY p.pair_id, arm.a)
      INTO v_driven, v_booked
      FROM public.ottoq_dial_pair_ledger p
      CROSS JOIN LATERAL (VALUES ('A', p.run_a), ('B', p.run_b)) AS arm(a, run)
      JOIN public.ottoq_kpi_service_point_turns t ON t.sim_run_id = arm.run AND t.day = DATE '2026-09-01'
     WHERE p.pair_id IN (76, 78, 80);
    IF v_driven IS DISTINCT FROM '76A:2.42 76B:2.42 78A:2.44 78B:2.60 80A:2.19 80B:2.19' THEN
      RAISE EXCEPTION '0527 V3 FAILED (a): as driven %', v_driven;
    END IF;
    IF v_booked IS DISTINCT FROM '76A:1.74 76B:1.64 78A:1.72 78B:1.71 80A:1.57 80B:1.45' THEN
      RAISE EXCEPTION '0527 V3 FAILED (b): as booked %', v_booked;
    END IF;
    SELECT sum(turns_completed) AS turns, max(points_used) AS points, sum(left_at_teardown) AS teardown INTO v_full
      FROM public.ottoq_kpi_service_point_turns WHERE sim_run_id = '6ddd827e-b549-43cf-8154-4d1bfb20cabf';
    IF v_full.turns <> 577 OR v_full.points <> 133 OR v_full.teardown <> 106 THEN
      RAISE EXCEPTION '0527 V3 FAILED (c): 6ddd827e read % turns on % points, % at the teardown', v_full.turns, v_full.points, v_full.teardown;
    END IF;
    v_t0 := clock_timestamp();
    v_raw := public.ottoq_kpi_five_raw('6ddd827e-b549-43cf-8154-4d1bfb20cabf');
    v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
    IF v_ms > 2000 OR (v_raw->'audit'->'service_point_turns_per_point_per_day'->>'bookings_done')::int <> 498
       OR (v_raw->'audit'->'service_point_turns_per_point_per_day'->>'turns_completed')::int <> 577 THEN
      RAISE EXCEPTION '0527 V3 FAILED (d): the one command took % ms and read %', round(v_ms), v_raw->'audit'->'service_point_turns_per_point_per_day';
    END IF;
    RAISE EXCEPTION '0527 V3 PASSED: as driven %; as booked %; 6ddd827e 577 turns on 133 points; the one command in % ms',
      v_driven, v_booked, round(v_ms);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0527 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0527 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0527_pre' -- the view's as
--   CREATE OR REPLACE VIEW public.ottoq_kpi_service_point_turns AS <definition> (it drops the four appended columns
--   only through DROP VIEW ... then CREATE, since CREATE OR REPLACE cannot remove columns), the function's as is.
COMMIT;
