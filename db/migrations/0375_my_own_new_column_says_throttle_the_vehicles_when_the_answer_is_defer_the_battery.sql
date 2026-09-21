-- migration-version: 20260920124500
-- migration-name:    my_own_new_column_says_throttle_the_vehicles_when_the_answer_is_defer_the_battery
--
-- 0375  0374's READER ANSWERS "WHAT IS THE BIGGEST LOAD" UNDER A COLUMN NAME THAT
--       READS AS "WHAT PUSHED US OVER". THOSE ARE DIFFERENT QUESTIONS AND THEY
--       DISAGREE ON THE ONLY EXCURSION WE HAVE.
--
-- Self-correction, twenty minutes after 0374. View only: no table DDL, no change to
-- the tick path, `forces_recert` **FALSE**.
--
-- ══ 1. THE DEFECT, WHICH IS A NAMING ONE AND THEREFORE THE DANGEROUS KIND ═══
--
-- 0374 shipped `dominant_component` and its own COMMENT told the reader it answers
-- *"what pushed us over, which is the first question and the one that decides
-- whether enforcement should refuse a vehicle or defer a battery."* The column does
-- not answer that. It computes the **largest single load** at the instant, which is
-- a different quantity, and on the one excursion in evidence the two disagree:
--
--   total 2,738.80   cap 2,500   EV 1,691.80   BESS charging 968.00   base 79.00
--   dominant_component                          = **ev_charging**   (EV is biggest)
--   total with the BESS charge deferred         = **1,770.8 kW**    (729 kW under cap)
--
-- So a reader following that column would **throttle vehicles**, when deferring the
-- battery clears the excursion outright with 729 kW of headroom to spare. That is a
-- decision-changing misread, produced by my own instrument, in the direction that
-- degrades service unnecessarily.
--
-- **AND BOTH REMOVALS CLEAR THE CAP, WHICH IS WHY ARITHMETIC ALONE CANNOT PICK.**
-- Dropping the EV load would also clear it (1,047 kW). The discriminator is not
-- magnitude, it is **which load is discretionary**: a battery's charge timing is a
-- schedulable arbitrage decision that can move to any cheaper hour, while a vehicle
-- mid-charge is a service commitment with a required-ready-time attached. That is a
-- judgement about the product, not a fact about the numbers, so this file states it
-- as one in the view's comment rather than smuggling it in as a computed column.
--
-- What the view now reports, separated:
--   * `largest_component`            -- renamed from `usual_dominant_component`, and
--                                       now named after what it actually measures.
--   * `excursions_bess_deferral_clears` -- the count for which deferring the BESS
--                                       charge alone would have brought the total
--                                       under the cap. The actionable number.
--   * `excursions_needing_ev_action` -- the residual: over the cap even with the
--                                       battery at zero. THIS is the set where a
--                                       shield would have to touch a vehicle, and
--                                       on the evidence so far it is **empty**.
--
-- The last one is the point of the whole file. "Every excursion we have ever
-- recorded would have been cleared by deferring the battery, and none of them
-- required refusing a vehicle" is a sentence worth having, and 0374's reader could
-- not produce it.
--
-- ══ 2. WHY THIS IS A SEPARATE FILE AND NOT AN EDIT TO 0374 ══════════════════
--
-- 0374 is applied. Rewriting an applied migration in place would leave the
-- repository describing a file the database never ran, which is the defect class
-- `db/checks/0135` exists to catch. The correction is additive and dated.
--
-- Note the shape this repeats, deliberately recorded: 0371 was the same move on
-- 0367 (I put `SKIP LOCKED` inside a certified path and took it back out an hour
-- later). Both are cases of the instrument being wrong rather than the finding, and
-- both were caught by reading the instrument's own output instead of trusting that
-- it said what I meant. **`ottoq_site_power_ledger` was read once, immediately after
-- apply, and that is what found this.**

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
BEGIN
  IF to_regclass('public.ottoq_site_power_ledger') IS NULL THEN
    RAISE EXCEPTION '0375 P1: ottoq_site_power_ledger does not exist -- 0374 must be '
                    'applied before this correction to it';
  END IF;
  RAISE NOTICE '0375 P1: 0374''s view is present';
END $p1$;

