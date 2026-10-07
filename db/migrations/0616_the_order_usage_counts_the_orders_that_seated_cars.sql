-- migration-version: PENDING
-- migration-name:    the_order_usage_counts_the_orders_that_seated_cars
--
-- 0616  **What the agent's orders did, counted by order.** `ottoq_agent_charge_order_usage` (0614) counts SEATS: how many
--       cars were seated by an order's rank, pinned, moved ahead. The twin draws one orb per agent PASS and colours it
--       green when that pass's order seated a car, so it needs the count in passes, and it needs it for the whole run:
--       the by_order list stops at 200 orders, and a four-hour demo run makes about 400. One key, `orders_seating`: the
--       orders that seated at least one car by their rank. Read-only; nothing on the tick path reads this function.
--
-- CHECKS. P0: nothing in flight. P1: the function is 0614's body (md5 of its source) and the key is not there yet. The
--   anchor matches once. V1: the key is in the answer, and on an unknown run it reads 0.
--   tests/test_agent_charge_order_sql.py counts it on seats it writes.
--
-- RECERT: FALSE/FALSE. No certification, sweep or dial pair reads this function, and no atom digests its answer.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0616_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0616_the_order_usage_counts_the_orders_that_seated_cars'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0616 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure)
     IS DISTINCT FROM '7584a178b82ebce6f4504e5197f928d4' THEN
    RAISE EXCEPTION '0616 P1: ottoq_agent_charge_order_usage is not 0614''s body (md5 7584a178); read it again';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0616_the_order_usage_counts_the_orders_that_seated_cars') THEN
    RAISE EXCEPTION '0616 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0616_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure;

DO $usage$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure);
  c_old := $old$    'seats_by_rank', (SELECT count(*) FROM t WHERE t.by_rank),
$old$;
  c_new := $new$    'seats_by_rank', (SELECT count(*) FROM t WHERE t.by_rank),
    -- 0616: the orders that seated at least one car by their rank: the agent passes the twin draws green
    'orders_seating', (SELECT count(DISTINCT t.order_id) FROM t WHERE t.by_rank),
$new$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0616 usage: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $usage$;

DO $v1$
DECLARE u jsonb;
BEGIN
  u := public.ottoq_agent_charge_order_usage('00000000-0000-4000-8000-000000000616', 5);
  IF NOT (u ? 'orders_seating') OR (u ->> 'orders_seating')::int <> 0 OR (u ->> 'orders')::int <> 0 THEN
    RAISE EXCEPTION '0616 V1: an unknown run answered %', u;
  END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0616_the_order_usage_counts_the_orders_that_seated_cars', false, false,
  'ottoq_agent_charge_order_usage gains orders_seating, the orders that seated at least one car by their rank. '
  'Read-only, off the tick path; FALSE/FALSE: no certification, sweep or dial pair reads it and no atom digests it.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
