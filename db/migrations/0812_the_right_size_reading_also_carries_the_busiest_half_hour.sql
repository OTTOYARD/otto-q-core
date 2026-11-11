-- migration-version: 20261111153741
-- migration-name:    the_right_size_reading_also_carries_the_busiest_half_hour
--
-- 0812  **The right-size reading also requires a unit to carry the busiest half hour, not only to stay cool.** (G538)
--
--   0810's ottoq_power_rightsize names the smallest standard size whose hot spot never passes 110 C on the measured day.
--   On the first production run it measured (54c0d20f, 2026-11-11, 1.76 sim-hours) it said TX-AUX's day "fits on 300 kVA"
--   when TX-AUX peaked at 1,230 kVA and carried 434 kVA through its busiest half hour: a transformer's oil takes about
--   three hours to warm, so on a short run, or under a short surge, the thermal test passes at a size no one would
--   install. Temperature is the limit over hours; over minutes a unit must still carry the load.
--   This file adds one condition: the size must be at or above the busiest full half hour (the peak itself where the run
--   holds no full half hour), and the reading says which figure it used. It is still a reading for a person and changes
--   no node (rules 10, 13).
--
--   One function, CREATE OR REPLACE of 0810's own, md5-guarded; nothing else reads it. forces_recert FALSE and
--   forces_dial_restart FALSE: it runs at a run's end, after every atom is written, and writes only
--   ottoq_power_node_study.rightsize.
BEGIN;

DO $p0$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_power_rightsize(uuid)'::regprocedure)
     IS DISTINCT FROM '1136d5f485f83b4fb6385b9ee24543d0' THEN
    RAISE EXCEPTION '0812 P0: ottoq_power_rightsize is not the body 0810 installed';
  END IF;
END $p0$;

CREATE OR REPLACE FUNCTION public.ottoq_power_rightsize(p_sim_run_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_tx record; v_t record; v_size numeric; v_out jsonb := '[]'::jsonb; v_sizes jsonb;
  v_top numeric; v_hsr numeric; v_step record; v_hot numeric; v_max numeric; v_age numeric; v_secs numeric;
  v_pick numeric; v_n integer; v_need numeric;
BEGIN
  FOR v_tx IN
    SELECT n.* FROM public.ottoq_power_nodes n
     WHERE n.kind = 'transformer'
       AND n.depot_id = (SELECT depot_id FROM public.ottoq_power_node_study WHERE sim_run_id = p_sim_run_id AND node_code = 'SERVICE')
     ORDER BY n.node_code
  LOOP
    v_sizes := '[]'::jsonb; v_pick := NULL;
    SELECT count(*) INTO v_n FROM public.ottoq_power_node_ticks WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code;
    IF v_n = 0 THEN CONTINUE; END IF;   -- the working rows are gone (purged); the stored reading stands
    -- 0812: what a unit must carry outright, whatever its temperature: the busiest full half hour (the peak itself on a
    -- run too short to hold one).
    SELECT COALESCE(st.peak_30min_kva, st.peak_kva) INTO v_need FROM public.ottoq_power_node_study st
     WHERE st.sim_run_id = p_sim_run_id AND st.node_code = v_tx.node_code;
    FOR v_size IN SELECT s FROM unnest(ARRAY[300, 500, 750, 1000, 1500, 2000, 2500, 3000, 3750]::numeric[]) s ORDER BY s
    LOOP
      v_top := NULL; v_hsr := NULL; v_max := NULL; v_age := 0; v_secs := 0;
      FOR v_t IN SELECT kva, dt_s, ambient_c FROM public.ottoq_power_node_ticks
                  WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code ORDER BY sim_clock_at, tick_id
      LOOP
        SELECT * INTO v_step FROM public.ottoq_power_thermal_step(v_t.kva / v_size, v_t.dt_s / 60.0, v_top, v_hsr,
          v_tx.top_oil_rise_rated_c, v_tx.hot_spot_rise_rated_c, v_tx.loss_ratio, v_tx.oil_tau_min, v_tx.winding_tau_min, v_tx.exp_n, v_tx.exp_m);
        v_top := v_step.top_oil_rise; v_hsr := v_step.hot_spot_rise;
        v_hot := v_t.ambient_c + v_top + v_hsr;
        v_max := GREATEST(v_max, v_hot);
        v_age := v_age + public.ottoq_power_aging_factor(v_hot) * v_t.dt_s; v_secs := v_secs + v_t.dt_s;
      END LOOP;
      v_sizes := v_sizes || jsonb_build_object('kva', v_size, 'max_hot_spot_c', round(v_max, 1),
        'aging_vs_normal', round(v_age / NULLIF(v_secs, 0), 4));
      IF v_pick IS NULL AND v_size >= COALESCE(v_need, 0) AND v_max <= 110 AND v_age / NULLIF(v_secs, 0) <= 1 THEN v_pick := v_size; END IF;
    END LOOP;
    UPDATE public.ottoq_power_node_study SET rightsize = jsonb_build_object(
        'installed_kva', v_tx.rated_kva, 'smallest_kva_this_day_fits', v_pick,
        'rule', 'carries the busiest full half hour, hot spot never over 110 C, and the day ages the insulation no faster than normal',
        'busiest_half_hour_kva', round(v_need, 1),
        'by_size', v_sizes, 'is', 'a reading of one run, for a person; it changes no node (rules 10, 13)')
     WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code;
    v_out := v_out || jsonb_build_object('node', v_tx.node_code, 'installed_kva', v_tx.rated_kva, 'smallest_kva_this_day_fits', v_pick);
  END LOOP;
  RETURN jsonb_build_object('sim_run_id', p_sim_run_id, 'transformers', v_out);
END $f$;

DO $v$
BEGIN
  IF position('v_size >= COALESCE(v_need, 0)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_power_rightsize(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0812 V1: the half-hour condition is not in the function';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_power_rightsize(uuid)', 'execute')
     OR has_function_privilege('authenticated', 'public.ottoq_power_rightsize(uuid)', 'execute')
     OR NOT has_function_privilege('service_role', 'public.ottoq_power_rightsize(uuid)', 'execute') THEN
    RAISE EXCEPTION '0812 V2: the reader''s grants moved';
  END IF;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0812_the_right_size_reading_also_carries_the_busiest_half_hour', false, false,
        'G538. ottoq_power_rightsize requires a size at or above the busiest full half hour as well as a hot spot under '
        '110 C. It runs at a run''s end and writes only ottoq_power_node_study.rightsize; no decision reads it.',
        now());

COMMIT;

-- APPLIED 2026-11-11: 15:37:41 UTC (9:37 AM CT), ledger 20261111153741, by Claude Code through the Management API's migrations
--   endpoint on Chase's instruction ("apply 0812"). The stored statement's md5 equals this file's as committed before this
--   header and footer changed (aefbff7e). The reader was then run again on production run 54c0d20f: TX-A2, TX-B1, TX-C1 and
--   TX-AUX read 500 kVA (their half hours 306, 352, 374 and 434 kVA); TX-A1, TX-B2 and TX-C2 read 300 (217, 293, 289).