DO $p2$
DECLARE v_dom text; v_clears boolean; v_n int;
BEGIN
  --: Assert the defect this file corrects is REAL in the live data, so the
  --: correction cannot be shipped on a story rather than a measurement.
  SELECT count(*) INTO v_n FROM public.ottoq_site_power_excursion_ledger
   WHERE severity_tier = 'excursion';
  IF v_n = 0 THEN
    RAISE WARNING '0375 P2: no excursion rows -- the disagreement this file corrects '
                  'is not demonstrable here, but the renaming stands on its own';
  ELSE
    SELECT l.dominant_component,
           (l.total_import_kw - l.bess_charging_kw) <= l.cap_kw
      INTO v_dom, v_clears
      FROM public.ottoq_site_power_excursion_ledger l
     WHERE l.severity_tier = 'excursion'
     ORDER BY l.excess_kw DESC LIMIT 1;
    IF v_dom = 'ev_charging' AND v_clears THEN
      RAISE NOTICE '0375 P2: confirmed -- worst excursion reports dominant_component=%, '
                   'yet deferring the BESS charge alone clears the cap', v_dom;
    ELSE
      RAISE WARNING '0375 P2: the worst excursion does not show the disagreement '
                    '(dominant=%, bess_deferral_clears=%) -- the renaming is still '
                    'correct but re-read section 1 before quoting it', v_dom, v_clears;
    END IF;
  END IF;
END $p2$;

DO $p2b$
DECLARE v_deps int; v_fns int;
BEGIN
  --: The corrected reader RENAMES a column and inserts two new ones mid-list, and
  --: CREATE OR REPLACE VIEW can do neither -- it refuses a rename outright and only
  --: permits additions at the end. So this file DROPs and recreates, which is safe
  --: only if nothing depends on the view. Asserted, not assumed.
  SELECT count(DISTINCT dependent.oid) INTO v_deps
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class dependent ON dependent.oid = r.ev_class
   WHERE d.refobjid = 'public.ottoq_site_power_ledger'::regclass
     AND dependent.relname <> 'ottoq_site_power_ledger';
  IF v_deps > 0 THEN
    RAISE EXCEPTION '0375 P2b: % object(s) depend on ottoq_site_power_ledger -- a DROP '
                    'would take them with it', v_deps;
  END IF;

  --: And no function body names it. NOTE THE ESCAPE: an unescaped LIKE pattern
  --: matched `ottoq.site_power_ledger_unlock` -- 0374's own append-only guard --
  --: because `_` is a single-character wildcard and so is the `.`. That is the trap
  --: BUILD_QUEUE records from earlier tonight, hit again here, and it is why this
  --: predicate escapes every underscore instead of reading naturally.
  SELECT count(*) INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.prosrc LIKE '%ottoq\_site\_power\_ledger%';
  IF v_fns > 0 THEN
    RAISE EXCEPTION '0375 P2b: % function(s) reference ottoq_site_power_ledger by name', v_fns;
  END IF;
  RAISE NOTICE '0375 P2b: no dependents -- the view can be recreated';
END $p2b$;

-- ══ THE CORRECTED READER ════════════════════════════════════════════════════

--: Not CREATE OR REPLACE: that cannot rename `usual_dominant_component` and cannot
--: insert the two remedy counts mid-list. No data is lost -- it is a view.
DROP VIEW public.ottoq_site_power_ledger;

