-- migration-version: PENDING
-- migration-name:    when_every_post_is_taken_a_car_takes_a_free_bay_first
--
-- 0782  **When every post is taken, a car that owes bay work and whose energy is not critical takes a free bay first and
--       charges after, so the service bays stop standing empty while the line waits for posts.** (G502)
--       Chase, 2026-10-24: "Go find an edge and build." Rule 9 allows queueing and names better ordering of who is
--       served next: nothing here shortens a charge, skips a service, or lets a car leave before it is full.
--
-- ══ §1 WHY, MEASURED (read-only; db/checks/0470 §4 and query (1) below) ═══════════════════════════════════════════════
--
--   Decide section (4b) seats a car in a bay only once it owes no charge ("CHARGE FIRST", the anchor leg), with one
--   exception from 0003: a car that owes interrupted bay work, whose energy is not critical, when no charger is free
--   right now. That doctrine was right when the posts were the wall. At 30 posts the wall is the two service bays
--   (0470 §1), and on 78c0624c they had no candidate at all for 53.7 bay-minutes (13:00-13:24:54 on one bay,
--   13:00-13:14:52 and 15:00:18-15:14:10 on the other) while every post was taken (0470 §4).
--   On each of the three busy days the 30-post depot has run, 2 to 3 of the cars there at the boot owed service-bay
--   work, were above their contract's 80% floor, and waited 15 minutes or more for a post (78c0624c 2 of 64 visits,
--   67290d0a 3 of 61, 3389e651 2 of 34; query (1), read at 18:20:43 UTC, 1:20 PM CT). Those are the cars this lets
--   into an empty bay: about one service job a day on this scenario, at the wall, out of 19 to 21 done.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) A dial, a person's (rule 10): bay_open_shop (0..1, default 0).
--   (b) ottoq_decide_tick, section (4b): the 0003 exception's first clause reads "the car owes interrupted bay work, or
--       bay_open_shop is 1". Its other two clauses are untouched: the car's energy is not 'critical' (the needs card's
--       grade: below its contract's deployment floor with less time to its deploy than its charge takes), and no
--       charger at the depot is free right now (section (3) has already run this tick; had a post been free the car
--       would be on it). The dial is read once per tick, before the bays are counted.
--   (c) A seat (4b) makes for a car that still owes a charge records bay_before_charge: true on its decision, with the
--       dial at 1 only (ottoq.ottoq_vehicle_owes_charge_now, 0780's helper).
--   Not changed: the forward calendar (the early activation still waits for a car that owes a charge, 0780, and the
--   reconcile still releases its hold), the charge line and its order, how full a car charges (rule 9: it charges
--   after, to its one target, and the departure test, 0543, holds it until then), and every other door to a bay.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0780 is applied (its helper is read); the decide tick is either the live
--   body of 2026-10-24 or the one 0781 leaves (md5); nothing this file creates exists. Pre-image under '0782_pre'. Each
--   anchor matches once. V1 the decide tick less its four replacements is the pre-image P1 read. V2 the dial is
--   catalogued 0..1, default 0, not agent-writable. The predicate itself is executed, both ways, by
--   tests/test_bay_open_shop_sql.py on the miniature depot with the live decide tick.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: at the default the exception reads exactly as before and no
--   decision row gains a field. Rule 12 has the switch go on at depot scope under the deciding person's name, with one
--   demo run to show it working.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0782_pre';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_open_shop' (and its policy rows);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0782_when_every_post_is_taken_a_car_takes_a_free_bay_first'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0782 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0782 P0: a run is running; its decide tick would change mid-run. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0780 applied; the decide tick is a body this file was written against; nothing of this file ──
CREATE TEMP TABLE _0782_pre ON COMMIT DROP AS
SELECT md5(prosrc) AS pre FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_decide_tick(uuid)');

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0782_when_every_post_is_taken_a_car_takes_a_free_bay_first') THEN
    RAISE EXCEPTION '0782 P1: already applied';
  END IF;
  IF to_regprocedure('ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION '0782 P1: 0780 is not applied (ottoq.ottoq_vehicle_owes_charge_now); apply it first';
  END IF;
  IF (SELECT pre FROM _0782_pre) IS DISTINCT FROM '2b3d0cbf5cdb13ca24f0de788073dc46'      -- live, 2026-10-24
     AND (SELECT pre FROM _0782_pre) IS DISTINCT FROM '30f727c4086cff7afa712145b4c38474' THEN -- after 0781
    RAISE EXCEPTION '0782 P1: the decide tick is not a body this file patches (md5 %)', left((SELECT pre FROM _0782_pre), 8);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_open_shop') THEN
    RAISE EXCEPTION '0782 P1: the dial already exists';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0782_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_open_shop',
        '0782 (G502): 1 = decide section (4b) seats in a free bay a car that still owes a charge, when its energy is not '
        'critical (the needs card''s grade) and no charger at the depot is free right now; it charges after, to its one '
        'target, and the departure test holds it until it is full (rule 9). 0 = only a car owing interrupted bay work '
        '(0003). A person''s dial, never the agent''s (rule 10).',
        0, 0, 1, 'public.ottoq_decide_tick (section 4b)', false);

-- ── (b) and (c): the anchored replacements ──
CREATE TEMP TABLE _0782_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0782_patch VALUES
  -- b1: the variable
  (1,
   $o1$  v_ok jsonb := '{}'::jsonb;                                                                                     /* 0642 */
$o1$,
   $n1$  v_ok jsonb := '{}'::jsonb;                                                                                     /* 0642 */
  v_open_shop boolean := false;                                                                     /* 0782 (G502) */
$n1$),
  -- b2: read once per tick, before the bays are counted
  (2,
   $o2$  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
$o2$,
   $n2$  -- 0782 (G502): with bay_open_shop, the 0003 exception below admits any car, not only one owed interrupted bay work
  v_open_shop := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_open_shop', 0), 0) >= 1;
  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
$n2$),
  -- b3: the exception's first clause
  (3,
   $o3$                   OR ( COALESCE(c.rebook_owed, false)
$o3$,
   $n3$                   OR ( (COALESCE(c.rebook_owed, false) OR v_open_shop)   /* 0782 (G502): any car, with bay_open_shop */
$n3$),
  -- c1: the seat says when it was made before the car's charge
  (4,
   $o4$                         ELSE jsonb_build_object('uptime_key', to_jsonb(v_need.upf_key)) END;   -- 0747
$o4$,
   $n4$                         ELSE jsonb_build_object('uptime_key', to_jsonb(v_need.upf_key)) END   -- 0747
                 || CASE WHEN v_open_shop AND ottoq.ottoq_vehicle_owes_charge_now(v_need.vehicle_id, v_clock)
                         THEN jsonb_build_object('bay_before_charge', true) ELSE '{}'::jsonb END;   -- 0782 (G502)
$n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0782_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0782: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0782: the decide tick is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the decide tick less its replacements is the pre-image P1 read ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0782_patch ORDER BY seq DESC LOOP
    IF strpos(v_body, p.c_new) = 0 THEN
      RAISE EXCEPTION '0782 V1: the decide tick does not carry replacement %', p.seq;
    END IF;
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM (SELECT pre FROM _0782_pre) THEN
    RAISE EXCEPTION '0782 V1: the decide tick less its replacements is not its pre-image (md5 %)', md5(v_body);
  END IF;
  RAISE NOTICE '0782 V1: the decide tick less its four replacements is its pre-image (%)', left((SELECT pre FROM _0782_pre), 8);
END $v1$;

-- ── V2: the dial ──
DO $v2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_open_shop' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0782 V2: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0782_when_every_post_is_taken_a_car_takes_a_free_bay_first', false, false,
        'Dial bay_open_shop (default 0); four anchored replacements in public.ottoq_decide_tick (section 4b): the 0003 '
        'exception admits any car whose energy is not critical when no charger is free, and the seat records '
        'bay_before_charge, both only at 1 (V1: the body less its replacements is its pre-image). No certification arm, '
        'canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- (1) the boot's candidates, per run: visits there in the first five minutes owing service-bay work, above their
--     contract's floor at arrival, and not on a post within 15 minutes of the boot
-- WITH runs(r) AS (VALUES ('78c0624c-ff52-4594-8e54-9da254d4d867'::uuid), ('67290d0a-b527-4240-8dac-07eaf64c5d02'::uuid),
--                         ('3389e651-6a4f-4267-a6f0-56d3a262bd92'::uuid)),
-- v AS (
--   SELECT vn.sim_run_id, vn.vehicle_id, vn.arrived_at, (vn.meta->>'soc_at_arrival')::numeric soc,
--          (vn.meta->>'sla_floor')::numeric floor_,
--          EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'requires_bay' = 'service_bay') svc,
--          (SELECT min(o.started_at) FROM ocpp_sessions o WHERE o.sim_run_id = vn.sim_run_id
--             AND o.vehicle_id = vn.vehicle_id AND o.started_at >= vn.arrived_at - interval '1 minute') first_chg
--     FROM ottoq_visit_needs vn JOIN runs ON runs.r = vn.sim_run_id)
-- SELECT left(sim_run_id::text, 8) run,
--        count(*) FILTER (WHERE arrived_at <= r0.s + interval '5 minutes') boot_visits,
--        count(*) FILTER (WHERE arrived_at <= r0.s + interval '5 minutes' AND svc AND soc >= floor_
--                           AND (first_chg IS NULL OR first_chg > r0.s + interval '15 minutes')) candidates
--   FROM v CROSS JOIN LATERAL (SELECT sim_clock_start s FROM ottoq_sim_runs WHERE sim_run_id = v.sim_run_id) r0
--  GROUP BY 1, r0.s ORDER BY 1;
