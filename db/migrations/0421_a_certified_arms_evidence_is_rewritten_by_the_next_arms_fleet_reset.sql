-- migration-version: PENDING
-- migration-name:    a_certified_arms_evidence_is_rewritten_by_the_next_arms_fleet_reset
--
-- 0421  **The one-line fix for `db/checks/0329` (G137): every certified pair fails when atom 4 is
--       recomputed from the evidence it was certified on, because the NEXT arm's fleet reset is filed
--       against the PREVIOUS arm. Proven on demand, both the cause and the fix, before writing this.**
--
--       **PREPARED, NOT APPLIED.** `forces_recert` **TRUE**: this changes `ottoq_events` content for
--       certification runs, so every canon re-runs. The recert sweep went green at 10:10 UTC and taking
--       the apparatus down twice in one morning is a scheduling decision, not a technical one — §5.
--
-- ══ §1 THE DEFECT IN ONE PARAGRAPH ════════════════════════════════════════════
--
-- `ottoq_determinism_pair` runs both arms in ONE transaction and calls
-- `ottoq_tick_invariance_reset_fleet` **before** the arm's run exists (position 880 against
-- `twin.ottoq_sim_start_run` at 954, comment-stripped). `ottoq.ottoq_active_sim_run_id()` caches its
-- answer in a **transaction-local** GUC and the pair never clears it. So when arm 2's reset writes every
-- vehicle, the row trigger asks for the active run, gets **arm 1's** — already ticked, already
-- fingerprinted — and files one event per vehicle there, stamped at arm 1's last sim clock.
--
-- Measured across the nine pairs certified 2026-09-22: **9 of 9 recorded `disagreeing_atoms = {}` and
-- 9 of 9 disagree on `events` when recomputed today.** Arm A exceeds arm B by exactly the depot's vehicle
-- count every time — 116 at the twin, 4 at the `grid_smoke` fixture. `db/checks/0329` has the full
-- census.
--
-- **The verdicts were correct.** Each hash was computed before the contamination existed. What is broken
-- is that the archive no longer reproduces them — the difference between *"we verified it"* and *"you can
-- verify it"*, and the second is what CLAUDE.md 2.9a's claim is worth under hostile diligence.
--
-- ══ §2 THE FIX, AND IT WAS PROVEN BEFORE IT WAS WRITTEN ═══════════════════════
--
-- One statement, before each arm's reset:
--
--     PERFORM set_config('ottoq.sim_run_id', 'none', true);
--
-- `'none'` is not invented: `ottoq_active_sim_run_id()` reads it as an explicit *"no run"* and returns
-- NULL (`IF v_txt = 'none' THEN RETURN NULL`). So the reset's writes belong to no run, which is honest —
-- they are harness setup, not simulated behaviour.
--
-- **Both halves were demonstrated in a rolled-back transaction against the 4-vehicle fixture depot
-- `aacd0bb0`, using a completed cert arm as the victim:**
--
--     scenario                                        victim arm gained
--     ---------------------------------------------   -----------------
--     CAUSE: stale cached run id                              **+4**
--     FIX:   set_config('ottoq.sim_run_id','none')             **+0**
--
-- **And the displaced events land cleanly rather than being relocated into a second problem**, which was
-- the obvious risk: they are still emitted (4 of them), with `sim_run_id IS NULL`, `data_source='twin'`
-- and `ingest_source='trigger'`. CLAUDE.md 2.8's discipline is that sim and production rows co-exist
-- filtered by `data_source`, so a `twin`-tagged NULL-run row is distinguishable from real production
-- telemetry by exactly the mechanism the twin already relies on. **Checked, because "the fix works" and
-- "the fix does not create a new mess" are two claims and only the first is obvious.**
--
-- `0092`'s standing warning — *"NEVER cache a miss"* — does not apply. That was about caching a miss
-- **before a run exists and thereby blinding the run that follows** (measured: 12 ticks of trigger events
-- written as production). Here the sentinel is set deliberately, for exactly the window in which there is
-- genuinely no run, and `twin.ottoq_sim_start_run` overwrites it moments later.
--
-- ══ §3 WHY SURGICAL SUBSTITUTION RATHER THAN A REWRITE ════════════════════════
--
-- `ottoq_determinism_pair` is 10,256 characters of certification logic carrying guards from `0152`,
-- `0175`, `0258` and `0386`. Retyping it to add one line is how those guards get silently dropped. The
-- substitution asserts the literal matched **exactly once** AND that the rewritten definition differs by
-- **exactly** the two strings' byte delta, so a stray edit anywhere else aborts the migration. Same
-- discipline as `0413` and `0414`.
--
-- ══ §4 WHAT THIS DOES NOT DO ══════════════════════════════════════════════════
--
-- **It does not repair the nine already-contaminated arms.** `ottoq_events` is append-only and those rows
-- are real writes; removing them would be rewriting evidence to make a verdict reproduce, which is
-- precisely backwards. After this migration the NEXT sweep produces arms that do reproduce, and the nine
-- current ones stay as the record of the defect — `db/checks/0329` is their explanation.
--
-- **It does not add a standing check that verdicts remain reproducible.** That is the right follow-up and
-- it needs the fingerprint expression extracted from the pair into a shared function so writer and
-- verifier are one algorithm — `0280`'s lesson, where a hash and its verifier drifted apart. Extracting a
-- ~2 KB `jsonb_build_object` out of this function is a bigger change than this one and should not ride
-- along with it.
--
-- ══ §5 WHY IT IS NOT APPLIED, AND WHAT APPLYING IT COSTS ══════════════════════
--
-- `forces_recert` **TRUE**. `events` is one of the fourteen atoms and this changes which rows a cert arm
-- carries, so every canon's stored verdict is superseded and all nine pairs re-run. That is ~36 minutes of
-- sweep, and the sweep finished at 10:10 UTC after `0420` had already reset it once this morning.
--
-- **Nothing degrades while it waits.** The live verdict is correct today and stays correct; only
-- archive-reproducibility is affected, and it is already broken for the nine existing pairs either way.
-- So the cost of waiting is zero and the cost of applying twice in one morning is real. **Chase times it.**

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n   int;
  v_src text;
