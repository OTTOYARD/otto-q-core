-- migration-version: 20260928074913
-- migration-name:    a_charger_its_car_has_left_for_a_bay_is_free
--
-- 0547  **A charger is free the moment its car has left it for a bay.** (G276, and the writer G121 could not find.)
--        When a car finishes a charge and goes straight on to a service, wash or detail bay, the update that empties
--        the charger's pointer was refused by the reassignment guard. The guard reads the car's state and never where
--        the car is, so a car in a bay read as work in progress at the charger it had left. The charger then read
--        `available` with a pointer to a car that was elsewhere. The decide tick offers a stall only when its pointer
--        is empty, so it could not give that charger to anyone. A car in a bay is not charging, so the charger it left
--        holds no work in progress. The guard now lets that charger be emptied without asking. Every other protection
--        is unchanged.
--
-- ══ §1 WHY (validation run dbdffd5c, check 0404 §12; CLAUDE.md rule 9; G276, G121) ════════════════════════════════════
--
--   Rule 9: when cars wait for chargers, one of the answers is freeing a charger the moment its car is done.
--
--   At sim 9:41 AM CT on dbdffd5c, DCFC-04 read `status = 'available'` with `current_vehicle_id` still Zoox-AV-078,
--   which was in the service bay. The signed stream shows the order (sim 9:40:53-9:41:15):
--     - the charge completes;
--     - the car goes to charge_complete_holding, then staged_awaiting_service (need_service), then `in_service_bay`;
--     - its `current_stall_id` and its tether are emptied;
--     - DCFC-04's update lands with only its status changed.
--
--   The writer is `public.ottoq_trg_reassignment_guard`, BEFORE UPDATE ON `stalls` (0029).
--   - When an update empties a stall's pointer, the guard reads the car's state.
--   - For a car in a bay or charging, it asks `ottoq_indepot_reassignment_guard(..., 'automated_reassignment', ...)`.
--   - When that declines, the guard restores `NEW.current_vehicle_id := OLD.current_vehicle_id`.
--   - The rest of the update goes through, which is why the stream shows the status moving alone.
--
--   The guard's own ledger (`ottoq_ops_approvals`, reason `automated_reassignment`) on dbdffd5c, through sim 10:30 AM,
--   splits the refusals into two groups by where the car was when the guard asked (its last `current_stall_id` in the
--   signed stream):
--     - **the car on the stall being emptied: 60 refusals**, 57 on L2 and 3 on fast chargers, every car charging
--       there. That is the guard doing its job.
--     - **the car on no stall: 19 refusals**, all from fast chargers, with the car already in a service bay (9), a wash
--       bay (7) or a detail bay (3). That is this defect.
--   Cost by sim 9:47 AM: **8 episodes on 7 of the 10 fast chargers, 132.5 fast-charger minutes, the longest 45.7**,
--   while 12-16 cars waited for a charger.
--   G121 (check 0326) found three fast chargers in exactly this state on 2026-09-22 and could not find the writer. The
--   pointer is put back inside a BEFORE trigger, so no event records a write of it.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   After the guard reads the car's state, it also reads where the car is. It returns without asking when all three
--   hold:
--     - the car is in a bay (`in_wash_bay`, `in_detail_bay`, `in_service_bay`);
--     - the stall being emptied is a charger (`dcfc`, `l2`);
--     - neither the car's `current_stall_id` nor its tether names that charger.
--   The car has left, and there is nothing at the charger to cut short. The charger is emptied, reads `available` with
--   no pointer, and the decide tick can offer it on its next pass.
--
--   Unchanged:
--     - a car charging keeps its charger (the 60 refusals above);
--     - a car in a bay keeps its bay, including one whose own `current_stall_id` is empty while the bay holds it
--       (0535 §1's wash-bay car);
--     - the transaction-local grant;
--     - the gate's verdict whenever it is asked.
--   Deliberately narrow. The broader rule, "protect a stall only if the car's own pointer names it", would drop 0535's
--   wash-bay car. A car in a bay cannot be charging, so this one case can be decided from the state and the stall type.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   In any arm where a car goes from a charger straight to a bay, the charger is now emptied at once. Which car is
--   offered it next, and when, can move; so can the approvals ledger and the stall events.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - A sweep for pointers already stranded. Every run's boot resets every stall (`twin.ottoq_sim_seed_fleet`), and
--     with this fix the path stops making new ones.
--   - The low standard visits 0404 §4 saw waiting 240 minutes for a charger. That is the charge order working as
--     written under a saturated charger bank, and 0546 (d) escalates each wait to a person.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0547 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the guard is the one measured (md5 of its source, 2026-09-28 06:45 UTC), bound where 0404 §12 found it ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_trg_reassignment_guard()'::regprocedure)
     <> '0300dd5c39532b375fe3259a0a822c69' THEN
    RAISE EXCEPTION '0547 P2: public.ottoq_trg_reassignment_guard is not the function measured';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.stalls'::regclass AND t.tgname = 'trg_reassignment_guard'
                    AND t.tgfoid = 'public.ottoq_trg_reassignment_guard()'::regprocedure
                    AND pg_get_triggerdef(t.oid) LIKE '%BEFORE UPDATE ON public.stalls FOR EACH ROW%') THEN
    RAISE EXCEPTION '0547 P2: trg_reassignment_guard is not the BEFORE UPDATE row trigger on stalls';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0547_pre', 'function', 'public', 'ottoq_trg_reassignment_guard',
       pg_get_functiondef('public.ottoq_trg_reassignment_guard()'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_trg_reassignment_guard()'::regprocedure));

-- ── the guard reads where the car is, and frees a charger its car has left for a bay ──
DO $guard$
DECLARE v_def text; n int;
  c_decl_old CONSTANT text := $a$      v_state text;
      v_granted text;
    BEGIN$a$;
  c_decl_new CONSTANT text := $a$      v_state text;
      v_granted text;
      v_cur uuid;      -- 0547: the car's own stall
      v_tether uuid;   -- 0547: the stall the car is tethered to
    BEGIN$a$;
  c_body_old CONSTANT text := $a$        SELECT v.current_state::text INTO v_state FROM vehicles v WHERE v.id = v_vehicle_id;
        IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay',
                                              'charging_dcfc','charging_l2') THEN
          RETURN NEW;
        END IF;$a$;
  c_body_new CONSTANT text := $a$        SELECT v.current_state::text, v.current_stall_id, v.robotic_tether_stall_id
          INTO v_state, v_cur, v_tether FROM vehicles v WHERE v.id = v_vehicle_id;
        IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay',
                                              'charging_dcfc','charging_l2') THEN
          RETURN NEW;
        END IF;

        -- ── (1b) 0547 (G276): A CHARGER ITS CAR HAS LEFT FOR A BAY IS FREE ──────
        -- A car in a bay is not charging, so the charger it came from holds no work
        -- in progress. Reading the state alone made such a car look mid-work at the
        -- charger it had left: the pointer was put back, the charger read available
        -- with a car that was elsewhere, and nothing could offer it (G121). The car
        -- is still at the charger only if it names it itself, by its current_stall_id
        -- or its tether. A car in a bay keeps its bay, even with its own pointer
        -- empty (0535 §1).
        IF v_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
           AND OLD.stall_type::text IN ('dcfc','l2')
           AND v_cur IS DISTINCT FROM OLD.id AND v_tether IS DISTINCT FROM OLD.id THEN
          RETURN NEW;
        END IF;$a$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_trg_reassignment_guard()'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_decl_old, ''))) / length(c_decl_old);
  IF n <> 1 THEN RAISE EXCEPTION '0547 guard: the DECLARE anchor matches % times, not 1', n; END IF;
  n := (length(v_def) - length(replace(v_def, c_body_old, ''))) / length(c_body_old);
  IF n <> 1 THEN RAISE EXCEPTION '0547 guard: the state anchor matches % times, not 1', n; END IF;
  EXECUTE replace(replace(v_def, c_decl_old, c_decl_new), c_body_old, c_body_new);
