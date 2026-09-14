-- migration-version: PENDING
-- migration-name:    0311_a_column_that_looks_like_the_price_and_is_not
--
-- 0311  site_energy_snapshots.lmp_usd_mwh IS NULL IN EVERY ROW EVER WRITTEN,
--       HAS NO READER, AND SITS NEXT TO THE ENERGY DATA THE ENGINE DOES USE
--
-- This migration adds one COMMENT. It is worth a migration because the column
-- it comments on cost this session a false finding that was reported outward
-- before it was caught.
--
-- ---------------------------------------------------------------------------
-- WHAT HAPPENED, since the cost is the entire justification
--
-- Investigating why the self-improvement loop's energy plans tied
-- (db/checks/0235), I read that ottoq_energy_orchestrate contains
-- `INTO v_se FROM site_energy_snapshots`, found a column on that table called
-- lmp_usd_mwh, measured it, and got NULL in 24,898 of 24,898 rows. I concluded
-- and reported that the twin has no electricity price and that the engine's
-- expensive-tariff branch was unreachable dead code.
--
-- Both false. The engine reads a DIFFERENT column on a DIFFERENT table:
--
--     SELECT lmp_usd_per_mwh INTO v_lmp FROM ottoq_grid_snapshots ...
--
-- and ottoq_grid_snapshots.lmp_usd_per_mwh is non-NULL in all 22,319 rows,
-- $8.00 to $282.80/MWh, with 1,178 rows (5.3%) above the $60 threshold that
-- makes v_expensive true. The twin has a wholesale price AND a retail
-- time-of-use rate, and always has. Retracted in db/checks/0235 correction 3.
--
-- Note the two spellings: lmp_usd_mwh (dead) and lmp_usd_per_mwh (live). They
-- differ by four characters and sit on two tables that both describe site
-- energy for the same run at the same tick.
--
-- ---------------------------------------------------------------------------
-- WHY A COMMENT RATHER THAN A DROP OR A BACKFILL
--
-- DROP is forbidden by scripts/APPLYING.md, and rightly -- a column dropped is
-- a column no rollback restores.
--
-- BACKFILL was considered and rejected. Populating it from
-- ottoq_grid_snapshots would make two columns carry the same fact with no
-- mechanism keeping them equal, which is the G54 class (two sources of truth
-- for one value) that this repo has convicted twice. A dead column is a trap;
-- a silently diverging duplicate is a worse one.
--
-- So: the column stays, empty, and says what it is. The next reader who greps
-- for a price on this table gets an answer instead of a hypothesis.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE. A COMMENT ON COLUMN changes no behaviour, no plan, no
-- value and no hash. Nothing reads the column; nothing reads the comment.
-- AND THE LINEAGE ROW IS WRITTEN IN THIS FILE -- 0308 and 0309 each argued
-- forces_recert=false correctly and omitted the row, the floor moved to 0309's
-- apply stamp, and ottoq_cert_matrix returned ZERO columns until 0310 repaired
-- it. Third occurrence of that omission in this repo. Not a fourth.
-- ===========================================================================

