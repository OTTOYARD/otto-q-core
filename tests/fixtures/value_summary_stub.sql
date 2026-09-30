-- What 0576's contract reads beyond the sweep stub: the depot's name, its battery's size and its solar (the twin's, as
-- built). The sweep stub already carries one battery row (its state of charge); this gives it the unit's size.
ALTER TABLE public.depots ADD COLUMN IF NOT EXISTS name text;
UPDATE public.depots SET name = 'OTTOYARD Nashville Flagship' WHERE id = '11111111-1111-1111-1111-111111111111';
ALTER TABLE public.ottoq_bess_units ADD COLUMN IF NOT EXISTS capacity_kwh numeric, ADD COLUMN IF NOT EXISTS max_discharge_kw numeric;
UPDATE public.ottoq_bess_units SET capacity_kwh = 3000, max_discharge_kw = 1500
 WHERE depot_id = '11111111-1111-1111-1111-111111111111';
CREATE TABLE IF NOT EXISTS public.ottoq_canopy_state (depot_id uuid, nameplate_ac_kw numeric);
INSERT INTO public.ottoq_canopy_state SELECT '11111111-1111-1111-1111-111111111111', 150 FROM generate_series(1, 4);
