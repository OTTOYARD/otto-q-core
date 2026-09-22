-- migration-version: 20260922150552
-- migration-name:    a_charger_heartbeat_written_after_the_charge_starts_is_a_liveness_check_that_cannot_pass
--
-- 0424  **`HW.002.charger_state_precondition` is `critical`/`block` and CANNOT PASS on the twin. Across
--       all 4,632 twin-depot failures the gap between the rule's own recorded `now_ts` and its own
--       `last_heartbeat_at` is min = max = 1800 s — ONE distinct value, zero variance — against
--       `max_offline_seconds = 90`. Diagnosed in `db/checks/0337` §5.**
--
--       1800 s is one tick. Both tick orchestrators write `last_heartbeat_at = <the tick's sim clock>`,
--       and both do it **AFTER** the tick's charge reconciliation, so every charge-session start reads
--       the PREVIOUS tick's heartbeat. Measured positions in the comment-stripped source:
--       `twin.ottoq_world_advance` reconcile @2171 / heartbeat @4483;
--       `public.ottoq_sim_advance_tick_world` reconcile @2963 / heartbeat @5375.
--
--       `forces_recert` **TRUE**: `rules` is one of the fourteen atoms, and this changes HW.002's verdict
--       on every charge-session start in a run.
--
-- ══ §1 WHAT THE FIX IS, AND WHY IT IS THE TWIN AND NOT THE RULE ═══════════════
--
-- One statement per orchestrator: write the tick's heartbeats **before** the tick's charge work instead
-- of after. The existing late write is LEFT IN PLACE and becomes idempotent — same column, same row set,
-- same value (`v_now` / `v_new_sim_clock` is fixed for the whole tick), so the second write is a no-op
-- rewrite. Nothing is moved and nothing is deleted; one write is added earlier.
--
-- **The rejected alternative was to raise `max_offline_seconds` above 1800, and it is worse than doing
-- nothing.** A liveness threshold wider than the twin's entire tick can never fail, so it would convert
-- a rule that always fails into a rule that always passes — trading a visibly broken check for an
-- invisibly vacuous one. `0337` §2 already counts three VACUOUS codes at `task_completion`; this would
-- have made a fourth, in a rule whose enforcement is `block`.
--
-- **The other rejected alternative was to teach the evaluator the tick length** (tolerate staleness up
-- to one tick). That puts a simulation concept inside the L1 shield, which `ottoyarddepot-sim/AGENTS.md`
-- names as the thing that breaks the swap test — *"If you build a code path that only works because
-- this is a simulation, you have broken the pitch"* — and is the same design `0423` §3 rejected for the
-- `twin_harness` actor. The shield must not know it is in a simulation.
--
-- **So the defect is in the twin's device model, which is where it belongs.** A real OCPP charger
-- heartbeats every 60–300 s; one twin tick is 1800 sim-seconds, during which a real charger would have
-- sent roughly thirty. The twin's liveness resolution is therefore one tick, and the only faithful
-- representation of "this charger is alive at sim instant T" is a heartbeat stamped T — which is what
-- the early write produces. `max_offline_seconds = 90` keeps its production meaning untouched.
--
-- ══ §2 WHY THIS DOES NOT MAKE HW.002 VACUOUS — THE PART THAT MATTERS ══════════
--
-- Both writes carry `WHERE ... AND station_state <> 'Faulted'`. **A faulted charger is deliberately not
-- heartbeated**, so its `last_heartbeat_at` stays behind and HW.002 goes on failing for it — which is
-- precisely the condition the rule exists to catch, and precisely what `0372` established as the third
-- availability gate (~13.8% of charger-time on a busy_day run is lost to faults, and 6 of the twin's 45
-- chargers were `Faulted` at the Part 3 reading).
--
-- So the rule moves from *"fails on 100% of evaluations, discriminating nothing"* to *"fails exactly on
-- faulted chargers"*. **V3 asserts this directly rather than trusting it**: after the fix, a probe against
-- a Faulted charger must still fail. A migration that made a `block` rule unable to fail would be a
-- regression dressed as a fix.
--
-- ══ §3 WHAT THIS DOES NOT FIX, STATED SO IT IS NOT ASSUMED ════════════════════
--
--   1. **The 4,632 historical failures are not repaired.** `ottoq_rule_evaluations` is append-only, so
--      the lifetime rate falls only as new evaluations accumulate. Any future reading of HW.002 must be
--      windowed on this migration's apply — the standing rule from `0334`.
--   2. **Nothing here makes the probe ENFORCE.** `twin.ottoq_sim_start_charge_session` still calls the
--      shield with `PERFORM` and still discards `would_block` (`0337` §3, G149). This migration removes
--      the reason the discard was load-bearing at this one probe point; promoting the probe is a separate
--      decision under 2.9a's blind-spot doctrine, and it is still blocked by HW.003 (G150b), which fires
--      at `task_completion` and is untouched here.
--   3. **HW.003's tautology is untouched.** Its staleness equals the atom's own duration; that is a
--      different defect with a different fix.
--
-- ══ §4 PRE-FLIGHT, SUBSTITUTION, VERIFICATION ═════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is still exactly as measured. Zero variance is the whole claim. ──
DO $$
DECLARE v_n int; v_min int; v_max int; v_distinct int; v_thresh int;
BEGIN
  SELECT count(*),
         min(EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                               - (result_payload->>'last_heartbeat_at')::timestamptz)))::int,
         max(EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                               - (result_payload->>'last_heartbeat_at')::timestamptz)))::int,
         count(DISTINCT EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                               - (result_payload->>'last_heartbeat_at')::timestamptz))::int),
         max((result_payload->>'max_offline_seconds')::int)
    INTO v_n, v_min, v_max, v_distinct, v_thresh
    FROM public.ottoq_rule_evaluations
   WHERE action_context='charge_session_start'
     AND rule_code='HW.002.charger_state_precondition'
     AND NOT passed
     AND depot_id='11111111-1111-1111-1111-111111111111'
     AND result_payload ? 'now_ts';

  IF v_n < 100 THEN
    RAISE EXCEPTION '0424 P1: only % HW.002 failures carrying now_ts -- the ledger was purged or the '
                    'defect changed. Re-derive db/checks/0337 §5 before applying.', v_n;
  END IF;
  IF v_distinct <> 1 OR v_min <> 1800 OR v_max <> 1800 THEN
    RAISE EXCEPTION '0424 P1: the gap is no longer a constant 1800s (min=% max=% distinct=%). The '
                    'zero-variance finding is what justifies this fix; without it, STOP and re-measure.',
                    v_min, v_max, v_distinct;
  END IF;
  IF v_thresh >= 1800 THEN
    RAISE EXCEPTION '0424 P1: max_offline_seconds is already % (>= one tick), so somebody took the '
                    'rejected widening path. Reconcile with §1 before applying.', v_thresh;
  END IF;
  RAISE NOTICE '0424 P1: % failures, gap constant %s against threshold %s -- defect confirmed',
               v_n, v_min, v_thresh;
