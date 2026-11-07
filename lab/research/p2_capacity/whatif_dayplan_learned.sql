-- lab/research/p2_capacity/whatif_dayplan_learned.sql -- LAB ONLY, a what-if on one lab day's replica (capacity_day.py
-- --lab-sql, on a template carrying 0803 and its fitted models). The battery day plan's EV forecast from the learned forecast
-- (0803's ottoq_bess_learned_forecast) instead of its rule max(known, queue, last hour): the model's upper band for the next
-- 8 half hours, and the depot's learned day (EV, its mean by half hour of the day) beyond; the rule where the depot has no
-- day for a half hour. The model is the run-scoped dial bess_lab_forecast_model (a lab dial, no catalogue entry: the model
-- fitted without the day's own seed); 0 or absent leaves the day plan as it is. The question (2026-11-06): does the learned
-- forecast inside the day plan capture what the planner does with it ($226 a day on the six 36-hour days), or is the gain
-- the planner's? G524's forecast fix inside the day plan moved nothing (-$1.23 a day).
DO $whatif$
DECLARE
  c_decl_old text := $a$  v_dr_lead numeric;   /* 0797 */$a$;
  c_decl_new text := $a$  v_dr_lead numeric;   /* 0797 */
  v_lf jsonb; v_lfm bigint;   /* lab what-if: the learned forecast */$a$;
  c_old text := $a$  END LOOP;
  IF p_net_load_now_kw IS NOT NULL THEN v_net[1] := GREATEST(0, p_net_load_now_kw); END IF;$a$;
  c_new text := $a$  END LOOP;
  -- lab what-if (whatif_dayplan_learned.sql): the EV term from the learned forecast (0803), its upper band for the next
  -- 8 half hours and the depot's learned day (EV, mean) beyond; the rule where the depot has no day for a half hour
  v_lfm := NULLIF(ottoq_policy_get(p_sim_run_id, 'bess_lab_forecast_model', 0), 0)::bigint;
  IF v_lfm IS NOT NULL THEN
    v_lf := public.ottoq_bess_learned_forecast(p_sim_run_id, p_depot_id, p_sim_clock,
              jsonb_build_object('ok', true, 'ev_persist_kw', round(v_ev_persist, 1), 'forecast', jsonb_build_object(
                'ev_known_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_known) WITH ORDINALITY AS u(x, o)),
                'ev_queue_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_queue) WITH ORDINALITY AS u(x, o)),
                'base_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_base) WITH ORDINALITY AS u(x, o)),
                'solar_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_solar) WITH ORDINALITY AS u(x, o)))),
              v_lfm);
    IF v_lf IS NOT NULL THEN
      FOR k IN 1..v_n LOOP
        v_ev[k] := CASE WHEN k <= 8 THEN (v_lf->'ev_upper_kw'->>(k - 1))::numeric
                        ELSE COALESCE((v_lf->'profile'->((k - 1) % 48)->>'ev_mean_kw')::numeric, v_ev[k]) END;
        v_net[k] := GREATEST(0, v_base[k] + v_ev[k] - v_solar[k]);
      END LOOP;
    END IF;
  END IF;
  IF p_net_load_now_kw IS NOT NULL THEN v_net[1] := GREATEST(0, p_net_load_now_kw); END IF;$a$;
  v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamptz,numeric)'::regprocedure);
  FOR n IN SELECT (length(v_def) - length(replace(v_def, x, ''))) / length(x) FROM unnest(ARRAY[c_decl_old, c_old]) x LOOP
    IF n <> 1 THEN
      RAISE EXCEPTION 'whatif_dayplan_learned: an anchor matches % times, not 1', n;
    END IF;
  END LOOP;
  v_def := replace(replace(v_def, c_decl_old, c_decl_new), c_old, c_new);
  EXECUTE v_def;
END $whatif$;
