-- migration-version: 20260922163008
-- migration-name:    the_presence_rule_finally_gets_a_stall_by_probing_where_a_charge_actually_ends
--
-- 0427  **`HW.006.physical_presence_verification` asks whether the vehicle is physically in the stall, and
--       has never once been handed one. `0422` spliced the `task_completion` probe into
--       `twin.ottoq_sim_advance_visit_atoms`, which completes ONLY the concurrent classes
--       (`cabin`/`exterior`/`digital`) — none of which occupies a stall. Diagnosed in `db/checks/0343`
--       §3–§4 (G154; G122 re-opened).**
--
--       Measured on runs after `0426`: HW.006 reports *"insufficient context for presence verification"*
--       on **224 of 224**, with **zero** carrying a `stall_id`, while on those same runs **charge (242
--       completions), readiness_check (182), exterior_wash (88) and interior_deep_clean (28)** completed
--       with no `task_completion` evaluation at all.
--
--       This adds the probe where a CHARGE ends, which is the largest of those populations and the one
--       where the stall is in hand by construction.
--
--       `forces_recert` **TRUE**: `rules` is one of the fourteen atoms and this adds evaluations to every
--       run.
--
-- ══ §1 THE SITE, AND THE ORDERING CONSTRAINT THAT DECIDES IT ═════════════════
--
-- **CORRECTION, caught by this file's own P2 before anything ran.** `db/checks/0343` §5–§6 and FINDINGS
-- G154 say *"`0418`'s probe already takes `p_stall_id`, so it is a wiring job rather than a new
-- instrument."* **It does not.** `ottoq_probe_task_completion`'s signature ends at `p_ends_at`; it
-- RESOLVES the stall itself:
--
--     WHERE b.vehicle_id = p_vehicle_id AND b.need_atom = p_svc
--       AND b.state IN ('held','active','done','interrupted') ...  LIMIT 1
--
-- **Which turns out to make this simpler, not harder.** A charge HAS such a booking — 312 with
-- `need_atom='charge'` on charging stalls in the measured run — so calling the probe with
-- `p_svc := 'charge'` resolves the stall through the existing mechanism. No new parameter, no new
-- instrument. What `0422`'s site lacks is not the ability to be told a stall; it is that **non-stall atoms
-- have no booking for the resolution to find** — which is the same finding stated correctly.
--
-- **The probe MUST sit before this block**, which the close path performs:
--
--     IF NOT v_tether THEN
--       UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;
--     END IF;
--
-- `ottoq_eval_hw_006_presence_verification` reads `stalls.current_vehicle_id` and fails on
-- `IS DISTINCT FROM`. **Probe after the clear and it fails 100% of untethered closes** — a brand-new
-- `critical` false-alarm stream, the exact class `0425` and `0426` just removed 1,522 of.
--
-- **And the `IF NOT v_tether` guard is why the anchor is the whole block rather than the UPDATE.** A
-- tethered DCFC close does NOT clear the pointer here at all — the robot still holds the car — so placing
-- the probe above the block is the one position where the stall still records the vehicle on **both**
-- paths. Anchoring on the bare UPDATE would put the probe inside the untethered branch and silently skip
-- every DCFC close, which is the larger and more interesting population.
--
-- ══ §2 WHY THIS SITE BUYS TWO RULES, NOT ONE ═════════════════════════════════
--
-- `HW.003.sensor_liveness` is **charge-only by its own scope guard** (`0340`), so it has spent its life
-- either abstaining (`0426`) or firing where it had no jurisdiction. Passing `'service' := 'charge'` here
-- makes it evaluate **for real** on the one population it was written for and has never been shown.
--
-- So one probe moves **two** of `task_completion`'s five vacuous codes to meaningful. That is why this
-- site is worth more than a generic bay-exit probe, and why it goes first.
--
-- Context keys, each chosen from what its consumer actually reads rather than by convention:
--
--     p_svc := 'charge'   -- and that ONE argument does all of it, which is the correction below:
--                         --   * the probe resolves the stall itself by `need_atom = p_svc`, so 'charge'
--                         --     is what finds the charge booking and fills `stall_id` for HW.006;
--                         --   * `0426` made the probe emit BOTH `svc` and `service` from `p_svc`, so
--                         --     HW.003's charge-only scope guard (0340) is satisfied by the same value.
--     p_ends_at := v_clock -- becomes `now_ts`, the SIM clock this function already computed (0326 §1)
--
-- ══ §3 MEASURE ONLY, AND THE PREDICTION STATED BEFORE APPLYING ═══════════════
--
-- **Nothing reads the verdict.** `ottoq_shield_probe` cannot raise, and this call discards its rows with
-- `PERFORM` — the same posture as the other six non-enforcing probe points (`0337` §3, G149). That is
-- deliberate under 2.9a's blind-spot doctrine: a rule is measured before it is promoted, and HW.006 has
-- never produced a legitimate verdict to judge a promotion on.
--
-- **PREDICTION, so a failure is a finding and not a surprise:** HW.006 should **PASS** — a vehicle should
-- still be recorded at its stall when its charge completes — and HW.003 should produce real
-- charge verdicts, passing whenever SOC telemetry is fresher than 300 s.
--
--   * **If HW.006 FAILS on untethered (L2) closes**, the stall pointer is being cleared somewhere upstream
--     of this function, which is a genuine state-machine finding and is adjacent to G121.
--   * **If HW.006 FAILS only on tethered (DCFC) closes**, the tether path clears the pointer elsewhere, and
--     the honest fix is to scope the probe rather than to weaken the rule.
--   * **If HW.003 FAILS**, SOC telemetry really is stale at charge completion, which is worth knowing and
--     is exactly what a safety-critical liveness rule is for.
--
-- **None of those is a reason to unwire it.** They are the reasons to wire it.
--
-- ══ §4 WHAT IS DELIBERATELY NOT DONE ═════════════════════════════════════════
--
--   1. **The bay exit is NOT touched.** `twin.ottoq_sim_advance_service_flow` is 30,510 characters with
--      several exit paths; assuming one anchor covers them is how a probe lands somewhere it cannot be
--      answered — which is the defect this file exists to fix. Separate migration, separate read.
--   2. **`readiness_check`'s gate path is NOT touched** (182 completions) — a third path again.
--   3. **`0422`'s existing probe is LEFT IN PLACE.** It produces five vacuous codes, but removing it would
--      also remove the only `task_completion` evidence there is, and `0333`/`0343` are both derived from
--      it. An instrument that reports "nothing here" is not the same as no instrument.
--   4. **HW.006 is NOT promoted to enforcing.** Measure first.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is live — HW.006 still resolves no stall at task_completion ──
DO $$
DECLARE v_evals int; v_with_stall int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE context ? 'stall_id')
    INTO v_evals, v_with_stall
    FROM public.ottoq_rule_evaluations
   WHERE rule_code='HW.006.physical_presence_verification'
     AND action_context='task_completion'
     AND evaluated_at >= '2026-09-22 15:54:23+00';
  IF v_evals = 0 THEN
    RAISE EXCEPTION '0427 P1: no HW.006 evaluations at task_completion since 0426 -- the ledger was purged '
                    'or the probe is gone. Re-derive db/checks/0343 before applying.';
  END IF;
  IF v_with_stall <> 0 THEN
    RAISE EXCEPTION '0427 P1: % of % HW.006 evaluations already carry a stall_id -- somebody wired this. '
                    'STOP and re-read.', v_with_stall, v_evals;
  END IF;
  RAISE NOTICE '0427 P1: % HW.006 evaluations, 0 carrying a stall_id -- defect confirmed', v_evals;