END $$;

-- ── P2: the twin depot still feeds sim, so the write we are moving actually runs. ──
DO $$
DECLARE v_mode text;
BEGIN
  SELECT COALESCE(feed_mode,'sim') INTO v_mode FROM public.depots
   WHERE id='11111111-1111-1111-1111-111111111111';
  IF v_mode <> 'sim' THEN
    RAISE EXCEPTION '0424 P2: twin depot feed_mode is %, not sim -- the heartbeat write is gated off '
                    'and this migration would change nothing', v_mode;
  END IF;
END $$;

-- ── P3: no run in flight, and no determinism pair (G141: a pair is invisible to ottoq_sim_runs). ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0424 P3: % run(s) running/paused -- apply between runs', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0424 P3b: a determinism pair is in flight (invisible to ottoq_sim_runs -- G141). '
                    'Only pg_stat_activity is honest about this. Wait for the sweep.';
  END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0424_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname='twin'   AND p.proname='ottoq_world_advance')
    OR (n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world');

-- ── P4: md5 guard. Assert the live definitions are the ones this change was derived from.
-- If either was hotfixed in the SQL editor since, raise rather than silently discard the fix.
-- The expected md5s are asserted by COUNT rather than by literal, because the two substitutions
-- below re-derive from pg_get_functiondef and the anchor-hit + byte-delta checks are what pin the
-- edit; what this guard adds is that the snapshot above captured exactly two rows to revert to.
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_schema_snapshots WHERE label='0424_pre';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0424 P4: snapshot captured % rows, expected 2 (twin.ottoq_world_advance and '
                    'public.ottoq_sim_advance_tick_world) -- there is no clean revert point', v_n;
  END IF;
  SELECT count(DISTINCT def_md5) INTO v_n FROM public.ottoq_schema_snapshots WHERE label='0424_pre';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0424 P4: the two snapshotted definitions are not distinct -- wrong objects captured';
  END IF;
  RAISE NOTICE '0424 P4: both orchestrators snapshotted as 0424_pre';
END $$;

-- ── (A) twin.ottoq_world_advance: heartbeat before the charge block ──
DO $$
DECLARE
  v_def    text;
  v_new    text;
  v_anchor text;
  v_insert text;
  v_hits   int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_world_advance';
  IF v_def IS NULL THEN RAISE EXCEPTION '0424 (A): twin.ottoq_world_advance not found'; END IF;

  v_anchor := E'  IF v_feed_sim THEN\n  BEGIN PERFORM ottoq_sim_reconcile_charge_sessions(v_run.sim_run_id, v_now);';

  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0424 (A): anchor matched % times, expected exactly 1 -- the function was '
                    'reformatted; re-read pg_get_functiondef and re-derive the anchor', v_hits;
  END IF;

  -- 0424: the tick's heartbeats are stamped BEFORE the tick's charge work, because HW.002 asks
  -- "is this charger alive at the instant of this decision" and the answer must be about THIS
  -- tick. The late write below is left in place and is now an idempotent rewrite of the same
  -- value. `station_state <> 'Faulted'` is deliberate and load-bearing: a faulted charger keeps
  -- a stale heartbeat so HW.002 still refuses it (0337 section 5, verified by V3).
  v_insert := E'  IF v_feed_sim THEN\n'
           || E'  BEGIN UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_now\n'
           || E'          WHERE depot_id = v_run.depot_id AND station_state <> ''Faulted'';\n'
           || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance early heartbeat: %'', SQLERRM; END;\n'
           || E'  END IF;\n'
           || v_anchor;

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0424 (A): byte delta % <> expected % -- refusing a substitution that did more '
                    'than one replacement', length(v_new) - length(v_def),
                    length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0424 (A): twin.ottoq_world_advance installed, +% bytes', length(v_new) - length(v_def);
END $$;

-- ── (B) public.ottoq_sim_advance_tick_world: same, at its own anchor ──
DO $$
DECLARE
  v_def    text;
  v_new    text;
  v_anchor text;
  v_insert text;
  v_hits   int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world';
  IF v_def IS NULL THEN RAISE EXCEPTION '0424 (B): ottoq_sim_advance_tick_world not found'; END IF;

  v_anchor := E'    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);';

  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0424 (B): anchor matched % times, expected exactly 1', v_hits;
  END IF;

  -- 0424: see (A). This anchor already sits inside the function's `IF v_feed_sim THEN` branch
  -- (its ELSE sets v_charge_adv), so no re-gating is needed here.
  v_insert := E'    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock\n'
           || E'     WHERE depot_id = v_run.depot_id AND station_state <> ''Faulted'';\n'
           || v_anchor;

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0424 (B): byte delta % <> expected %',
                    length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0424 (B): ottoq_sim_advance_tick_world installed, +% bytes',
               length(v_new) - length(v_def);
END $$;

-- ── V1: both orchestrators now write the heartbeat BEFORE the charge reconciliation ──
DO $$
DECLARE r record; v_bad int := 0;
BEGIN
  FOR r IN
    SELECT n.nspname||'.'||p.proname AS fn,
           regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS s
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE (n.nspname='twin'   AND p.proname='ottoq_world_advance')
        OR (n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world')
  LOOP
    IF position('SET last_heartbeat_at' in r.s) = 0
       OR position('ottoq_sim_reconcile_charge_sessions' in r.s) = 0
       OR position('SET last_heartbeat_at' in r.s)
          > position('ottoq_sim_reconcile_charge_sessions' in r.s) THEN
      v_bad := v_bad + 1;
      RAISE WARNING '0424 V1: % still writes the heartbeat after the charge work', r.fn;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0424 V1: % orchestrator(s) still ordered wrongly', v_bad;
  END IF;
  RAISE NOTICE '0424 V1: both orchestrators heartbeat before the charge block';
END $$;

-- ── V2: the late write still exists in both. Nothing was moved or deleted. ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE ((n.nspname='twin'   AND p.proname='ottoq_world_advance')
       OR (n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world'))
     AND (length(p.prosrc) - length(replace(p.prosrc, 'SET last_heartbeat_at', '')))
         / length('SET last_heartbeat_at') = 2;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0424 V2: expected both orchestrators to carry exactly TWO heartbeat writes '
                    '(the new early one and the original late one); % do. A missing late write means '
                    'the substitution moved code instead of adding it.', v_n;
  END IF;
  RAISE NOTICE '0424 V2: both orchestrators carry two heartbeat writes -- nothing was moved';
END $$;

-- ── V3: HW.002 CAN STILL FAIL. A block rule that cannot fail is a regression. ──
-- Faulted chargers are excluded from both writes by design, so the rule must still refuse them.
-- Probed against a real faulted charger where one exists; asserted structurally otherwise.
DO $$
DECLARE v_res public.ottoq_rule_result; v_charger record; v_params jsonb;
BEGIN
  SELECT c.charger_id, c.ocpp_identifier, c.last_heartbeat_at
    INTO v_charger
    FROM public.ottoq_ocpp_chargers c
   WHERE c.station_state = 'Faulted' LIMIT 1;

  SELECT COALESCE(r.default_parameters, '{}'::jsonb) INTO v_params
    FROM public.ottoq_rules r
   WHERE r.rule_code='HW.002.charger_state_precondition' AND r.status='active' LIMIT 1;

  IF v_charger.charger_id IS NULL THEN
    -- No faulted charger to probe right now. Assert the exclusion clause is present in both
    -- writes instead, which is the mechanism V3 exists to protect.
    IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE ((n.nspname='twin'   AND p.proname='ottoq_world_advance')
             OR (n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world'))
           AND (length(p.prosrc) - length(replace(p.prosrc, 'station_state <> ''Faulted''', '')))
               / length('station_state <> ''Faulted''') >= 2) <> 2 THEN
      RAISE EXCEPTION '0424 V3: no faulted charger to probe AND the Faulted exclusion is not present '
                      'twice in both orchestrators -- HW.002 may now be unable to fail';
    END IF;
    RAISE NOTICE '0424 V3: no faulted charger present; Faulted exclusion asserted structurally in both';
  ELSE
    -- Signature is (p_entity_type, p_entity_id, p_context, p_parameters); the evaluator resolves the
    -- charger out of p_context, so the entity pair is passed for shape only.
    --
    -- `now_ts` is deliberately the charger's OWN last_heartbeat_at, making staleness exactly 0. A
    -- faulted charger's heartbeat is also stale, so probing with a real clock would fail on the
    -- liveness branch and V3 would pass for a reason that has nothing to do with what it asserts.
    -- Zeroing the staleness leaves `station_state` as the only branch that can refuse -- which is
    -- the mechanism (the `<> 'Faulted'` exclusion in both writes) V3 exists to protect.
    v_res := public.ottoq_eval_hw_002_charger_state(
               'stall', NULL::uuid,
               jsonb_build_object('charger_id', v_charger.charger_id::text,
                                  'now_ts',     v_charger.last_heartbeat_at::text),
               v_params);
    IF v_res.passed THEN
      RAISE EXCEPTION '0424 V3: HW.002 PASSED a Faulted charger (%) at zero staleness -- the rule can '
                      'no longer refuse a faulted charger, which is a worse defect than the one this '
                      'migration fixes', v_charger.ocpp_identifier;
    END IF;
    IF v_res.reason NOT LIKE '%state=Faulted%' THEN
      RAISE EXCEPTION '0424 V3: HW.002 refused Faulted charger % but for the wrong reason (%) -- at '
                      'zero staleness the refusal must name the station state, or this assertion is '
                      'not testing the Faulted exclusion', v_charger.ocpp_identifier, v_res.reason;
    END IF;
    RAISE NOTICE '0424 V3: HW.002 refuses Faulted charger % on its STATE at zero staleness -- the rule '
                 'still discriminates', v_charger.ocpp_identifier;
  END IF;
END $$;

COMMIT;

-- ══ §5 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE, so the canon matrix must resweep before any determinism claim is quoted.
--
-- Then window HW.002 on the apply and expect the failure rate at `charge_session_start` to fall from
-- 100%-of-evaluations to approximately the faulted-charger share (~14% of charger-time per `0372`):
--
--   SELECT count(*) AS evals,
--          count(*) FILTER (WHERE NOT passed) AS failed,
--          round(100.0*count(*) FILTER (WHERE NOT passed)/count(*),2) AS pct_failed,
--          count(DISTINCT EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
--                        - (result_payload->>'last_heartbeat_at')::timestamptz))::int) AS distinct_gaps
--     FROM public.ottoq_rule_evaluations
--    WHERE rule_code='HW.002.charger_state_precondition'
--      AND action_context='charge_session_start'
--      AND depot_id='11111111-1111-1111-1111-111111111111'
--      AND evaluated_at >= '<this migration's apply timestamp>';
--
-- **Read `distinct_gaps` as the real signal, not the percentage.** Before the fix it is 1; after the fix
-- a healthy charger's gap is 0 and a faulted one's is whatever its fault duration is, so the count must
-- be > 1. A rate can fall for many reasons; the gap losing its zero variance can only mean the ordering
-- changed.

-- ══ APPLIED ═══════════════════════════════════════════════════════════════════
--
-- **Applied 2026-09-22 15:05:52 UTC (10:05 AM CT) as `20260922150552`.** All eight blocks ran:
-- P1 confirmed the defect live (4,632 failures, gap constant 1800 s, threshold 90 s), P2 confirmed
-- `feed_mode='sim'`, P3/P3b confirmed no run and no pair in flight, P4 snapshotted both orchestrators
-- as `0424_pre`, (A) and (B) installed, V1/V2/V3 passed.
--
-- **DEVIATION, declared per APPLYING.md step 4.** The apply channel takes SQL inline, so the submitted
-- text is this file with whole-line `--` comments and the one psql meta-command removed. The executable
-- halves were **proven identical by digest before applying**, not assumed: comment-stripped and
-- whitespace-collapsed, both sides give **`89b6c002b9e2e9119eb2db46d6e4123c` at 9,479 characters**, and
-- the only opcode difference between the normalised file and the normalised submission is the deletion
-- of `\set ON_ERROR_STOP on` — which is a psql directive, not SQL, and cannot be submitted.
--
-- **VERIFIED independently of the migration's own asserts**, re-reading the catalog afterwards:
--
--     fn                                 first_heartbeat_write  charge_work  heartbeat_first  writes  faulted_excl
--     ---------------------------------  ---------------------  -----------  ---------------  ------  ------------
--     public.ottoq_sim_advance_tick_world                 2,982        3,103            true       2             2
--     twin.ottoq_world_advance                            2,190        2,434            true       2             2
--
-- Before the migration those positions were 5,375 / 2,963 and 4,483 / 2,171 — heartbeat AFTER the charge
-- work in both. `writes = 2` is V2's claim confirmed from outside: the original late write is still
-- there, so this added a statement rather than moving one.
--
-- **`ottoq_cert_lineage` row inserted with `forces_recert = true`**, which moved the recert floor to
-- 2026-09-22 15:06:22.746274+00 and put **9 of 9 canon columns into `NOT satisfies_floor`**. Job 746
-- resweeps them; no determinism claim may be quoted until it lands.
--
-- **NOT YET VERIFIED, and this is the number that actually settles it:** the post-apply HW.002 failure
-- rate and — more importantly — `distinct_gaps > 1`. §5's query is the one to run once the resweep has
-- generated fresh `charge_session_start` evaluations. Until then this migration is "applied and
-- structurally verified", not "shown to have fixed the rule". Those are different claims and the
-- difference is the whole of `db/checks/0337`.