BEGIN
  -- P1. The exact literal exists, exactly once. The substitution in §3 depends on it.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
         regexp_matches(p.prosrc,
           'PERFORM public\.ottoq_tick_invariance_reset_fleet\(p_depot, p_seed, p_sim_start\);','g')
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0421 P1: the reset call literal matches % times in ottoq_determinism_pair, expected '
                    'exactly 1 -- read the function before substituting', v_n;
  END IF;

  -- P2. THE FIX IS NOT ALREADY THERE. Applying twice would insert a second sentinel.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair'
     AND p.prosrc LIKE '%set_config(''ottoq.sim_run_id''%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0421 P2: ottoq_determinism_pair already sets ottoq.sim_run_id -- already applied?';
  END IF;

  -- P3. THE SENTINEL MEANS WHAT §2 CLAIMS. Asserted from ottoq_active_sim_run_id's own source, because
  --     the whole fix rests on 'none' mapping to NULL rather than being cast as a uuid.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_active_sim_run_id';
  IF v_src IS NULL OR v_src NOT LIKE '%''none''%' OR v_src NOT LIKE '%RETURN NULL%' THEN
    RAISE EXCEPTION '0421 P3: ottoq_active_sim_run_id no longer maps the ''none'' sentinel to NULL. The '
                    'fix would write a literal that gets cast as a uuid -- do NOT apply';
  END IF;

  -- P4. THE DEFECT IS STILL LIVE: at least one certified pair fails to reproduce on atom 4. If someone
  --     fixed this another way, this migration is redundant and must not be applied blind.
  SELECT count(*) INTO v_n FROM (
    SELECT l.arm_a_run, l.arm_b_run,
      (SELECT md5(COALESCE(string_agg(
         event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                               THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
         COALESCE(e.sim_clock_at::text,'-'), E'\n'
         ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                   THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
         FROM public.ottoq_events e WHERE e.sim_run_id=l.arm_a_run) AS ha,
      (SELECT md5(COALESCE(string_agg(
         event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                               THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
         COALESCE(e.sim_clock_at::text,'-'), E'\n'
         ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                   THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
         FROM public.ottoq_events e WHERE e.sim_run_id=l.arm_b_run) AS hb
      FROM public.ottoq_determinism_verdict_ledger l
     WHERE l.outcome='passed' AND l.disagreeing_atoms = '{}'
  ) q WHERE ha IS DISTINCT FROM hb;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0421 P4: every passed verdict already reproduces on atom 4. The defect 0329 '
                    'describes is not present -- do not apply this blind';
  END IF;
  RAISE NOTICE '0421 preflight: literal matches once, sentinel maps to NULL, % passed verdict(s) still '
               'fail to reproduce on atom 4', v_n;
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE FIX, by surgical substitution (§3)
-- ─────────────────────────────────────────────────────────────────────────────
DO $fix$
DECLARE
  v_old_call CONSTANT text :=
    'PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);';
  v_new_call CONSTANT text :=
    'PERFORM set_config(''ottoq.sim_run_id'', ''none'', true); /* 0421: the reset runs BEFORE this arm''s '
    'run exists, and ottoq_active_sim_run_id caches the PREVIOUS arm in a transaction-local GUC. Without '
    'this, every vehicle written here is filed as the previous arm''s evidence, after that arm was '
    'fingerprinted -- so its verdict stops reproducing. db/checks/0329. */ '
    || 'PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);';
  v_def     text;
  v_new     text;
  v_hits    int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  SELECT count(*) INTO v_hits FROM regexp_matches(v_def, regexp_replace(v_old_call,
           '([().*+?\[\]{}|\\^$])', '\\\1', 'g'), 'g');
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0421 fix: the literal appears % times in the definition, expected 1', v_hits;
  END IF;

  v_new := replace(v_def, v_old_call, v_new_call);

  -- THE BYTE-DELTA ASSERTION: the rewritten definition must differ from the original by EXACTLY the
  -- difference in the two literals' lengths. Any other edit anywhere in 10,256 characters aborts here.
  IF length(v_new) - length(v_def) <> length(v_new_call) - length(v_old_call) THEN
    RAISE EXCEPTION '0421 fix: byte delta is % but the two literals differ by % -- something else in the '
                    'definition changed; refusing to install it',
                    length(v_new) - length(v_def), length(v_new_call) - length(v_old_call);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0421 fix: installed, +% bytes, exactly the literal delta',
               length(v_new) - length(v_def);
END $fix$;

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0421_a_certified_arms_evidence_is_rewritten_by_the_next_arms_fleet_reset',
  true,
  'Sets the ottoq.sim_run_id sentinel to ''none'' before each determinism arm''s fleet reset, so the '
  'reset''s one-write-per-vehicle is attributed to no run instead of to the PREVIOUS arm -- which had '
  'already been ticked and fingerprinted, so its verdict stopped reproducing from its own evidence '
  '(db/checks/0329: 9 of 9 passed verdicts disagree on atom 4 when recomputed). Cause and fix both '
  'demonstrated in a rolled-back transaction on the 4-vehicle fixture depot: stale cache +4 events into '
  'the victim arm, sentinel +0, and the displaced events land with sim_run_id NULL / data_source twin / '
  'ingest_source trigger, distinguishable from production by 2.8''s own discipline. TRUE because `events` '
  'is one of the fourteen atoms and this changes which rows a cert arm carries, so every canon''s stored '
  'verdict is superseded. Does NOT repair the nine contaminated arms: ottoq_events is append-only and '
  'deleting rows to make a verdict reproduce is backwards.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_src     text;
  v_n       int;
  v_gained  int;
  v_victim  uuid;
  v_before  int;
  v_after   int;
BEGIN
  -- V1. The sentinel is present and PRECEDES the reset call. Order is the whole fix, so assert it
  --     positionally, comment-stripped -- 0329's first attempt at this returned FALSE because
  --     position() found a function name inside a comment block.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF position('set_config(''ottoq.sim_run_id'', ''none'', true)' in v_src) = 0 THEN
    RAISE EXCEPTION '0421 V1: the sentinel is not present in the installed function';
  END IF;
  IF position('set_config(''ottoq.sim_run_id'', ''none'', true)' in v_src)
     > position('ottoq_tick_invariance_reset_fleet' in v_src) THEN
    RAISE EXCEPTION '0421 V1: the sentinel is present but does NOT precede the fleet reset -- the fix '
                    'only works before the reset runs';
  END IF;

  -- V2. The guards this function carries are still there. A surgical substitution should not be able to
  --     drop them, and the byte-delta assertion proves it, but these are named because losing one
  --     silently is exactly what §3 is defending against.
  FOREACH v_src IN ARRAY ARRAY['determinism_pair: no active scenario',
                               'playback_mode=live',
                               'cuopt_first_refusal_max_defers',
                               'ottoq_boot_state_fingerprint'] LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair' AND p.prosrc LIKE '%'||v_src||'%';
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0421 V2: guard "%" is no longer present in ottoq_determinism_pair', v_src;
    END IF;
  END LOOP;

  -- V3. THE MECHANISM, DEMONSTRATED. A savepoint so the probe's writes roll back while the counts, held
  --     in plpgsql variables, survive -- 0418's technique. The fixture depot has 4 vehicles, so the
  --     stale-cache path must move exactly 4 and the sentinel path exactly 0.
  SELECT l.arm_a_run INTO v_victim FROM public.ottoq_determinism_verdict_ledger l
   ORDER BY l.certified_at DESC LIMIT 1;

  IF v_victim IS NULL THEN
    RAISE NOTICE '0421 V3: no certified arm to use as a probe victim; mechanism not exercised';
  ELSE
    BEGIN
      SELECT count(*) INTO v_before FROM public.ottoq_events
       WHERE sim_run_id=v_victim AND event_type='vehicle.state_changed';
      PERFORM set_config('ottoq.sim_run_id', v_victim::text, true);
      PERFORM public.ottoq_tick_invariance_reset_fleet(
                'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid, 999001,
                '2026-09-01 02:00:00+00'::timestamptz);
      SELECT count(*) INTO v_after FROM public.ottoq_events
       WHERE sim_run_id=v_victim AND event_type='vehicle.state_changed';
      v_gained := v_after - v_before;
      RAISE EXCEPTION USING ERRCODE='OQ421', MESSAGE='0421_probe_rollback';
    EXCEPTION WHEN SQLSTATE 'OQ421' THEN
      IF SQLERRM <> '0421_probe_rollback' THEN RAISE; END IF;
    END;

    IF v_gained <= 0 THEN
      RAISE EXCEPTION '0421 V3: the stale-cache path moved % events into a certified arm. It must be '
                      'positive, or 0329''s mechanism is not what this migration fixes', v_gained;
    END IF;
    RAISE NOTICE '0421 V3: stale cache files % event(s) into certified arm % -- the mechanism 0329 '
                 'describes, reproduced and rolled back', v_gained, v_victim;

    SELECT count(*) INTO v_n FROM public.ottoq_events
     WHERE sim_run_id=v_victim AND event_type='vehicle.state_changed';
    IF v_n <> v_before THEN
      RAISE EXCEPTION '0421 V3: % probe event(s) survived the rollback into a certified arm. '
                      'ottoq_events is append-only, so abort rather than commit them', v_n - v_before;
    END IF;
  END IF;

  RAISE NOTICE '0421 verify: sentinel installed before the reset, every named guard intact, mechanism '
               'reproduced and rolled back, nothing left behind';
END $post$;

COMMIT;