END $$;

-- ── P2: the probe RESOLVES the stall itself, and a charge booking exists for it to find.
-- This block is the one that caught my own false premise: I had written in db/checks/0343 that the probe
-- "already takes p_stall_id, so this is wiring". IT DOES NOT -- its signature ends at p_ends_at and it
-- resolves the stall internally from ottoq_stall_bookings. Assert the mechanism that actually exists.
DO $$
DECLARE v_args text; v_src text; v_bookings int;
BEGIN
  SELECT pg_get_function_arguments(p.oid),
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
    INTO v_args, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_probe_task_completion';
  IF v_args IS NULL THEN RAISE EXCEPTION '0427 P2: ottoq_probe_task_completion not found'; END IF;

  IF v_src !~ 'b\.need_atom\s*=\s*p_svc' THEN
    RAISE EXCEPTION '0427 P2: the probe no longer resolves its stall via need_atom = p_svc (%) -- this '
                    'migration depends on that resolution finding the charge booking. Re-read 0418.',
                    v_args;
  END IF;
  IF position('''service''' in v_src) = 0 THEN
    RAISE EXCEPTION '0427 P2: the probe no longer emits a ''service'' key -- 0426 added it and HW.003''s '
                    'charge-only scope guard reads it. Without it HW.003 abstains and this migration buys '
                    'one rule instead of two.';
  END IF;

  SELECT count(*) INTO v_bookings
    FROM public.ottoq_stall_bookings b JOIN public.stalls st ON st.id = b.stall_id
   WHERE st.depot_id='11111111-1111-1111-1111-111111111111'
     AND b.need_atom = 'charge'
     AND b.state IN ('held','active','done','interrupted');
  IF v_bookings = 0 THEN
    RAISE EXCEPTION '0427 P2: no charge bookings carry need_atom=''charge'' on the twin depot, so the '
                    'probe would resolve no stall and this migration would change nothing.';
  END IF;
  RAISE NOTICE '0427 P2: probe resolves via need_atom = p_svc, emits ''service'', and % charge bookings '
               'exist for it to find', v_bookings;
