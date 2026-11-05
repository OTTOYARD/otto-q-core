-- lab/research/p1_referee_owner_futures/futures.sql -- run in the LAB (never production), after
-- lab/research/p0_referee_per_owner/replay.sql. Usage: psql -v worker=0 -v workers=4 -f futures.sql (one per core).
-- For each decision of the replay set and each of the futures the referee rolled (0 = the expected future, 1..11
-- sampled, common random numbers from the decision's seed: ottoq_charge_line_rollout), the depot's verdict and each
-- owner's verdict on its own cars (ottoq_charge_line_compare, the engine's yardstick), with each car's owner in the
-- state exactly as replay.sql adds it (as ottoq_charge_line_state does since 0784). Nothing is decided here: it is the
-- raw material for comparing candidate referee rules (rules.sql).
-- The table is created once, before the workers start (concurrent CREATE ... IF NOT EXISTS races on the catalog):
--   CREATE TABLE IF NOT EXISTS research.referee_owner_futures (order_id bigint NOT NULL, s int NOT NULL,
--     depot_cmp int NOT NULL, owner text NOT NULL, owner_cmp int NOT NULL, PRIMARY KEY (order_id, s, owner));
\set ON_ERROR_STOP on
DELETE FROM research.referee_owner_futures WHERE order_id % :workers = :worker;
INSERT INTO research.referee_owner_futures (order_id, s, depot_cmp, owner, owner_cmp)
WITH own AS (
  SELECT COALESCE(jsonb_object_agg(ov.id::text, ov.fleet_operator_id), '{}'::jsonb) AS owners
    FROM public.vehicles ov
   WHERE ov.home_depot_id = '11111111-1111-1111-1111-111111111111' AND ov.category = 'autonomous'
), d AS (
  SELECT s.order_id, s.seed, s.futures, s.agent_order,
         CASE WHEN COALESCE((s.state ->> 'owner_guard')::boolean, false) THEN s.state
              ELSE s.state || jsonb_build_object('owner_guard', true)
                           || CASE WHEN s.state ? 'owners' THEN '{}'::jsonb ELSE jsonb_build_object('owners', own.owners) END
         END AS state_o
    FROM research.ottoq_charge_order_snapshots s, own
   WHERE s.order_id % :workers = :worker
)
SELECT d.order_id, f.s, (public.ottoq_charge_line_compare(x.k, x.a) ->> 'cmp')::int, o.owner,
       (public.ottoq_charge_line_compare(x.k -> 'by_owner' -> o.owner, x.a -> 'by_owner' -> o.owner) ->> 'cmp')::int
  FROM d
  CROSS JOIN LATERAL generate_series(0, d.futures - 1) f(s)
  CROSS JOIN LATERAL (SELECT public.ottoq_charge_line_simulate(d.state_o, NULL, f.s, d.seed) AS k,
                             public.ottoq_charge_line_simulate(d.state_o, d.agent_order, f.s, d.seed) AS a) x
  CROSS JOIN LATERAL (SELECT jsonb_object_keys(x.k -> 'by_owner') UNION SELECT jsonb_object_keys(x.a -> 'by_owner')) o(owner);
