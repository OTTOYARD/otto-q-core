-- ---------------------------------------------------------------------------
-- schedule-round.sql — lay out one certification round's six cron slots from
-- the durations the harness has actually been recording, not from a guess.
--
-- WHY THIS EXISTS. Round 25 was hand-scheduled at 16 minutes for 12-tick pairs
-- and 26 for 24-tick, from measurements taken when a 12-tick pair ran 812 s.
-- Pair e (24 ticks) then ran 1,300 s and was still holding the flagship depot
-- at 09:53 with pair f due at 10:00. Two pairs on one depot contaminate both,
-- so f and g had to be pushed by hand mid-round. The spacing was not wrong when
-- it was written; it was stale by the time it fired, because the pair keeps
-- getting slower (task G19).
--
-- So the slots are derived, every round, from the SLOWEST run of that tick
-- count in the recent past, plus a margin. Edit the three constants, run it,
-- read the plan it prints, then run it again with v_commit := true.
--
-- Durations come from cron.job_run_details. Note the trap recorded in
-- db/canons/round25.md: an IN-FLIGHT job of this shape reports
-- status='succeeded', return_message='SET', duration ~1 s, because the command
-- is two statements and the row reflects the first until the job ends. Rows
-- under 60 s are therefore discarded as in-flight artefacts rather than trusted
-- as fast pairs.
-- ---------------------------------------------------------------------------

DO $round$
DECLARE
  ---------------------------------------------------------------- constants --
  v_round      int         := 26;          -- round number; jobs are named r<N>_<letter>_...
  v_first_fire timestamptz := NULL;        -- NULL = now() + v_lead
  v_lead       interval    := '10 min';    -- gap before the first pair fires
  v_margin     numeric     := 1.35;        -- slot = slowest recent run x this
  v_floor_min  int         := 14;          -- never space closer than this
  v_commit     boolean     := false;       -- false = print the plan only
  v_depot      uuid        := '11111111-1111-1111-1111-111111111111';
  v_sim_start  timestamptz := '2026-09-01 02:00:00+00';
  v_budget     int         := 900;
  ------------------------------------------------------------------- working --
  v_cols       text[][]    := ARRAY[
                   ARRAY['a','busy_day',  '314159','12'],
                   ARRAY['b','busy_day',  '171717','12'],
                   ARRAY['c','normal_day','171717','12'],
                   ARRAY['d','busy_day',  '424242','12'],
                   ARRAY['e','busy_day',  '171717','24'],
                   ARRAY['f','busy_day',  '424242','24']];
  i int; v_fire timestamptz; v_slot int; v_secs numeric; v_name text; v_cmd text; v_sched text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ ('^r'||v_round||'_')) THEN
    RAISE EXCEPTION 'schedule-round: round % already has jobs; unschedule them first', v_round;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active'
                AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION 'schedule-round: a pair is running right now — pg_stat_activity, not the '
                    'cron log, is the authority on that';
  END IF;

  v_fire := COALESCE(v_first_fire, now() + v_lead);

  FOR i IN 1 .. array_length(v_cols, 1) LOOP
    -- slowest COMPLETED run of this tick count in the last five days; rows
    -- under 60 s are in-flight artefacts (see the header), not fast pairs.
    SELECT max(extract(epoch FROM (d.end_time - d.start_time))) INTO v_secs
      FROM cron.job_run_details d
     WHERE d.command ILIKE '%ottoq_determinism_pair%'
       AND d.command ILIKE '%, '||v_cols[i][4]||', %'
       AND d.start_time > now() - interval '5 days'
       AND extract(epoch FROM (d.end_time - d.start_time)) >= 60;

    IF v_secs IS NULL THEN
      RAISE WARNING 'schedule-round: no measured duration for %-tick pairs in the last five '
                    'days; falling back to 30 min', v_cols[i][4];
      v_secs := 1800;
    END IF;

    v_slot := GREATEST(v_floor_min, ceil(v_secs * v_margin / 60.0)::int);
    v_fire := date_trunc('minute', v_fire);

    IF v_fire <= now() THEN
      RAISE EXCEPTION 'schedule-round: slot % would fire at % which is not in the future (now %)',
                      v_cols[i][1], v_fire, now();
    END IF;

    v_name  := format('r%s_%s_%s_%s_%s', v_round, v_cols[i][1],
                      replace(v_cols[i][2],'_day',''), v_cols[i][3], v_cols[i][4]);
    v_sched := format('%s %s %s %s *',
                      to_char(v_fire,'MI'), to_char(v_fire,'HH24'),
                      to_char(v_fire,'DD'),  to_char(v_fire,'MM'));
    v_cmd   := format($c$SET statement_timeout TO '25min'; SELECT public.ottoq_determinism_pair(%s, %s, %L, %L::uuid, %L::timestamptz, %s);$c$,
                      v_cols[i][3], v_cols[i][4], v_cols[i][2], v_depot, v_sim_start, v_budget);

    -- one % per argument: RAISE has no %s, and a stray one silently eats an
    -- argument and prints a literal 's'.
    RAISE NOTICE '% | fires % UTC | slot % min (slowest recent %-tick run % s x %)',
                 rpad(v_name, 32), to_char(v_fire,'YYYY-MM-DD HH24:MI'), v_slot,
                 v_cols[i][4], round(v_secs), v_margin;

    IF v_commit THEN
      PERFORM cron.schedule(v_name, v_sched, v_cmd);
    END IF;

    v_fire := v_fire + make_interval(mins => v_slot);
  END LOOP;

  IF v_commit THEN
    RAISE NOTICE 'schedule-round: round % scheduled. Verify with the query below.', v_round;
  ELSE
    RAISE NOTICE 'schedule-round: PLAN ONLY. Set v_commit := true to write the jobs.';
  END IF;
END $round$;

-- Verify what landed, and re-assert every slot is still in the future. Run this
-- after committing; a slot in the past is a slot that will never fire.
SELECT jobname, schedule, active,
       (date_trunc('day', now())
        + make_interval(hours => split_part(schedule,' ',2)::int,
                        mins  => split_part(schedule,' ',1)::int)) AS fire_utc,
       (date_trunc('day', now())
        + make_interval(hours => split_part(schedule,' ',2)::int,
                        mins  => split_part(schedule,' ',1)::int)) > now() AS in_future
FROM cron.job
WHERE jobname ~ '^r[0-9]+_'
ORDER BY fire_utc;
