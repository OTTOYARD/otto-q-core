-- migration-version: 20261007202316
-- migration-name:    a_car_named_for_the_kind_not_free_waits_behind_the_cars_not_named
--
-- 0617  **Under the agent's charge order, a car named for the kind of charger that is not free waits behind the cars the
--       order did not name, instead of taking the only kind free.** One function, `ottoq_agent_charge_order_key`, whose
--       answer for a car the order does not name changes from NULL to 500. Every reader of the key (the charge cursor,
--       the cockpits' queue, the planners' batch) sorts it after the agent's key, so the line becomes: the cars named
--       for a kind free now, in the agent's order; then the cars not named, in the kernel's own order; then the cars
--       named for the other kind. Immediate dispatch and the 90-minute pin still go first, as 0614 built them.
--
-- ══ §1 WHY (run 0bbdcc07, the first run under an agent order, measured 2026-10-07 ~2:05 PM CT) ══════════════════════
--
--   Of the 19 cars seated by the agent's rank by sim 13:36, 7 were cars the agent named for a fast charger that took an
--   L2 on a tick when only L2s were free. 0614's key put such a car (rank + 1000) ahead of every car the order did not
--   name (NULL, NULLS LAST), so when the agent's L2 cars were seated the next free L2 went to a car it had named for a
--   fast charger. That is FINDINGS G315's pattern, a low battery on L2 for hours, made by the agent's own order: its
--   reason on order 25 read "DCFC reserved for Waymo-AV-038 (32% SoC, 72 min DCFC) when DCFC frees in 2 min".
--   CLAUDE.md rule 9 names the lever: "better ordering of who is served next". A car still takes the other kind when
--   no other car waits for it, so no charger idles, and the pin bounds the wait.
--
-- ══ §2 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the key is 0614's body (md5 of its source); no lineage row. V1: the truth table: named for
--   a free kind = its rank; not named = 500; named for the other kind = rank + 1000; no order or no car = NULL; a rank
--   that is not a whole number = 999. tests/test_agent_charge_order_sql.py runs the line before and after on stubs.
--
-- ══ §3 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. Every reader evaluates the key only under a live order (CASE WHEN v_ao_on ...), and orders exist only
--   on operator_demo runs (0615); no certification, sweep or dial pair runs one.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0617_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0617_a_car_named_for_the_kind_not_free_waits_behind_the_cars_not_named'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0617 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_charge_order_key(jsonb,uuid,text)'::regprocedure)
     IS DISTINCT FROM '0f79713ad05723330b0391437d118696' THEN
    RAISE EXCEPTION '0617 P1: ottoq_agent_charge_order_key is not 0614''s body (md5 0f79713a); read it again';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0617_a_car_named_for_the_kind_not_free_waits_behind_the_cars_not_named') THEN
    RAISE EXCEPTION '0617 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0617_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_charge_order_key(jsonb,uuid,text)'::regprocedure;

CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_key(p_order jsonb, p_vehicle_id uuid, p_mode text)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0614, 0617: the car's place in the agent's charge order, for the cursor's ORDER BY (read only under a live order).
  -- A car the order names for a kind of charger free now (or for either): its rank. A car the order does not name: 500,
  -- so the kernel's own keys order those cars among themselves. A car named for the other kind than the only kind free
  -- now: its rank plus 1000, behind every car not named, so it waits for its kind while another car takes this one, and
  -- still takes it when no other car waits. NULL with no order or no car. Total: a rank that is not a whole number
  -- reads as 999.
  SELECT CASE
           WHEN p_order IS NULL OR p_vehicle_id IS NULL THEN NULL
           WHEN NOT (p_order ? p_vehicle_id::text) THEN 500
           ELSE CASE WHEN (p_order -> p_vehicle_id::text ->> 'rank') ~ '^[0-9]{1,6}$'
                     THEN (p_order -> p_vehicle_id::text ->> 'rank')::int ELSE 999 END
                + CASE WHEN p_mode = 'dcfc' AND p_order -> p_vehicle_id::text ->> 'kind' = 'l2'   THEN 1000
                       WHEN p_mode = 'l2'   AND p_order -> p_vehicle_id::text ->> 'kind' = 'dcfc' THEN 1000
                       ELSE 0 END
         END
$fn$;

DO $v1$
DECLARE a uuid := 'aaaaaaaa-0000-4000-8000-000000000001'; b uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  c uuid := 'aaaaaaaa-0000-4000-8000-000000000003'; o jsonb;
BEGIN
  o := jsonb_build_object(a::text, jsonb_build_object('rank', 2, 'kind', 'l2'),
                          b::text, jsonb_build_object('rank', 5, 'kind', 'dcfc'));
  IF public.ottoq_agent_charge_order_key(o, a, 'l2') IS DISTINCT FROM 2
     OR public.ottoq_agent_charge_order_key(o, a, 'both') IS DISTINCT FROM 2
     OR public.ottoq_agent_charge_order_key(o, a, 'dcfc') IS DISTINCT FROM 1002
     OR public.ottoq_agent_charge_order_key(o, b, 'dcfc') IS DISTINCT FROM 5
     OR public.ottoq_agent_charge_order_key(o, b, 'l2') IS DISTINCT FROM 1005
     OR public.ottoq_agent_charge_order_key(o, c, 'dcfc') IS DISTINCT FROM 500
     OR public.ottoq_agent_charge_order_key(o, c, 'both') IS DISTINCT FROM 500
     OR public.ottoq_agent_charge_order_key(NULL, a, 'dcfc') IS NOT NULL
     OR public.ottoq_agent_charge_order_key(o, NULL, 'dcfc') IS NOT NULL
     OR public.ottoq_agent_charge_order_key(jsonb_build_object(a::text, jsonb_build_object('rank', 'x')), a, 'none') IS DISTINCT FROM 999 THEN
    RAISE EXCEPTION '0617 V1: the key''s truth table is wrong';
  END IF;
  -- the ordering the change exists for: named for a free kind < not named < named for the other kind
  IF NOT (public.ottoq_agent_charge_order_key(o, a, 'l2') < public.ottoq_agent_charge_order_key(o, c, 'l2')
          AND public.ottoq_agent_charge_order_key(o, c, 'l2') < public.ottoq_agent_charge_order_key(o, b, 'l2')) THEN
    RAISE EXCEPTION '0617 V1: a car not named does not sort between the free kind and the other kind';
  END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0617_a_car_named_for_the_kind_not_free_waits_behind_the_cars_not_named', false, false,
  'ottoq_agent_charge_order_key reads 500 for a car the agent''s order does not name (was NULL), so under a live order a '
  'car named for the kind of charger not free sorts behind the cars not named. FALSE/FALSE: the key is read only under a '
  'live order, and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
