-- migration-version: 20260921165330
-- migration-name:    a_determinism_verdict_can_finally_state_the_clock_it_was_earned_at_g112
--
-- 0402  **G112, decision (3a): a determinism verdict can state its own clock.** `db/checks/0312` §3
--       measured that **all 18 surviving `cert_harness` runs advance 30.00 sim-minutes per tick while
--       `production_live` advances 2.00** — the certification harness is **15× coarser than the
--       configuration that ships** — and that **neither `ottoq_determinism_canon` nor
--       `ottoq_determinism_verdict_ledger` has any column recording tick SIZE.** `canon.ticks` and
--       `ledger.ticks` are COUNTS. So today a verdict is physically unable to say what clock it was
--       earned at, and "certified" reads as unqualified when it is not.
--
-- **`forces_recert` FALSE, and measurably rather than by argument: this migration creates a VIEW and
-- a function. It writes no table, changes no engine behaviour, and nothing hashed can read an object
-- that did not exist when the hash was taken.**
--
-- ══ APPLIED 20260921165330, AND ITS FIRST READING IS THE DISCLOSURE ═══════
--
--   SELECT * FROM public.ottoq_assert_verdict_clock_legibility();
--   verdicts  clock_recoverable  distinct_clocks  coarsest  finest
--       56            9             **30.00**      30.00    30.00
--
-- **Not one determinism verdict in this database whose clock is recoverable was earned at anything
-- other than 30.00 sim-minutes per tick** — coarsest and finest are the same number — against a
-- `production_live` clock of **2.00**. And **47 of 56 cannot state their clock at all**, because the
-- arm runs that produced them have been purged. Both halves are the finding: the engine has never
-- certified determinism at the granularity it ships, and until now could not have told you so.
--
-- ══ WHAT THIS DELIBERATELY DOES *NOT* DO, AND WHY ══════════════════════════
--
-- **(1) It does not add a column to `ottoq_determinism_canon`.** Measured: **no function in the
-- database writes that table** — `prosrc` matching `INSERT INTO … canon` / `UPDATE … canon` returns
-- nothing. Its writer is outside the database. **A column that nothing fills is the exact defect this
-- repo keeps convicting** (`0277`'s orphaned concurrency class, `0145`'s empty instrument, G28's
-- unreachable branch), so adding one here would create the problem it is meant to document.
--
-- **(2) It does not modify `public.ottoq_determinism_pair`.** That function is the ledger's sole
-- writer and is the certification path itself, 13,489 characters of it. Stamping the clock at write
-- time IS the durable fix — a view can only report what survives — but editing the function that
-- produces every verdict, in the same pass that decides three unrelated things, is how a certification
-- run breaks. **Named as the follow-up rather than done badly here.**
--
-- ══ WHAT IT DOES, AND THE LIMIT ON IT ══════════════════════════════════════
--
-- `ottoq_determinism_verdict_ledger` is `class='evidence'` (56 rows, survives the purge) and carries
-- `arm_a_run` / `arm_b_run`. `ottoq_sim_runs` is `class='engine'` and does NOT survive it. So the
-- clock is recoverable exactly while a verdict's arm runs still exist, and **NULL is not missing data
-- — it is the honest answer "the runs that produced this verdict have been purged, and its clock is
-- not recoverable from this database."** The view says so in its own comment rather than letting a
-- NULL be read as zero or as an oversight. That gap is precisely the argument for (2).

BEGIN;

DO $preflight$
DECLARE v_n int;
BEGIN
  -- (1) The ledger still carries the arm-run links this view joins through.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_determinism_verdict_ledger'
     AND column_name IN ('verdict_id','arm_a_run','arm_b_run','ticks','engine_hash','certified_at');
  IF v_n <> 6 THEN
    RAISE EXCEPTION '0402 P1: ottoq_determinism_verdict_ledger is missing one of verdict_id/arm_a_run/arm_b_run/ticks/engine_hash/certified_at (found % of 6)', v_n;
  END IF;

  -- (2) The runs table still carries the two columns the clock is derived from. If either moves,
  --     the derivation below silently becomes NULL for every row rather than erroring.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_sim_runs'
     AND column_name IN ('sim_clock_start','sim_clock_current','tick_count');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0402 P2: ottoq_sim_runs is missing one of sim_clock_start/sim_clock_current/tick_count (found % of 3)', v_n;
  END IF;

  -- (3) The premise: no tick-SIZE column exists on either verdict table. If one has appeared,
  --     this view is redundant and should not be created in ignorance of it.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public'
     AND table_name IN ('ottoq_determinism_canon','ottoq_determinism_verdict_ledger')
     AND column_name ~ 'sim_min_per_tick|tick_minutes|tick_size';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0402 P3: a tick-size column already exists on a verdict table (% found); re-read before adding a view that derives one', v_n;
  END IF;

  -- (4) The distinction this whole file rests on: tick_interval_seconds is WALL pacing, not sim
  --     advance. Assert it is still a different thing from the derived value, so a future reader
  --     cannot quietly substitute it. Measured 2026-09-21: 30 for every run in the database,
  --     including production runs advancing 2.00 sim-min and demo runs advancing 0.48.
  SELECT count(DISTINCT tick_interval_seconds) INTO v_n FROM public.ottoq_sim_runs WHERE tick_count > 0;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0402 P4: no runs with tick_count > 0 -- cannot establish the wall-vs-sim distinction this file documents';
  END IF;
END
$preflight$;