END $guard$;

-- ── V1 (comment-stripped): the exception is there once, and the guard still keeps the pointer everywhere else ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_trg_reassignment_guard()'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'IF v_state IN \(''in_wash_bay'',''in_detail_bay'',''in_service_bay''\)\s+AND OLD\.stall_type::text IN \(''dcfc'',''l2''\)\s+AND v_cur IS DISTINCT FROM OLD\.id AND v_tether IS DISTINCT FROM OLD\.id THEN\s+RETURN NEW;', 'g')) <> 1 THEN
    RAISE EXCEPTION '0547 V1: the guard does not free a charger its car has left for a bay';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'SELECT v\.current_state::text, v\.current_stall_id, v\.robotic_tether_stall_id\s+INTO v_state, v_cur, v_tether FROM vehicles v WHERE v\.id = v_vehicle_id;', 'g')) <> 1 THEN
    RAISE EXCEPTION '0547 V1: the guard does not read where the car is';
  END IF;
  -- 0535 P2 relies on this line: everywhere else the guard still keeps the pointer when the gate declines
  IF (SELECT count(*) FROM regexp_matches(v_src, 'NEW\.current_vehicle_id := OLD\.current_vehicle_id;', 'g')) <> 1 THEN
    RAISE EXCEPTION '0547 V1: the guard no longer keeps the pointer when the gate declines';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0547_a_charger_its_car_has_left_for_a_bay_is_free', true, true,
  'G276 (the writer behind G121): public.ottoq_trg_reassignment_guard, BEFORE UPDATE on stalls, now reads where the car '
  'is as well as its state. When the car is in a bay (in_wash_bay, in_detail_bay, in_service_bay), the stall being '
  'emptied is a charger (dcfc, l2), and neither the car''s current_stall_id nor its tether names that charger, the '
  'guard returns without asking the in-depot gate: the car has left, and the charger is emptied. Before, a car in a bay '
  'read as work in progress at the charger it had left; the gate declined, the guard put the pointer back, and the '
  'charger read available with a pointer to a car elsewhere, so the decide tick could not offer it (dbdffd5c: 8 '
  'episodes on 7 of 10 fast chargers, 132.5 minutes by sim 9:47 AM). A car charging keeps its charger and a car in a '
  'bay keeps its bay, as before.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run dbdffd5c, marked running inside this block so the guard asks the gate as