CREATE VIEW public.ottoq_site_power_ledger AS
SELECT l.depot_id,
       count(*)                                                       AS readings,
       count(*) FILTER (WHERE l.severity_tier = 'excursion')          AS excursions,
       count(*) FILTER (WHERE l.severity_tier = 'high_water')         AS high_water,
       --: 0341's assertion as a column rather than a promise: these two must sum to
       --: `readings` or a tier has been added without a reader.
       (count(*) FILTER (WHERE l.severity_tier = 'excursion')
        + count(*) FILTER (WHERE l.severity_tier = 'high_water')) = count(*)
                                                                      AS tiers_sum_to_readings,
       count(DISTINCT l.sim_run_id)                                   AS runs_seen,
       count(DISTINCT l.sim_run_id) FILTER (WHERE l.severity_tier = 'excursion')
                                                                      AS runs_with_excursion,
       max(l.cap_kw)                                                  AS cap_kw,
       round(max(l.total_import_kw), 1)                               AS worst_total_kw,
       round(max(l.excess_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_excess_kw,
       round(avg(l.total_import_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS mean_total_when_over,
       --: 0375: RENAMED from `usual_dominant_component`, which read as though it
       --: answered "what pushed us over". It answers "what is the biggest load",
       --: and on the only excursion in evidence those disagree.
       mode() WITHIN GROUP (ORDER BY l.dominant_component)
         FILTER (WHERE l.severity_tier = 'excursion')                 AS largest_component,
       --: 0375: THE ACTIONABLE PAIR. Deferring a battery's charge is schedulable;
       --: refusing a vehicle mid-charge is a broken service commitment. So the
       --: question that matters is not which load is biggest but whether the
       --: discretionary one was enough on its own.
       count(*) FILTER (WHERE l.severity_tier = 'excursion'
                          AND (l.total_import_kw - COALESCE(l.bess_charging_kw,0)) <= l.cap_kw)
                                                                      AS excursions_bess_deferral_clears,
       --: The residual, and the only set in which a shield would have to touch a
       --: vehicle. Zero on the evidence so far.
       count(*) FILTER (WHERE l.severity_tier = 'excursion'
                          AND (l.total_import_kw - COALESCE(l.bess_charging_kw,0)) > l.cap_kw)
                                                                      AS excursions_needing_ev_action,
       round(max(l.bess_charging_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_bess_charging_kw,
       round(max(l.ev_charging_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_ev_charging_kw,
       count(*) FILTER (WHERE l.source_kind = 'live')                 AS live_rows,
       count(*) FILTER (WHERE l.source_kind = 'backfill')             AS backfilled_rows,
       max(l.sim_clock)                                               AS last_reading_sim_clock,
       max(l.detected_at)                                             AS last_detected_at
  FROM public.ottoq_site_power_excursion_ledger l
 GROUP BY l.depot_id;

COMMENT ON VIEW public.ottoq_site_power_ledger IS
'0374, corrected by 0375. The per-depot answer to "how often has this site exceeded its declared power cap, and what would have cleared it" -- a question no surviving table could answer before, because the total lives in site_energy_snapshots (class=engine, purged by the next demo run). READ excursions_bess_deferral_clears AND excursions_needing_ev_action, NOT largest_component. largest_component was shipped by 0374 as usual_dominant_component with a comment claiming it answered "what pushed us over"; it does not, it answers "what is the biggest load", and on the only excursion in evidence the two disagree -- it reports ev_charging (1,691.8 kW, the largest single load) while deferring the BESS charge of 968 kW alone brings 2,738.8 under the 2,500 cap with 729 kW to spare. Acting on the old column would have throttled vehicles for no reason. BOTH REMOVALS CLEAR THE CAP THERE, so magnitude cannot pick between them: the discriminator is that a battery''s charge timing is schedulable arbitrage which can move to any cheaper hour, while a vehicle mid-charge is a service commitment carrying a required-ready-time. That is a judgement about the product, not a fact about the numbers, and it is stated here rather than computed into a column. excursions_needing_ev_action is the residual -- over the cap even with the battery at zero -- and is the only set in which a shield would have to touch a vehicle at all. tiers_sum_to_readings is 0341''s lesson as a column: if it reads false, a tier was added to the table and not to this view.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p3$
DECLARE v_clears int; v_needs int; v_exc int; v_sum boolean; v_largest text;
BEGIN
  SELECT excursions, excursions_bess_deferral_clears, excursions_needing_ev_action,
         tiers_sum_to_readings, largest_component
    INTO v_exc, v_clears, v_needs, v_sum, v_largest
    FROM public.ottoq_site_power_ledger
   WHERE depot_id = '11111111-1111-1111-1111-111111111111';

  IF v_exc IS NULL THEN
    RAISE WARNING '0375 P3: no ledger rows for the twin depot';
    RETURN;
  END IF;

  --: The two new counts partition the excursions. If they do not, one of the
  --: predicates is wrong and the actionable number is not trustworthy -- the same
  --: non-summing-buckets defect 0341 fixed and 0374 guarded against for tiers.
  IF v_clears + v_needs <> v_exc THEN
    RAISE EXCEPTION '0375 P3: the remedy counts do not partition the excursions '
                    '(% + % <> %)', v_clears, v_needs, v_exc;
  END IF;
  IF NOT v_sum THEN
    RAISE EXCEPTION '0375 P3: tiers no longer sum to readings';
  END IF;
  RAISE NOTICE '0375 P3: % excursion(s); % clearable by deferring the BESS, % needing '
               'EV action; largest_component reads %', v_exc, v_clears, v_needs, v_largest;
END $p3$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0375_my_own_new_column_says_throttle_the_vehicles_when_the_answer_is_defer_the_battery', false,
  'View only, correcting 0374''s reader twenty minutes after it shipped. No table DDL and no '
  'change to ottoq_sim_decide_and_dispatch or any tick path, so no canon is invalidated. '
  '0374 exposed usual_dominant_component with a comment claiming it answered "what pushed us '
  'over"; it answers "what is the biggest load", and on the only excursion in evidence the two '
  'disagree -- it reads ev_charging while deferring the 968 kW BESS charge alone brings 2,738.8 '
  'under the 2,500 cap with 729 kW to spare, so a reader following it would throttle vehicles '
  'for no reason. Renamed to largest_component and joined by excursions_bess_deferral_clears / '
  'excursions_needing_ev_action, which are asserted in P3 to partition the excursions.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
