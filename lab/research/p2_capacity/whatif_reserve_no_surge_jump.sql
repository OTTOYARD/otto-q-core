-- What-if for a lab day only (capacity_day.py --lab-sql): the battery's reserve does not jump at a surge.
--
-- As production runs it, the battery may discharge only above a reserve of its own floor plus 20 points times the
-- "forecast uncertainty" (ottoq_energy_orchestrate's dispatch gate, ottoq_bess_day_plan's deliverable energy and
-- ottoq_bess_reserve_target alike). That uncertainty is ottoq_forecast_uncertainty: the variability of the last eight
-- snapshots (40 minutes) of EV charging, which is at its maximum at the start of every surge. So the reserve is 30%
-- exactly when the battery is needed, and a battery under 33% sits the surge out (measured on the lab's seed-424242
-- normal day: started at 25%, held back through the day's highest draw at 6:10 AM CT).
--
-- Here the uncertainty reads 0, so the reserve is the battery's own floor (10%) in all three places. It is the extreme
-- form of the fix (no hedge at all), measured to size what the jump costs; it changes nothing else.
CREATE OR REPLACE FUNCTION public.ottoq_forecast_uncertainty(p_sim_run_id uuid, p_depot_id uuid,
                                                             p_sim_clock timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$ SELECT 0::numeric $function$;