--   it does on a live run. Three cars, three stalls, and the update every releaser uses (`current_vehicle_id = NULL,
--   status = 'available'`):
--   (a) DCFC d1 holds car c1, which is in the service bay with its own pointer and tether empty (0404 §12's shape):
--       d1 is emptied, and the gate is not asked (no new approval for c1);
--   (b) DCFC d2 holds car c2, which is charging there (its current_stall_id is d2): d2 keeps c2, as before (the gate is
--       asked, as before; whether it writes a new approval row or reuses one is the gate's business, so V3 reports it);
--   (c) wash bay w1 holds car c3, which is in the wash bay with its own pointer empty (0535 §1's shape): w1 keeps c3,
--       as before.
DO $v3$
DECLARE
  v_msg text; v_run uuid := 'dbdffd5c-a878-43ce-8b64-578bd776c813'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_cars uuid[]; c1 uuid; c2 uuid; c3 uuid; d1 uuid; d2 uuid; w1 uuid;
  p1 uuid; p2 uuid; p3 uuid; s1 text; a1 int; a2 int; b1 int; b2 int;
BEGIN
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run) THEN
      RAISE EXCEPTION '0547 V3: run % is gone; point V3 at a run that exists', v_run;
    END IF;
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = v_twin AND status = 'running') THEN
      RAISE EXCEPTION '0547 V3: a run is live at the twin depot; V3 must run between runs';
    END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' ORDER BY v.id LIMIT 3) q;
    c1 := v_cars[1]; c2 := v_cars[2]; c3 := v_cars[3];
    SELECT (array_agg(s.id ORDER BY s.id))[1], (array_agg(s.id ORDER BY s.id))[2] INTO d1, d2
      FROM public.stalls s WHERE s.depot_id = v_twin AND s.stall_type::text = 'dcfc';
    SELECT s.id INTO w1 FROM public.stalls s WHERE s.depot_id = v_twin AND s.stall_type::text = 'wash_bay' ORDER BY s.id LIMIT 1;
    IF c3 IS NULL OR d2 IS NULL OR w1 IS NULL THEN RAISE EXCEPTION '0547 V3: not enough twin cars or stalls'; END IF;

    -- set the scene with no run live, so the guard lets every setup write through
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE current_vehicle_id = ANY (v_cars) OR id IN (d1, d2, w1);
    UPDATE public.vehicles
       SET current_state = CASE WHEN id = c1 THEN 'in_service_bay' WHEN id = c2 THEN 'charging_dcfc' ELSE 'in_wash_bay' END::vehicle_state,
           current_stall_id = CASE WHEN id = c2 THEN d2 END,
           robotic_tether_stall_id = NULL
     WHERE id = ANY (v_cars);
    UPDATE public.stalls SET current_vehicle_id = c1, status = 'occupied' WHERE id = d1;
    UPDATE public.stalls SET current_vehicle_id = c2, status = 'occupied' WHERE id = d2;
    UPDATE public.stalls SET current_vehicle_id = c3, status = 'occupied' WHERE id = w1;

    -- now the run is live, as it is when a releaser runs
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    SELECT count(*) FILTER (WHERE vehicle_id = c1), count(*) FILTER (WHERE vehicle_id = c2) INTO b1, b2
      FROM public.ottoq_ops_approvals WHERE sim_run_id = v_run AND payload->>'reason' = 'automated_reassignment';

    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE id = d1;
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE id = d2;
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE id = w1;

    SELECT current_vehicle_id, status::text INTO p1, s1 FROM public.stalls WHERE id = d1;
    SELECT current_vehicle_id INTO p2 FROM public.stalls WHERE id = d2;
    SELECT current_vehicle_id INTO p3 FROM public.stalls WHERE id = w1;
    SELECT count(*) FILTER (WHERE vehicle_id = c1) - b1, count(*) FILTER (WHERE vehicle_id = c2) - b2 INTO a1, a2
      FROM public.ottoq_ops_approvals WHERE sim_run_id = v_run AND payload->>'reason' = 'automated_reassignment';

    IF p1 IS NOT NULL OR s1 <> 'available' OR a1 <> 0 THEN
      RAISE EXCEPTION '0547 V3 FAILED (a): the charger its car left for the service bay holds % (status %), % new approvals',
        p1, s1, a1;
    END IF;
    IF p2 IS DISTINCT FROM c2 THEN
      RAISE EXCEPTION '0547 V3 FAILED (b): the charger its car is charging on holds % (want %)', p2, c2;
    END IF;
    IF p3 IS DISTINCT FROM c3 THEN
      RAISE EXCEPTION '0547 V3 FAILED (c): the wash bay its car is in holds % (want %)', p3, c3;
    END IF;

    RAISE EXCEPTION '0547 V3 PASSED: (a) the charger a car had left for the service bay was emptied and the gate was not asked; (b) a car charging kept its charger (the gate asked % time(s)); (c) a car in the wash bay with its own pointer empty kept its bay', a2;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0547 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0547 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0547_pre' as it is.

COMMIT;
