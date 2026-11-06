-- lab/research/p2_capacity/whatif_force_dr_call.sql -- LAB ONLY (capacity_day.py --lab-sql). A demand-response call at the
-- first tick from 2:25 PM CT on every seed, the call the two hot seeds of the 0801 base days drew (717171 and 282828,
-- 2026-11-06): the twin's igniter (twin.ottoq_sim_maybe_ignite_dr_call) draws its roll, duration and reduction from a
-- seed keyed on the depot and the run's clock, not the run's seed, so every run draws the same call at the same moment
-- and only the afternoon's temperature decides whether it fires (32.4 and 33.0 C on those two; the other eight stayed
-- under 32). This forces the hazard to one at that tick and nothing else: the duration (192 min) and the reduction
-- (183.3 kW from the prior hour's mean grid draw) come from the same draws, so the call is the one a hot afternoon brings.
CREATE TEMP TABLE _force_patch (k int, c_old text, c_new text);
INSERT INTO _force_patch VALUES
(1, $o$  v_zero     CONSTANT uuid := '00000000-0000-0000-0000-000000000000';
$o$, $n$  v_zero     CONSTANT uuid := '00000000-0000-0000-0000-000000000000';
  v_force    boolean := false;   -- LAB what-if: the 2:25 PM call on every seed
$n$),
(2, $o$  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
$o$, $n$  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  IF (p_sim_clock_now AT TIME ZONE 'America/Chicago')::time >= time '14:25'
     AND (p_sim_clock_now AT TIME ZONE 'America/Chicago')::time < time '14:30'
     AND NOT EXISTS (SELECT 1 FROM ottoq_dr_calls c WHERE c.depot_id = p_depot_id
                       AND COALESCE(c.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)) THEN
    v_force := true;
    p_ambient_temp_c := GREATEST(p_ambient_temp_c, 32.0);   -- the call reads as a heat call, as on the hot seeds
  END IF;
$n$),
(3, $o$  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
$o$, $n$  IF v_force THEN v_prob := 1; END IF;
  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
$n$);

DO $force$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_maybe_ignite_dr_call(uuid,uuid,timestamp with time zone,numeric,bigint)'::regprocedure);
  FOR p IN SELECT * FROM _force_patch ORDER BY k LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION 'whatif_force_dr_call: anchor % matches % times, not 1', p.k, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
END $force$;

DROP TABLE _force_patch;