END $$;

-- ── P3: nothing in flight (G141: a pair is invisible to ottoq_sim_runs) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0427 P3: % run(s) running/paused -- apply between runs', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0427 P3b: a determinism pair is in flight (invisible to ottoq_sim_runs -- G141). '
                    'Only pg_stat_activity is honest about this. Wait for the sweep.';
  END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0427_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='twin' AND p.proname='ottoq_sim_stop_charge_session';

-- ── THE CHANGE: probe immediately ABOVE the tether-guarded pointer clear ──
DO $$
DECLARE
  v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_stop_charge_session';
  IF v_def IS NULL THEN RAISE EXCEPTION '0427: twin.ottoq_sim_stop_charge_session not found'; END IF;

  -- The WHOLE tether block, not the bare UPDATE: anchoring on the UPDATE would place the probe inside
  -- the untethered branch and skip every DCFC close. See section 1.
  v_anchor := E'  IF NOT v_tether THEN\n'
           || E'    UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id;\n'
           || E'  END IF;';

  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0427: anchor matched % times, expected exactly 1 -- the function was reformatted; '
                    're-read pg_get_functiondef and re-derive the anchor', v_hits;
  END IF;

  -- 0427 (G154): HW.006 asks whether the vehicle is in the stall and had never been given one --
  -- 0422's probe sits on the path that completes only non-stall atoms, which have no booking to
  -- resolve. A CHARGE does: the probe finds it by `need_atom = p_svc`, so passing 'charge' is what
  -- hands HW.006 its first stall. MUST stay ABOVE the clear below: HW.006 reads stalls.current_vehicle_id,
  -- so probing after it would fail every untethered close and manufacture the false-alarm class
  -- 0425/0426 just removed. 'service' is what HW.003's charge-only scope guard reads (0340);
  -- 'svc' is what the stall resolution and every analysis query read (0418) -- both, deliberately.
  -- MEASURE ONLY: PERFORM discards the verdict, per 2.9a's blind-spot doctrine.
  -- Own handler: a probe must never abort a tick.
  v_insert := E'  BEGIN\n'
           || E'    PERFORM 1 FROM public.ottoq_probe_task_completion(\n'
           || E'      p_sim_run_id := p_sim_run_id,\n'
           || E'      p_depot_id   := (SELECT depot_id FROM stalls WHERE id = v_session.stall_id),\n'
           || E'      p_vehicle_id := v_session.vehicle_id,\n'
           || E'      p_svc        := ''charge'',\n'
           || E'      p_started_at := v_session.started_at,\n'
           || E'      p_ends_at    := v_clock);\n'
           || E'  EXCEPTION WHEN OTHERS THEN\n'
           || E'    RAISE WARNING ''ottoq_sim_stop_charge_session: task_completion probe FAILED SAFELY %: %'',\n'
           || E'      SQLSTATE, SQLERRM;\n'
           || E'  END;\n'
           || v_anchor;

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0427: byte delta % <> expected % -- refusing a substitution that did more than one '
                    'replacement', length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0427: twin.ottoq_sim_stop_charge_session installed, +% bytes',
               length(v_new) - length(v_def);
