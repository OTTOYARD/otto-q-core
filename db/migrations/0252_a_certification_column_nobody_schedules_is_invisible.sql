-- migration-version: PENDING
-- migration-name: 0252_a_certification_column_nobody_schedules_is_invisible
-- ===========================================================================
-- 0252  A CERTIFICATION COLUMN NOBODY SCHEDULES IS INVISIBLE
-- ===========================================================================
-- probe:          db/checks/0167; BUILD_QUEUE P0 #1 and P0 #3
-- forces_recert:  FALSE
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority.
--
-- WHAT WENT WRONG, AND IT WAS NOT A MISSING MEASUREMENT
--
-- For most of 2026-09-09 I said "the flagship matrix is green" and it was six of
-- seven. busy_day/171717/48t had not been paired since 2026-09-04 18:20 --
-- measured at 14:15 UTC today, 115.9 hours -- sitting below the recert floor with
-- a history that predates four fingerprint migrations.
--
-- ottoq_cert_matrix KNEW. It computes `stale` and returned stale=true for that
-- column in every query I ran. The flag was correct, present, and read by
-- nothing -- including me, until I wrote "six of seven" into a canon file and
-- only then noticed what I had been saying for hours.
--
-- So the defect is not a blind instrument. It is an instrument whose output no
-- process consumes. That is the same shape as G23 (ottoq_purge_prior_runs
-- existed, was correct, and nothing scheduled it) and as the six assertion
-- functions 0167 found that nothing ever calls. THE REPEATED PATTERN IN THIS
-- CODEBASE IS NOT ABSENT MACHINERY. IT IS CORRECT MACHINERY WITH NO CALLER.
--
-- WHY A REGISTRY, AND NOT JUST AN ALERT ON `stale`
--
-- ottoq_cert_matrix derives its columns FROM HISTORY: it groups the pairs that
-- have run. A column that has never run does not appear at all, and a column
-- deliberately dropped from the rotation looks identical to one forgotten. An
-- alert on that view can only ever say "something you already do is old"; it can
-- never say "something you intended to do is missing."
--
-- The registry inverts it, exactly as 0250's allow-list inverted the purge:
-- state the columns the certification is SUPPOSED to cover, then compare
-- intention against reality. A column that is registered and never run reads
-- MISSING -- the loudest state, not the quietest.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. What the certification is supposed to cover.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_cert_columns (
  depot_id   uuid    NOT NULL,
  scenario   text    NOT NULL,
  seed       bigint  NOT NULL,
  ticks      int     NOT NULL,
  max_age    interval NOT NULL,
  enabled    boolean NOT NULL DEFAULT true,
  note       text    NOT NULL,
  added_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (depot_id, scenario, seed, ticks)
);

COMMENT ON TABLE public.ottoq_cert_columns IS
  '0252: the columns the certification is SUPPOSED to cover, declared rather '
  'than inferred. ottoq_cert_matrix derives its columns from history, so a column '
  'that has never run is invisible to it and a column dropped from the rotation '
  'looks the same as one forgotten. max_age is the cadence the column is expected '
  'to hold; exceeding it is OVERDUE and never running at all is MISSING. Set '
  'enabled=false to retire a column deliberately -- that is a decision with a '
  'note, which is the point.';

INSERT INTO public.ottoq_cert_columns (depot_id, scenario, seed, ticks, max_age, note) VALUES
  ('11111111-1111-1111-1111-111111111111','busy_day',  314159,12,'6 hours',
   'Flagship rotation. Fastest column; first to show a boot-state defect.'),
  ('11111111-1111-1111-1111-111111111111','busy_day',  171717,12,'6 hours',
   'Flagship rotation.'),
  ('11111111-1111-1111-1111-111111111111','normal_day',171717,12,'6 hours',
   'Flagship rotation. The only non-busy scenario -- 0134''s energy-path carrier '
   'appeared here and nowhere else, so dropping it would hide a whole class.'),
  ('11111111-1111-1111-1111-111111111111','busy_day',  424242,12,'6 hours',
   'Flagship rotation.'),
  ('11111111-1111-1111-1111-111111111111','busy_day',  171717,24,'6 hours',
   'Flagship rotation. 0130''s deferral coin surfaced at this horizon.'),
  ('11111111-1111-1111-1111-111111111111','busy_day',  424242,24,'6 hours',
   'Flagship rotation.'),
  ('11111111-1111-1111-1111-111111111111','busy_day',  171717,48,'24 hours',
   'THE COLUMN THIS MIGRATION EXISTS FOR. Longest horizon; 0108 and 0193 both '
   'broke here first, which is exactly why it must not be the one that quietly '
   'stops running. A wider max_age than the 12/24t columns because a 48t pair '
   'costs ~2x -- wider, not absent.'),
  ('aacd0bb0-2d02-d101-72cc-33f70e950bc8','grid_smoke',239001,6,'24 hours',
   'Grid fixture (0153). Seconds per pair, and the only column that exercises the '
   '0132 site power gate under a tight cap.'),
  ('aacd0bb0-2d02-d101-72cc-33f70e950bc8','grid_smoke',424242,6,'24 hours',
   'Grid fixture, second seed.')
