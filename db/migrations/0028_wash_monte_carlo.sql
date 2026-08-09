-- MIGRATION: 0028_wash_monte_carlo.sql
-- Wire wash variables into seeded-random so each run draws fresh Monte Carlo values.

-- Helper: seeds wash_group and cycles_since_wash using the run's random seed.
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_wash_variables(
  p_depot_id uuid,
  p_seed bigint DEFAULT 42
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_seed BIGINT := COALESCE(p_seed, 42);
BEGIN
  UPDATE vehicles v
     SET config = jsonb_set(
                    jsonb_set(
                      COALESCE(v.config, '{}'::jsonb),
                      '{wash_group}',
                      to_jsonb(FLOOR(ottoq_sim_seeded_random(v_seed, 'wash_group:' || v.id::text) * 3)::int)
                    ),
                    '{cycles_since_wash}',
                    to_jsonb(CASE
                      WHEN ottoq_sim_seeded_random(v_seed, 'cyc:' || v.id::text) < 0.15
                        THEN FLOOR(ottoq_sim_seeded_random(v_seed, 'cyc_init:' || v.id::text) * 9)::int
                      WHEN ottoq_sim_seeded_random(v_seed, 'cyc:' || v.id::text) < 0.55
                        THEN (2 + FLOOR(ottoq_sim_seeded_random(v_seed, 'cyc_init:' || v.id::text) * 5))::int
                      ELSE 0
                    END)
                  )
   WHERE v.home_depot_id = p_depot_id
     AND v.category = 'autonomous';
END;
$fn$;