END $$;

-- ── V1: the probe is present, and it is ABOVE the pointer clear ──
DO $$
DECLARE v_src text; v_probe int; v_clear int;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_stop_charge_session';

  v_probe := position('ottoq_probe_task_completion' in v_src);
  v_clear := position('UPDATE stalls SET current_vehicle_id = NULL' in v_src);
  IF v_probe = 0 THEN RAISE EXCEPTION '0427 V1: the probe is not in the function'; END IF;
  IF v_clear = 0 THEN RAISE EXCEPTION '0427 V1: the pointer clear is gone -- re-read before trusting V1'; END IF;
  IF v_probe > v_clear THEN
    RAISE EXCEPTION '0427 V1: the probe (%) sits AFTER the pointer clear (%) -- HW.006 would fail every '
                    'untethered close, which is the exact defect this migration exists to avoid',
                    v_probe, v_clear;
  END IF;
  RAISE NOTICE '0427 V1: probe at % is above the clear at % -- ordering correct', v_probe, v_clear;
END $$;

-- ── V2: the tick path still compiles and the function is callable.
-- A syntactically valid body that errors on first call would take the charge path down, and this function
-- runs inside the world advance. Assert the plan can be built rather than waiting for a tick to find out.
DO $$
BEGIN
  PERFORM twin.ottoq_sim_stop_charge_session(
            p_session_id := '00000000-0000-0000-0000-000000000000'::uuid,
            p_reason     := 'completed');
  RAISE NOTICE '0427 V2: function executes and returns early on an unknown session (IF NOT FOUND RETURN)';
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION '0427 V2: the rewritten function raised on a no-op call (%) -- it sits on the charge '
                  'path inside the world advance, so this would take charging down', SQLERRM;
END $$;

-- ── LINEAGE. In the file and inside the transaction (see 0425's note on 0267/0271). ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0427_the_presence_rule_finally_gets_a_stall_by_probing_where_a_charge_actually_ends',
  true,
  'Probes task_completion at twin.ottoq_sim_stop_charge_session, immediately ABOVE the tether-guarded '
  '`UPDATE stalls SET current_vehicle_id = NULL`. HW.006.physical_presence_verification asks whether the '
  'vehicle is in the stall and had NEVER been handed one: 0422 spliced the probe into '
  'ottoq_sim_advance_visit_atoms, which completes only the concurrent classes (cabin/exterior/digital), '
  'none of which occupies a stall -- measured, 224 of 224 evaluations report "insufficient context" with '
  'ZERO carrying a stall_id, while charge (242), readiness_check (182), exterior_wash (88) and '
  'interior_deep_clean (28) completed unprobed on the same runs. ORDERING IS LOAD-BEARING: HW.006 reads '
  'stalls.current_vehicle_id, so a probe below the clear would fail 100% of untethered closes and '
  'manufacture the false-alarm class 0425/0426 removed 1,522 of; and the anchor is the WHOLE `IF NOT '
  'v_tether` block rather than the bare UPDATE, because anchoring on the UPDATE would put the probe inside '
  'the untethered branch and skip every DCFC close. V1 asserts the ordering permanently. The same probe '
  'gives HW.003 its first legitimate case -- it is charge-only by its scope guard (0340), so '
  '`service := charge` makes it evaluate for real on the one population it was written for -- so one probe '
  'moves TWO of five vacuous codes to meaningful. MEASURE ONLY: PERFORM discards the verdict, per 2.9a. '
  'TRUE because `rules` is one of the fourteen atoms. PREDICTION stated before applying: HW.006 should '
  'PASS (a vehicle should still be recorded at its stall when charging ends) and HW.003 should produce '
  'real charge verdicts; a failure from either is a genuine finding, NOT a reason to unwire. Does NOT '
  'touch the bay exit (advance_service_flow, 30,510 chars, several exit paths -- separate read) or the '
  'gate path, and does NOT remove 0422''s probe (an instrument reporting "nothing here" is not no '
  'instrument).')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE — resweep before quoting any determinism claim.