DO $pre$
DECLARE v_total int; v_nonnull int; v_readers int;
BEGIN
  -- P1. THE COLUMN EXISTS AND IS EMPTY. If it ever gains a value this comment
  --     becomes false and the migration must not be applied blind.
  SELECT count(*), count(lmp_usd_mwh) INTO v_total, v_nonnull
    FROM public.site_energy_snapshots;
  IF v_nonnull <> 0 THEN
    RAISE EXCEPTION '0311 P1: site_energy_snapshots.lmp_usd_mwh now has % non-NULL value(s) of %; '
                    'it is no longer dead and this comment would be wrong', v_nonnull, v_total;
  END IF;
  IF v_total < 1000 THEN
    RAISE EXCEPTION '0311 P1: only % rows in site_energy_snapshots; too few to call the column dead', v_total;
  END IF;

  -- P2. NOTHING READS IT. The claim the comment makes, asserted.
  --
  -- THIS PRECONDITION REFUSED THE FIRST APPLY, and it was right to. Written
  -- without the exemption below it found ONE match and stopped the migration
  -- rather than let it assert "no reader" falsely. The match is
  -- twin.ottoq_sim_sample_lmp_usd_mwh -- the function that GENERATES the price
  -- series (seasonal shape plus storm cards), whose own NAME contains the
  -- quantity and which uses 'lmp_usd_mwh' as a feed-plan key and a plan label
  -- ('lmp_usd_mwh.v1'). Those are string literals and an identifier, not a read
  -- of public.site_energy_snapshots.lmp_usd_mwh.
  --
  -- It is exempted BY NAME rather than by loosening the pattern, because a
  -- pattern relaxed until it passes is not a precondition. Any NEW function
  -- that references the column still fails this block.
  --
  -- And the exemption is itself evidence for the comment this migration adds:
  -- a dedicated sampler for this quantity exists, which is the opposite of the
  -- retracted claim that the twin has no price.
  SELECT count(*) INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc LIKE '%lmp_usd_mwh%'
     AND p.prosrc NOT LIKE '%lmp_usd_per_mwh%'
     AND p.proname <> 'ottoq_sim_sample_lmp_usd_mwh';
  IF v_readers <> 0 THEN
    RAISE EXCEPTION '0311 P2: % function(s) reference lmp_usd_mwh without the live spelling; '
                    'the column is not unread', v_readers;
  END IF;

  -- P3. AND THE LIVE COLUMN REALLY IS LIVE, so the comment points somewhere true.
  SELECT count(lmp_usd_per_mwh) INTO v_nonnull FROM public.ottoq_grid_snapshots;
  IF v_nonnull < 1000 THEN
    RAISE EXCEPTION '0311 P3: ottoq_grid_snapshots.lmp_usd_per_mwh has only % non-NULL value(s); '
                    'the comment would point at a column that is itself empty', v_nonnull;
  END IF;
END $pre$;

COMMENT ON COLUMN public.site_energy_snapshots.lmp_usd_mwh IS
'DEAD COLUMN -- NULL in every row ever written, and no function reads it. THIS IS NOT THE PRICE '
'THE ENGINE USES. ottoq_energy_orchestrate reads public.ottoq_grid_snapshots.lmp_usd_per_mwh '
'(note the different spelling), which is populated in every row, ranges $8.00-$282.80/MWh, and '
'drives v_expensive := v_lmp > 60 and therefore the choice between '
'energy_demand_factor_expensive and energy_demand_factor_peak. The retail rate on THIS table, '
'current_rate_per_kwh, is populated and is a different quantity. 0311; the trap is recorded in '
'db/checks/0235 correction 3, where reading this column instead of the live one produced a '
'reported-and-retracted claim that the twin had no electricity price. Not backfilled '
'deliberately: two columns carrying one fact with nothing keeping them equal is the G54 class.';

DO $post$
DECLARE v_c text;
BEGIN
  -- A1. THE COMMENT LANDED, and names the live column so the pointer works.
  SELECT col_description('public.site_energy_snapshots'::regclass, a.attnum) INTO v_c
    FROM pg_attribute a
   WHERE a.attrelid = 'public.site_energy_snapshots'::regclass
     AND a.attname = 'lmp_usd_mwh';
  IF v_c IS NULL OR position('lmp_usd_per_mwh' in v_c) = 0 THEN
    RAISE EXCEPTION '0311 A1: the comment is missing or does not name the live column: %', COALESCE(v_c,'NULL');
  END IF;

  -- A2. NOTHING ELSE MOVED. A comment must not have touched a row.
  IF (SELECT count(lmp_usd_mwh) FROM public.site_energy_snapshots) <> 0 THEN
    RAISE EXCEPTION '0311 A2: the column acquired values during a COMMENT';
  END IF;
END $post$;

-- The lineage row, IN THIS FILE, because 0308/0309 omitted theirs and the
-- recert floor swallowed every certification column until 0310 repaired it.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0311_a_column_that_looks_like_the_price_and_is_not', false,
   'One COMMENT ON COLUMN on public.site_energy_snapshots.lmp_usd_mwh, a column that is NULL in '
   'all 24,898 rows and has no reader (both asserted in P1/P2). A comment changes no behaviour, '
   'no value and no hash. Not backfilled deliberately -- duplicating ottoq_grid_snapshots.'
   'lmp_usd_per_mwh with nothing keeping the two equal is the G54 two-sources-of-truth class.',
   now())
ON CONFLICT (name) DO NOTHING;