CREATE OR REPLACE VIEW public.ottoq_determinism_verdict_clock AS
SELECT l.verdict_id,
       l.certified_at,
       l.scenario,
       l.seed,
       l.ticks                                   AS tick_count,
       l.outcome,
       l.equal,
       l.engine_hash,
       -- The clock, derived from arm A. NULL means the arm runs have been purged, NOT that the
       -- verdict lacked one. See the view's comment.
       round(extract(epoch FROM (r.sim_clock_current - r.sim_clock_start))
             / NULLIF(r.tick_count, 0) / 60.0, 2) AS sim_min_per_tick,
       r.tick_interval_seconds                    AS wall_seconds_per_tick,
       (r.sim_run_id IS NOT NULL)                 AS clock_recoverable,
       r.run_by                                   AS arm_a_run_by
  FROM public.ottoq_determinism_verdict_ledger l
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.arm_a_run;

COMMENT ON VIEW public.ottoq_determinism_verdict_clock IS
'The clock each determinism verdict was earned at, which the verdict tables themselves cannot state: '
'ottoq_determinism_canon.ticks and ottoq_determinism_verdict_ledger.ticks are COUNTS, and neither '
'table has a tick-SIZE column (0402/G112). sim_min_per_tick is SIM time advanced per tick, derived '
'from arm A. wall_seconds_per_tick is tick_interval_seconds, which is REAL-TIME pacing and a '
'different quantity -- it reads 30 for every run in this database, including production runs '
'advancing 2.00 sim-min per tick and demo runs advancing 0.48, so it must never be substituted for '
'the derived value. NULL sim_min_per_tick with clock_recoverable=false means the arm runs were '
'purged (ottoq_sim_runs is class=engine; this ledger is class=evidence), NOT that the verdict had no '
'clock -- which is the argument for stamping it at certification time in ottoq_determinism_pair, the '
'durable fix this view is not. Measured 2026-09-21: cert_harness 30.00 sim-min/tick against '
'production_live 2.00 -- the harness is 15x coarser than what ships, and at 30 the begin_charge '
'chain cannot complete inside a charge window with less than about 36 minutes of budget left '
'(db/checks/0311 section 2), which is why ~40%% of cert charge turns never charge.';

CREATE OR REPLACE FUNCTION public.ottoq_assert_verdict_clock_legibility()
RETURNS TABLE (verdicts bigint, clock_recoverable bigint, distinct_clocks text, coarsest numeric, finest numeric)
LANGUAGE sql STABLE AS $$
  SELECT count(*),
         count(*) FILTER (WHERE clock_recoverable),
         COALESCE(string_agg(DISTINCT sim_min_per_tick::text, ', '
                  ORDER BY sim_min_per_tick::text), '(none recoverable)'),
         max(sim_min_per_tick),
         min(sim_min_per_tick)
    FROM public.ottoq_determinism_verdict_clock
$$;

COMMENT ON FUNCTION public.ottoq_assert_verdict_clock_legibility() IS
'How many determinism verdicts can state the clock they were earned at. This is a DISCLOSURE, not a '
'gate: it is expected to report fewer recoverable than total, because ottoq_sim_runs is class=engine '
'and purges while the verdict ledger is class=evidence and does not. It becomes a gate only once '
'ottoq_determinism_pair stamps the clock at write time, after which recoverable should equal total '
'for every verdict written from then on. 0402 / G112.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0402_a_determinism_verdict_can_finally_state_the_clock_it_was_earned_at_g112',
        FALSE,
        'G112 decision (3a) from db/checks/0312. Measured: all 18 surviving cert_harness runs advance '
        '30.00 sim-minutes per tick while production_live advances 2.00, so the certification harness '
        'is 15x coarser than the configuration that ships -- and NEITHER ottoq_determinism_canon nor '
        'ottoq_determinism_verdict_ledger has any column recording tick SIZE, only COUNT. A verdict '
        'has therefore been unable to state its own clock, and "certified" read as unqualified when '
        'it was not. Adds ottoq_determinism_verdict_clock, a view deriving sim_min_per_tick from arm '
        'A, plus ottoq_assert_verdict_clock_legibility() reporting how many verdicts can state their '
        'clock. forces_recert FALSE, measurable rather than argued: this creates a view and a '
        'function, writes no table, changes no engine behaviour, and nothing hashed can read an '
        'object that did not exist. DELIBERATELY NOT DONE, both named rather than hidden: (1) no '
        'column is added to ottoq_determinism_canon, because NO function in the database writes that '
        'table -- its writer is external -- and a column nothing fills is the defect class this repo '
        'keeps convicting; (2) ottoq_determinism_pair is not modified, though stamping the clock at '
        'write time is the durable fix a view cannot be, because it is the certification path itself '
        'and editing it inside a pass that decides three unrelated things is how a cert run breaks. '
        'The view reports NULL where arm runs have been purged, which is the honest answer rather '
        'than missing data, and is itself the argument for (2). Preflight (4) asserts the '
        'wall-versus-sim distinction that nearly decided this wrongly: tick_interval_seconds is '
        'REAL-TIME pacing and reads 30 for every run in the database regardless of whether that run '
        'advances 30.00, 2.00 or 0.48 sim-minutes per tick. NOT CLAIMED: that any published verdict '
        'is invalid. None is -- determinism holds at any tick size and both arms of every pair are '
        'equally coarse. What is claimed is that the nine current canon columns were all earned at '
        '30 sim-min/tick against a production clock of 2.00, and until now no verdict could say so.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
