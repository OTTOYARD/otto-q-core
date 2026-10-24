-- migration-version: PENDING
-- migration-name:    the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due
--
-- 0769  **The agent's wake gate also wakes it when a charger is free with a car waiting, or a car in the line's head
--       has a dispatch due time: the two moments its charge order changes what the kernel does.** (G488)
--       Chase, 2026-10-23 at about 10:25 PM CT: "study the agent layer and see if there is any opportunity for growth
--       and expansion with intelligence there"; at about 11:40 PM CT: "just build to completion as needed".
--
-- ══ §1 WHY (read-only on live, 2026-10-24 04:50-05:00 UTC; db/checks/0461 §7) ════════════════════════════════════════
--
--   The gate (public.ottoq_agent_wake, 0705/0710/0711) runs in shadow at the twin depot (agent_wake_enabled 0): it
--   records what it would do and the agent is consulted every pass. On run 78c0624c it would have woken on 5 of 151
--   passes, and 1 of the 8 passes whose charge order the kernel's check took. What separates those 8 is on the board the
--   agent read (ottoq_agent_pass_evidence.board_text, charge_queue): when the check took the order, a mean 4.13 chargers
--   were free at that moment and 3.1 cars of the line's first 24 had a dispatch due time; for the 81 orders the check
--   recorded as the kernel's own (projection reason 'same_as_kernel', 78 of the run's 131 orders by 04:40 UTC), 0.28 and
--   0.6; for the 45 that differed and lost, 0.18 and 1.0. An order changes nothing while every charger is busy and every
--   car in the head is past the wait floor: the kernel's order is then the longest wait first, and the agent repeats it.
--   Replayed on the recorded boards, a gate that also wakes when (a charger is free AND a car is waiting) OR (a car in
--   the first 24 has a due time):
--                                      passes   woken          taken orders woken   model tokens kept
--     78c0624c (in sample)                151     79 (52%)       8 of 8               51.6%
--     14 other runs, 10-13 to 10-24      1,106    529 (48%)      16 of 22             49.3%
--     the gate as it is, 14 runs         1,106    193            6 of 22
--   (the passes read by recorded_at, the board as stored, the order joined by chain_id; the in-sample row was read
--   first, so the out-of-sample row is the one to quote.)
--
-- ══ §2 WHAT CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_wake, four anchored changes, everything else as 0711 left it:
--     (a) two counts, read as the agent's board reads them (ottoq_agent_charge_queue_board): the cars among the kernel's
--         first 24 whose open visit on this run carries a dispatch due time (the board's due_in_min), counted in the same
--         pass over the kernel's order that counts the line (no third call of it); and the chargers free now
--         (contention.free_now): no car on the stall, no live reservation, its charger Available with a heartbeat in the
--         last 90 s, no booking covering the moment;
--     (b) both in the fingerprint, as chargers_free and due_in_line;
--     (c) two reasons, charger_free (a free charger and a car waiting) and due_in_line (a car with a due time in the
--         head), each a level, not an onset: every pass that meets one is a pass whose order can change what happens.
--   In shadow nothing changes but the record (wake stays true on every pass); where the gate is on (five research runs
--   set it), it can only wake more, never less.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the gate is the body 0711 left and live carries (prosrc md5 3ce4f3f5), 0711 is classified,
--   and every column the counts read exists. P2 not already applied. Pre-image to ottoq_schema_snapshots as '0769_pre'.
--   Each anchor matches once. V1 the body less its changes is its pre-image. V2 the two counts run on every running run
--   (a missing column would only surface at run time, where the gate's handler would turn it into a wake on every
--   pass). V3 the body is the one the tests ran. Executed by tests/test_agent_wake_seat_moments_sql.py on the stub
--   engine of tests/test_agent_scouts_wake_sql.py, whose gate is byte-for-byte live's.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═══════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE, forces_dial_restart FALSE: the gate is read only by the agent's edge function, quiesced in
--   certification arms and dial pairs; no atom reads it.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0769_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0769_the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0769 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, 0711, and the columns the counts read ──
DO $p1$
DECLARE c text;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_agent_wake(uuid)'))
       IS DISTINCT FROM '3ce4f3f5bc2070ad5778ad1b5fb002b8' THEN
    RAISE EXCEPTION '0769 P1: public.ottoq_agent_wake is not the body this file patches (md5 3ce4f3f5)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0711_the_wake_gate_wakes_on_a_change_that_matters_not_on_every_wobble') THEN
    RAISE EXCEPTION '0769 P1: 0711 is not classified; apply in order';
  END IF;
  FOREACH c IN ARRAY ARRAY['stalls.reservation_expires_at', 'ottoq_ocpp_chargers.last_heartbeat_at',
                           'ottoq_stall_bookings.during', 'ottoq_stall_bookings.state', 'ottoq_visit_needs.dispatch_due_at',
                           'ottoq_visit_needs.visit_key'] LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = split_part(c, '.', 1)
                      AND column_name = split_part(c, '.', 2)) THEN
      RAISE EXCEPTION '0769 P1: public.% is missing', c;
    END IF;
  END LOOP;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0769_the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due') THEN
    RAISE EXCEPTION '0769 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0769_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_wake(uuid)'::regprocedure;