ON CONFLICT (depot_id, scenario, seed, ticks) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Intention vs reality, in one call.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cert_coverage()
RETURNS TABLE (
  status      text,
  depot_id    uuid,
  scenario    text,
  seed        bigint,
  ticks       int,
  last_pair   timestamptz,
  age         interval,
  max_age     interval,
  registered  boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $function$
  WITH seen AS (
    SELECT r.depot_id,
           (r.validation_notes::jsonb->>'scenario')      AS scenario,
           (r.validation_notes::jsonb->>'seed')::bigint  AS seed,
           (r.validation_notes::jsonb->>'ticks')::int    AS ticks,
           max(r.started_at)                             AS last_pair
      FROM public.ottoq_sim_runs r
     WHERE r.run_by = 'cert_harness'
       AND r.validation_notes IS NOT NULL
       AND jsonb_typeof(r.validation_notes::jsonb->'arm_a') = 'object'
     GROUP BY 1,2,3,4
  )
  -- Registered columns: MISSING if never paired, OVERDUE past max_age, else OK.
  SELECT CASE WHEN s.last_pair IS NULL              THEN 'MISSING'
              WHEN now() - s.last_pair > c.max_age  THEN 'OVERDUE'
              ELSE 'OK' END,
         c.depot_id, c.scenario, c.seed, c.ticks,
         s.last_pair, now() - s.last_pair, c.max_age, true
    FROM public.ottoq_cert_columns c
    LEFT JOIN seen s
      ON s.depot_id = c.depot_id AND s.scenario = c.scenario
     AND s.seed = c.seed AND s.ticks = c.ticks
   WHERE c.enabled
  UNION ALL
  -- And the other direction: a column being paired that nobody declared. Not a
  -- fault, but it must be visible -- otherwise the registry silently drifts from
  -- what the harness actually runs, which is how this class of defect returns.
  SELECT 'UNREGISTERED', s.depot_id, s.scenario, s.seed, s.ticks,
         s.last_pair, now() - s.last_pair, NULL::interval, false
    FROM seen s
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_cert_columns c
                      WHERE c.depot_id = s.depot_id AND c.scenario = s.scenario
                        AND c.seed = s.seed AND c.ticks = s.ticks)
  ORDER BY 1, 7 DESC NULLS FIRST;
$function$;

COMMENT ON FUNCTION public.ottoq_cert_coverage() IS
  '0252: what the certification is supposed to cover vs what it has. MISSING = '
  'registered and never paired. OVERDUE = past its declared max_age. UNREGISTERED '
  '= being paired but not declared. Read this before saying the matrix is green; '
  'ottoq_cert_matrix answers whether the pairs that RAN agree, never whether the '
  'pairs that should have run did.';

-- ---------------------------------------------------------------------------
-- 3. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int; v_missing int; v_overdue int; v_unreg int; v_48 text;
BEGIN
  -- A1. Every column the harness has actually paired is registered. If this
  --     fails the registry is already drifting from reality on day one.
  SELECT count(*) INTO v_unreg FROM public.ottoq_cert_coverage() WHERE status='UNREGISTERED';
  IF v_unreg <> 0 THEN
    RAISE EXCEPTION 'A1 FAILED: % column(s) are being paired but not registered', v_unreg;
  END IF;

  -- A2. Nothing is MISSING -- all nine registered columns have run at least once.
  SELECT count(*) INTO v_missing FROM public.ottoq_cert_coverage() WHERE status='MISSING';
  IF v_missing <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: % registered column(s) have never been paired', v_missing;
  END IF;

  -- A3. THE ASSERTION THIS MIGRATION EXISTS FOR. The instrument must be able to
  --     see the defect that motivated it. At apply time the 48t column has been
  --     unpaired for ~5 days against a 24h max_age, so it MUST read OVERDUE --
  --     unless the two pairs scheduled for 15:45/16:10 have already landed, in
  --     which case it reads OK and that is the fix working. Either answer is
  --     acceptable; what is NOT acceptable is the instrument returning nothing,
  --     which is precisely what the old one did.
  SELECT status INTO v_48 FROM public.ottoq_cert_coverage()
   WHERE scenario='busy_day' AND seed=171717 AND ticks=48;
  IF v_48 IS NULL THEN
    RAISE EXCEPTION 'A3 FAILED: the 48-tick column is invisible to the coverage instrument';
  END IF;
  RAISE NOTICE 'A3: busy_day/171717/48t reads %', v_48;

  SELECT count(*) INTO v_overdue FROM public.ottoq_cert_coverage() WHERE status='OVERDUE';
  SELECT count(*) INTO v_n FROM public.ottoq_cert_columns WHERE enabled;
  RAISE NOTICE 'A1-A3 PASSED; % registered column(s), % OVERDUE, % MISSING, % UNREGISTERED',
               v_n, v_overdue, v_missing, v_unreg;
END $$;

-- ===========================================================================
-- WHAT THIS DOES NOT DO, SAID PLAINLY
--
-- It does not schedule anything. It makes the gap VISIBLE and nameable in one
-- call; it does not close the loop that lets a column go unrun for five days.
-- That loop -- a round that reads ottoq_cert_coverage() and schedules its own
-- OVERDUE columns instead of firing a hand-written list of six -- is the actual
-- fix and is BUILD_QUEUE P0 #3. Shipping the instrument first is deliberate:
-- an auto-scheduler built on an unproven coverage query would be the same
-- mistake as 0247's purge built on an unexamined delete list.
-- ===========================================================================
