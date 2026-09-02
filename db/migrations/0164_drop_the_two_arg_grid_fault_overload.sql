-- 0164  Drop the two-argument grid_fault overload. Harness; forces_recert = false.
--
-- 0163 added p_duration_minutes with a DEFAULT, which in Postgres creates a NEW
-- function rather than replacing the old one, leaving both
-- twin.ottoq_grid_fault(text,text) and (text,text,int) callable - so a
-- two-argument call resolves to neither ("function is not unique").
--
-- The same latent trap already exists elsewhere: public.ottoq_depot_current_demand_kw
-- has both a 1-arg and a 2-arg-with-default form, so any single-argument call to it
-- fails the same way. Recorded rather than changed, since EN.001 and 0156 both call
-- the two-argument form and nothing calls the one-argument form.
DROP FUNCTION IF EXISTS twin.ottoq_grid_fault(text, text);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('drop_the_two_arg_grid_fault_overload', false,
        'Harness: 0163''s defaulted parameter created a second overload of twin.ottoq_grid_fault, making two-argument calls ambiguous. Stale signature dropped.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