-- ── the patches ──
CREATE TEMP TABLE _0769_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0769_patch VALUES
  -- (a) the two counts' variables
  (1,
   $a1o$  v_objective text;
BEGIN
$a1o$,
   $a1n$  v_objective text;
  v_free     integer; v_due integer;                   --: 0769 (G488)
BEGIN
$a1n$),
  -- (a) the due cars, in the pass that counts the line; the free chargers, as the board counts them
  (2,
   $a2o$  SELECT count(*) INTO v_waiting
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
$a2o$,
   $a2n$  --: 0769 (G488): the same pass over the kernel's order counts the cars in its first 24 whose open visit on this run
  --: carries a dispatch due time, read as the agent's board reads due_in_min
  SELECT count(*), count(*) FILTER (WHERE k.kernel_pos <= 24 AND vd.dispatch_due_at IS NOT NULL)
    INTO v_waiting, v_due
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
    LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM public.ottoq_visit_needs vn
                        WHERE vn.vehicle_id = k.vehicle_id AND vn.status IN ('open', 'in_progress')
                          AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                        ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vd ON true;
  --: 0769 (G488): a charger free now, as the board counts contention.free_now: no car on the stall, no live
  --: reservation, its charger Available with a heartbeat in the last 90 s, and no booking covering the moment
  SELECT count(*) INTO v_free
    FROM public.stalls s
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_run.depot_id AND s.stall_type::text IN ('dcfc', 'l2')
     AND s.current_vehicle_id IS NULL
     AND NOT (s.reserved_by IS NOT NULL
              AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > v_run.sim_clock_current)
     AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_run.sim_clock_current - interval '90 seconds'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                      WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                        AND b.state IN ('held', 'active', 'done', 'interrupted')
                        AND b.during @> v_run.sim_clock_current);
$a2n$),
  -- (b) both in the fingerprint
  (3,
   $a3o$                             'scout_critical', v_crit, 'scout_stranded', v_strand);
$a3o$,
   $a3n$                             'scout_critical', v_crit, 'scout_stranded', v_strand,
                             'chargers_free', v_free, 'due_in_line', v_due);          --: 0769 (G488)
$a3n$),
  -- (c) the two reasons
  (4,
   $a4o$      v_reasons := array_append(v_reasons, 'scout_finding'::text);
    END IF;
  END IF;
$a4o$,
   $a4n$      v_reasons := array_append(v_reasons, 'scout_finding'::text);
    END IF;
    --: 0769 (G488): the two moments an order changes what the kernel does: a charger free with a car waiting, and a
    --: car in the line's head with a due time. Levels, not onsets: on run 78c0624c the 8 orders the check took came at
    --: a mean 4.13 chargers free against 0.28 for the 81 it recorded as the kernel's own order; replayed on 14 other
    --: runs' boards, these and the rules above woke 48% of passes and caught 16 of the 22 taken orders (6 before).
    IF v_free > 0 AND v_waiting > 0 THEN v_reasons := array_append(v_reasons, 'charger_free'::text); END IF;
    IF v_due > 0 THEN v_reasons := array_append(v_reasons, 'due_in_line'::text); END IF;
  END IF;
$a4n$);

-- A paste can arrive with Windows line endings (the SQL editor did so with 0765 on 2026-10-23); the stored definition ends
-- its lines in a bare newline, so the anchors and their replacements are read with bare newlines.
UPDATE _0769_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0769_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0769: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_agent_wake(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0769: the gate is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the body less its changes is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_agent_wake(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0769_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '3ce4f3f5bc2070ad5778ad1b5fb002b8' THEN
    RAISE EXCEPTION '0769 V1 FAILED: the gate less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the two counts run on every running run ──
DO $v2$
DECLARE r record; v_due int; v_free int; v_zero constant uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  FOR r IN SELECT sim_run_id, depot_id, sim_clock_current FROM public.ottoq_sim_runs
            WHERE status = 'running' AND depot_id IS NOT NULL AND sim_clock_current IS NOT NULL LOOP
    SELECT count(*) FILTER (WHERE k.kernel_pos <= 24 AND vd.dispatch_due_at IS NOT NULL) INTO v_due
      FROM public.ottoq_charge_queue_kernel_order(r.sim_run_id, r.depot_id, r.sim_clock_current) k
      LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM public.ottoq_visit_needs vn
                          WHERE vn.vehicle_id = k.vehicle_id AND vn.status IN ('open', 'in_progress')
                            AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(r.sim_run_id, v_zero)
                          ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vd ON true;
    SELECT count(*) INTO v_free
      FROM public.stalls s LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = r.depot_id AND s.stall_type::text IN ('dcfc', 'l2') AND s.current_vehicle_id IS NULL
       AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > r.sim_clock_current)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= r.sim_clock_current - interval '90 seconds'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                        WHERE b.sim_run_id = r.sim_run_id AND b.stall_id = s.id
                          AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> r.sim_clock_current);
    RAISE NOTICE '0769 V2: run % reads % due in the head and % chargers free', r.sim_run_id, v_due, v_free;
  END LOOP;
END $v2$;

-- ── V3: the patched body is byte for byte the one the tests ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_wake(uuid)'::regprocedure)
       IS DISTINCT FROM '353f108cb90369892c18a72537d2619b' THEN
    RAISE EXCEPTION '0769 V3 FAILED: the gate is not the body the tests ran';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0769_the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due', false, false,
        'G488. public.ottoq_agent_wake also counts the chargers free now and the cars in the kernel''s first 24 with a '
        'dispatch due time (both as the agent''s board counts them, the due cars in the same pass over the kernel''s '
        'order), carries both in its fingerprint, and wakes on charger_free (a free charger and a car waiting) and '
        'due_in_line. Replayed on 14 runs'' recorded boards: 48% of passes woken, 16 of 22 taken orders caught, 49.3% of '
        'model tokens kept (the gate before it: 6 of 22). In shadow (the twin depot) only the record changes; where '
        'the gate is on it wakes more, never less. Read only by the agent edge function, quiesced in certification.',
        now());

COMMIT;