--
-- Then, on a fresh run, windowed on the apply (`0334`'s standing rule):
--
--   SELECT rule_code,
--          count(*) FILTER (WHERE context ? 'stall_id') AS with_stall,
--          count(*) AS evals,
--          count(*) FILTER (WHERE NOT passed) AS failed,
--          left(min(reason) FILTER (WHERE NOT passed), 90) AS a_failure
--     FROM public.ottoq_rule_evaluations
--    WHERE action_context='task_completion'
--      AND context->>'svc' = 'charge'
--      AND evaluated_at >= '<apply timestamp>'
--    GROUP BY 1 ORDER BY 1;
--
-- **`with_stall` must be non-zero — that is the whole point, and it is the first time in this engine's
-- life that HW.006 has an input.** Then read `failed` against §3's prediction, and split tethered from
-- untethered before concluding anything: `stalls.stall_kind='dcfc'` is the tethered path.
--
-- And re-run `ottoq_assert_task_completion_coverage()`: HW.006 and HW.003 should move off VACUOUS. If they
-- do not, the probe is not reaching this path — check whether `p_sim_run_id` is NULL on the close, which is
-- the one input this site does not own.
--
-- ══ APPLIED 20260922163008 (2026-09-22 16:30:08 UTC / 11:30 AM CT) ═══════════
--
-- All three preconditions passed on a clear window — **0 runs running/paused and 0 other active backends**
-- (`pg_stat_activity`, which G141 establishes is the only honest witness). P1 read **2,288** HW.006
-- evaluations at `task_completion` since `0426`, **zero** carrying a `stall_id`; P2 found the probe still
-- resolving by `need_atom = p_svc`, still emitting `'service'`, and **6,059** charge bookings on the twin
-- depot for it to find. The anchor matched **exactly once**; the byte delta equalled the insert exactly.
--
-- **V1 passed on the number that matters: the probe sits at 7,938 and the pointer clear at 8,419.** The
-- ordering this whole file is about is now asserted in the function permanently, not just at apply time.
-- V2 passed — the rewritten function returns early on an unknown session without raising.
--
-- **DEVIATION, declared, identical to `0424`/`0425`/`0426`:** whole-line comments and `\set ON_ERROR_STOP on`
-- were stripped for the inline channel. File and submission differ by exactly those characters.
--
-- **AND ONE PRECONDITION THIS FILE DID NOT CARRY, checked by hand before applying and worth recording as
-- the gap it is.** `V2` calls the function with an unknown session, which returns early — so V2 can prove
-- the body *parses* and cannot prove any name inside it *resolves*. PL/pgSQL does not resolve variable
-- names at `CREATE FUNCTION`, so a typo'd `v_clock` or `v_session.started_at` would have compiled, passed
-- V1 and V2, and raised on the first real charge close inside the world advance — caught only by the
-- `EXCEPTION WHEN OTHERS` this file adds, i.e. silently, as a WARNING nobody reads. I asserted the four
-- referenced names against `prosrc` separately (`v_clock`, `p_sim_run_id`, `v_session.vehicle_id`,
-- `v_session.started_at`, `v_session.stall_id` — all present) and the probe's signature against
-- `pg_get_function_arguments`. **THE GENERAL RULE: a smoke call that returns early proves syntax, not
-- resolution. If the splice references names, assert the names.**
--
-- **NOT YET VERIFIED:** §6's windowed query, which needs a fresh run. `with_stall` must be non-zero.
