-- G516 on a finished lab day: the visits whose arm routine (0764) a departure from the post cut short, and whether the
-- car was cleaned before it left. Run in a kept replica: psql -d ottoq_cap_<day> -f lab/research/p2_capacity/check_g516.sql
WITH r AS (SELECT sim_run_id AS run FROM ottoq_sim_runs WHERE run_by = 'ab_harness' ORDER BY started_at DESC LIMIT 1),
v AS (SELECT vn.visit_id, vn.vehicle_id, vn.atoms, o.departed_at
        FROM r JOIN ottoq_visit_needs vn ON vn.sim_run_id = r.run
        LEFT JOIN LATERAL (SELECT x.departed_at FROM public.ottoq_visit_outcomes(r.run) x WHERE x.visit_id = vn.visit_id) o ON true),
cut AS (SELECT v.*, (SELECT count(*) FROM jsonb_array_elements(v.atoms) a
                      WHERE a->>'svc' = 'interior_tidy' AND COALESCE((a->>'arm_routine')::boolean, false)
                        AND a->>'status' = 'cancelled'
                        AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(a->'interrupted', '[]'::jsonb)) i
                                     WHERE i->>'reason' = 'left_the_cabin_robot')) AS n_cut,
               EXISTS (SELECT 1 FROM jsonb_array_elements(v.atoms) a
                        WHERE a->>'svc' = 'interior_tidy' AND a->>'status' = 'done'
                          AND (v.departed_at IS NULL OR COALESCE((a->>'done_at')::timestamptz, (a->>'ends_at')::timestamptz)
                                                        <= v.departed_at)) AS cleaned
        FROM v)
SELECT count(*) FILTER (WHERE n_cut > 0) AS visits_cut_short,
       sum(n_cut) AS routines_cut_short,
       count(*) FILTER (WHERE n_cut > 0 AND cleaned) AS cleaned_before_leaving,
       count(*) FILTER (WHERE n_cut > 0 AND NOT cleaned AND departed_at IS NOT NULL) AS left_without_the_clean,
       count(*) FILTER (WHERE n_cut > 0 AND NOT cleaned AND departed_at IS NULL) AS still_in_the_depot
  FROM cut;
