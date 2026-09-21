-- migration-version: 20260920132500
-- migration-name:    removing_the_one_row_my_own_path_test_left_in_an_evidence_table
--
-- 0377  I TESTED 0376's `ON CONFLICT` PATH BY LOWERING THE THRESHOLD BY HAND, AND
--       IT LEFT A `high_water` ROW AT 498 kW IN AN EVIDENCE TABLE.
--
-- Data only: one DELETE under the append-only override. No DDL, no function change,
-- nothing on the tick path. `forces_recert` **FALSE**.
--
-- ══ 1. WHY THE TEST HAPPENED AND WHY IT HAD TO ══════════════════════════════
--
-- `0376` rewrote the detector's finding-INSERT to
-- `ON CONFLICT (snapshot_id) WHERE severity_tier <> 'armed' DO NOTHING`, because the
-- unique index became partial. **That inference is resolved when the statement runs,
-- not when the function is created** -- so `0376` applying cleanly proved nothing about
-- it, and a wrong inference would have raised inside the detector, been swallowed by
-- `decide_and_dispatch`'s handler as a WARNING, and **silently lost an excursion.**
-- Exactly the failure mode the whole night has been about, so it needed exercising
-- rather than assuming.
--
-- I exercised it by calling the detector with `p_warn_frac := 0.001` on run
-- `cf59a904`, twice. It behaved correctly both times:
--
--   first call   tier high_water · **written 1** · armed false · total 498.2 kW
--   second call  tier high_water · **written 0** · armed false · same snapshot
--
-- So the insert works and the dedup works, and `armed false` on both confirms the
-- beacon does not re-fire within a run. **The test was right and the method was
-- sloppy:** it should have run in a transaction that rolled back, and instead it wrote
-- to an append-only evidence table.
--
-- ══ 2. WHY THE ROW CANNOT STAY ══════════════════════════════════════════════
--
-- Not tidiness. **A 498.2 kW reading tiered `high_water` is a lie about the site.**
-- `high_water` means "crossed 60% of the declared cap", i.e. 1,500 kW on this depot,
-- and the tier exists for exactly one purpose: to characterise the tail after a purge
-- has taken the snapshots. With this row present, the tail reads
--
--   high_water   min_kw **498.2**   max_kw 1,713.8
--
-- and any reader concludes the site crossed 60% of a 2,500 kW contract at 498 kW. The
-- threshold that produced it (0.001) is not recorded in the row -- `warn_kw` holds
-- 2.5, which is the only trace, and nobody reads a row's `warn_kw` before quoting its
-- tier. **A tier whose membership depends on an argument nobody sees is worse than no
-- tier.**
--
-- Deleted rather than annotated because the table is append-only: there is no UPDATE
-- to add a `path_test` marker with, and adding a `source_kind` value for it would mean
-- new DDL to preserve a row with no evidential content.
--
-- ══ 3. AND THE OVERRIDE IS USED AS ITS OWN COMMENT INSTRUCTS ════════════════
--
-- `ottoq_site_power_excursion_ledger_append_only` refuses UPDATE and DELETE unless
-- `ottoq.site_power_ledger_unlock = 'on'`, and its message says to *"set it in the
-- session to override, and say why in a migration."* This file is that. The unlock is
-- set, the DELETE is keyed to the single `high_water` row whose `warn_kw` is below any
-- plausible threshold, and it is reset immediately -- scoped with SET LOCAL so it
-- cannot leak past this transaction even if the reset were forgotten.
--
-- **The 16 backfilled rows and the 2 `armed` rows are NOT touched**, and P2 asserts it.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_target int; v_total int;
BEGIN
  --: Identify the row by the property that makes it wrong -- a warn_kw far below any
  --: threshold a real call would use -- rather than by id, so the predicate documents
  --: itself and cannot match a legitimate row.
  SELECT count(*) INTO v_target
    FROM public.ottoq_site_power_excursion_ledger
   WHERE severity_tier = 'high_water'
     AND source_kind = 'live'
     AND warn_kw < 100;
  SELECT count(*) INTO v_total FROM public.ottoq_site_power_excursion_ledger;

  IF v_target <> 1 THEN
    RAISE EXCEPTION '0377 P1: expected exactly 1 path-test row (high_water / live / '
                    'warn_kw < 100), found % of % total -- do not delete blind', v_target, v_total;
  END IF;
  RAISE NOTICE '0377 P1: 1 path-test row identified out of % total', v_total;
END $p1$;

-- ══ THE DELETE ══════════════════════════════════════════════════════════════

--: SET LOCAL, so the unlock dies with this transaction whatever happens next.
SET LOCAL "ottoq.site_power_ledger_unlock" = 'on';

DELETE FROM public.ottoq_site_power_excursion_ledger
 WHERE severity_tier = 'high_water'
   AND source_kind = 'live'
   AND warn_kw < 100;

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p2$
DECLARE v_armed int; v_back int; v_stray int; v_min numeric;
BEGIN
  SELECT count(*) FILTER (WHERE severity_tier = 'armed'),
         count(*) FILTER (WHERE source_kind = 'backfill'),
         count(*) FILTER (WHERE severity_tier = 'high_water' AND warn_kw < 100),
         min(total_import_kw) FILTER (WHERE severity_tier = 'high_water')
    INTO v_armed, v_back, v_stray, v_min
    FROM public.ottoq_site_power_excursion_ledger;

  IF v_stray <> 0 THEN
    RAISE EXCEPTION '0377 P2: % path-test row(s) remain', v_stray;
  END IF;
  IF v_back <> 16 THEN
    RAISE EXCEPTION '0377 P2: 0374''s backfill should be 16 rows, found % -- the DELETE '
                    'took more than it should', v_back;
  END IF;
  IF v_armed <> 2 THEN
    RAISE WARNING '0377 P2: expected 2 armed rows from the 12:48 pair, found % -- a run '
                  'may have started since', v_armed;
  END IF;
  --: The point of the file: the tail's floor is a real threshold crossing again.
  IF v_min < 1000 THEN
    RAISE EXCEPTION '0377 P2: the high_water floor is still % kW, which no 60%% threshold '
                    'on this depot could produce', round(v_min,1);
  END IF;
  RAISE NOTICE '0377 P2: clean -- 16 backfill, % armed, high_water floor % kW', v_armed, round(v_min,1);
END $p2$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0377_removing_the_one_row_my_own_path_test_left_in_an_evidence_table', false,
  'Data only: one DELETE under the append-only override, no DDL and nothing on the tick path, '
  'so no canon is invalidated. 0376 rewrote the detector''s finding-INSERT to ON CONFLICT '
  '(snapshot_id) WHERE severity_tier <> armed, an inference resolved at execution rather than at '
  'function creation -- so a wrong one would have raised inside the detector, been swallowed as a '
  'WARNING by decide_and_dispatch, and silently lost an excursion. Exercising it with '
  'p_warn_frac := 0.001 proved insert (written 1) and dedup (written 0) both correct, and left a '
  '498.2 kW row tiered high_water in an append-only evidence table. That row had to go because '
  'high_water means "crossed 60% of the declared cap" (1,500 kW here) and the tier exists to '
  'characterise the tail after a purge: with it present the tail floor read 498.2 kW and its only '
  'trace of the argument that produced it was warn_kw = 2.5, which nobody reads before quoting a '
  'tier. Deleted rather than annotated because append-only leaves no UPDATE to mark it with. The '
  '16 backfilled and 2 armed rows are asserted untouched in P2.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
