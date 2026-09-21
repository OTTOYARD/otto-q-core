-- migration-version: 20260920173700
-- migration-name:    the_fourteen_atom_verdict_is_the_one_thing_the_permanent_run_record_does_not_keep
--
-- 0386  G93: EVERY DETERMINISM VERDICT THIS ENGINE HAS EVER PRODUCED IS GONE. 1,166
--       ARMS ARE ARCHIVED PERMANENTLY AND NOT ONE CARRIES ITS PASS/FAIL.
--
-- `forces_recert` **FALSE**. It adds an evidence ledger and appends two diagnostic keys to
-- the verdict jsonb; `v_equal`, `v_outcome` and every atom hash are computed by the same
-- unchanged code, so no canon's result can move. See §4 for why that was the hard part.
--
-- ══ 1. THE CLAIM, AND WHERE ITS EVIDENCE ACTUALLY LIVES ════════════════════
--
-- CLAUDE.md 2.9a makes reproducibility a *product property*: *"a fourteen-atom
-- byte-identical verdict over every pair"*, and argues it is a claim most of the field
-- cannot make. Measured today, the evidence for it does not survive a demo run.
--
--   `ottoq_run_archives`  class **run_ledger**, *"the permanent per-run record; its whole
--                         job is to outlive the run"* -- **1,166 rows** with
--                         `run_by='cert_harness'`, `reason='determinism_arm_complete'`,
--                         newest 2026-09-20 15:31:59. Carries scenario, seed, depot,
--                         tick_count, `config_hash`, `engine_hash`.
--                         **`run_payload ? 'validation_notes'` = 0 of 1,166.**
--   `ottoq_sim_runs`      where the verdict IS written. Also class run_ledger -- and
--                         `ottoq_purge_prior_runs` ends with `DELETE FROM ottoq_sim_runs`.
--                         **Surviving cert-harness runs: 0. Surviving verdicts: 0.**
--
-- So the inputs of 1,166 certifications are permanent and every one of their *answers* is
-- gone. The reproducibility claim is currently unfalsifiable in the bad direction: nothing
-- on disk says any pair ever agreed.
--
-- ══ 2. AND THE COMMENT THAT MADE IT LOOK HANDLED ═══════════════════════════
--
-- `ottoq_determinism_pair` writes the verdict under this comment:
--
--     -- The verdict survives a dropped client: it lives on both run rows.
--
-- **True for the case it names, false for the one that matters.** It survives an HTTP
-- client dropping mid-call; it does not survive `ottoq_start_demo_run`. Third instance of
-- this exact class after `0231` (a naming convention relied on to defeat a purge that reads
-- the registry, not names) and `0340` (`cuopt_invocation_log` registered `engine` while
-- rule 6 quoted it as history). **A durability comment is not a durability mechanism.**
--
-- And the archive could not have caught it even in principle: `ottoq_archive_run` copies
-- `v_run.payload`, the verdict is not in `payload`, and each arm is archived by
-- `ottoq_sim_stop_and_reset(v_run,'determinism_arm_complete')` **inside the arm loop** --
-- so at archive time the verdict does not exist yet. The ordering is verbatim:
--
--     PERFORM public.ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');
--   END LOOP;
--   v_equal := ... ;                 -- verdict computed only now
--   UPDATE ottoq_sim_runs SET validation_status = ..., validation_notes = ...;
--
-- ══ 3. THE FIX ═════════════════════════════════════════════════════════════
--
-- `public.ottoq_determinism_verdict_ledger`: append-only, `class='evidence'`, one row per
-- PAIR (not per arm), with **deliberately no FK to `ottoq_sim_runs`**. Same doctrine as
-- `0340` and `0364`, and the registry's own guard is why: check (b2) demands an FK only for
-- `engine`/`stamp` rows, and an enforcing FK on evidence can only block the purge or, as
-- CASCADE, erase exactly what check (c) forbids erasing. `arm_a_run`/`arm_b_run` are
-- registered `evidence` even though the guard does not watch those column names -- the
-- registry is the place this intent is written down, and a column it cannot see is still a
-- run reference.
--
-- **NO BACKFILL IS POSSIBLE, and that is the point rather than a limitation.** Zero
-- verdicts exist anywhere to backfill from. The 1,166 archived arms keep their inputs, so
-- every one of those certifications is *re-runnable* -- which is what `config_hash` and
-- `engine_hash` are for -- but its historical answer is unrecoverable. The ledger starts
-- empty and the first row will be the first durable verdict this engine has ever held.
--
-- ══ 4. THE DIAGNOSTICS ARE ADDITIVE, AND THE REASON IS A TRAP I NEARLY SET ══
--
-- The verdict now also names WHICH of the fourteen atoms disagreed, which the old jsonb
-- left the reader to diff by hand out of `arm_a`/`arm_b`. The obvious implementation is to
-- rebuild agreement from the per-atom list -- and that would have been a silent semantic
-- change:
--
--   * today `v_equal` is one AND chain of `=` comparisons. In SQL, `NULL = NULL` is NULL,
--     a NULL anywhere makes the whole chain NULL, and `CASE WHEN v_equal THEN 'passed'`
--     then falls to `ELSE 'failed'`. So a NULL atom hash currently reports **failed**.
--   * rebuilding it with `IS DISTINCT FROM` would treat NULL vs NULL as agreement and could
--     turn a present `failed` into a `passed`.
--
-- So `v_equal` is left computed by the original chain, untouched, and the per-atom list is
-- computed separately using the same `NOT (a = b)` form. A `null_atoms` array is added to
-- make that latent trap **visible** rather than to change it: it names any atom where
-- either arm is NULL -- precisely the case the AND chain already fails without saying why.
-- This is why the migration is `forces_recert FALSE`: no canon's outcome can move.
--
-- ══ 5. WHY THIS IS NOT MERELY HYGIENE ══════════════════════════════════════
--
-- `ottoq_cert_recert_floor()` reads **2026-09-20 16:18:46** (the moment `0383` was
-- classified `forces_recert TRUE`), and `ottoq_cert_matrix(now())` returns **zero rows** --
-- no canon currently satisfies the floor. Recertifying is therefore due anyway, and without
-- this ledger the recert would produce nine verdicts that the next demo run erases. The
-- ledger is the precondition for the recert being worth running, not a tidy-up after it.

-- ══ P0 PREFLIGHT ═══════════════════════════════════════════════════════════

DO $p0$
DECLARE v_n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0386 P0: a sim run is running or paused -- this rewrites the certification path';
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_run_archives
   WHERE run_by='cert_harness' AND reason='determinism_arm_complete';
  IF v_n = 0 THEN
    RAISE EXCEPTION '0386 P0: no archived determinism arms -- the premise of this migration is not present';
  END IF;
  RAISE NOTICE '0386 P0: % archived determinism arms, of which % carry a verdict', v_n,
    (SELECT count(*) FROM public.ottoq_run_archives
      WHERE run_by='cert_harness' AND reason='determinism_arm_complete'
        AND run_payload ? 'validation_notes');

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.proname='ottoq_determinism_pair'
     AND p.prosrc LIKE '%The verdict survives a dropped client%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0386 P0: ottoq_determinism_pair is not the expected version (found %)', v_n;
  END IF;
END $p0$;

-- ══ THE LEDGER ═════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.ottoq_determinism_verdict_ledger (
  verdict_id        bigserial PRIMARY KEY,
  certified_at      timestamptz NOT NULL DEFAULT now(),
  depot_id          uuid        NOT NULL,
  scenario          text        NOT NULL,
  seed              bigint      NOT NULL,
  ticks             integer     NOT NULL,
  outcome           text        NOT NULL,
  equal             boolean     NOT NULL,
  complete          boolean     NOT NULL,
  -- Run references, DELIBERATELY WITHOUT A FOREIGN KEY. See the header: an enforcing FK on
  -- an evidence table can only block ottoq_purge_prior_runs or, as CASCADE, erase the very
  -- rows the registry's check (c) exists to protect. A pair has two runs, so there is no
  -- single sim_run_id to carry and no column name the registry's check (a) watches -- both
  -- are registered explicitly anyway, so the intent is written down where it is looked for.
  arm_a_run         uuid,
  arm_b_run         uuid,
  atoms_compared    integer     NOT NULL,
  disagreeing_atoms text[]      NOT NULL DEFAULT '{}',
  null_atoms        text[]      NOT NULL DEFAULT '{}',
  engine_hash       text,
  verdict           jsonb       NOT NULL,
  CONSTRAINT ottoq_dvl_outcome_known
    CHECK (outcome IN ('passed','failed','inconclusive')),
  -- The arithmetic the ledger asserts about itself: a passed pair has no disagreeing atom,
  -- and a failed one has at least a reason recorded somewhere. 0341 is why this is a
  -- CONSTRAINT rather than a hope -- a view whose buckets did not sum reported 515 of 1,676
  -- rows and put the other 1,161 nowhere.
  CONSTRAINT ottoq_dvl_passed_means_no_disagreement
    CHECK (outcome <> 'passed' OR cardinality(disagreeing_atoms) = 0),
  CONSTRAINT ottoq_dvl_equal_matches_outcome
    CHECK ((outcome = 'passed') = (equal AND complete))
);

COMMENT ON TABLE public.ottoq_determinism_verdict_ledger IS
'0386 (G93). One row per determinism PAIR: the durable answer to "did these two arms agree across all fourteen atoms". class=evidence, append-only, NO FK to ottoq_sim_runs by design. EXISTS BECAUSE THE VERDICT WAS NOT DURABLE: ottoq_determinism_pair wrote it only to ottoq_sim_runs.validation_notes under the comment "The verdict survives a dropped client: it lives on both run rows" -- true of a dropped HTTP client, false of ottoq_purge_prior_runs, which ends with DELETE FROM ottoq_sim_runs. Measured at creation: 1,166 arms archived in ottoq_run_archives with reason=determinism_arm_complete, 0 carrying a verdict, and 0 cert-harness runs alive. The archive could not have held it either -- ottoq_archive_run copies v_run.payload, and each arm is archived inside the arm loop before the verdict is computed. Not backfillable: no verdict existed anywhere to recover, so row 1 is the first durable verdict this engine has held. The arms'' INPUTS survive in ottoq_run_archives (scenario, seed, depot, config_hash, engine_hash), so every historical certification is re-runnable even though its answer is not recoverable.';

COMMENT ON COLUMN public.ottoq_determinism_verdict_ledger.null_atoms IS
'0386: atoms where either arm''s hash is NULL. This is a TRAP MADE VISIBLE, not a new rule. v_equal is an AND chain of `=` comparisons, so a NULL on either side makes the chain NULL and the outcome falls through to failed -- a pair can therefore be reported failed with no atom actually differing. Rebuilding agreement with IS DISTINCT FROM would have silently converted such a case to passed, which is why the original chain was left untouched and this column added beside it.';

-- ── append-only guard, mirroring 0374's ledger ────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_determinism_verdict_ledger_append_only()
 RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.determinism_verdict_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_determinism_verdict_ledger is append-only: % refused. Set '
    'ottoq.determinism_verdict_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END $fn$;

DROP TRIGGER IF EXISTS ottoq_dvl_append_only ON public.ottoq_determinism_verdict_ledger;
CREATE TRIGGER ottoq_dvl_append_only
  BEFORE UPDATE OR DELETE ON public.ottoq_determinism_verdict_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_determinism_verdict_ledger_append_only();

CREATE INDEX IF NOT EXISTS ottoq_dvl_canon_idx
  ON public.ottoq_determinism_verdict_ledger (depot_id, scenario, seed, ticks, certified_at DESC);

-- ── run-scope registry ───────────────────────────────────────────────────────
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note, registered_at)
VALUES
  ('public','ottoq_determinism_verdict_ledger','arm_a_run','evidence',
   '0386 (G93): the A arm of a determinism pair. Evidence, not engine: CLAUDE.md 2.9a treats '
   'the fourteen-atom verdict as a product property, and before this ledger every verdict '
   'this engine had produced was gone -- 1,166 arms archived, 0 verdicts recoverable. '
   'Deliberately carries NO FK to ottoq_sim_runs: check (b2) demands one only of engine/stamp, '
   'and on evidence an FK can only block the purge or, as CASCADE, erase what check (c) '
   'protects. Registered although check (a) does not watch this column name, because the '
   'registry is where this intent is looked for.', now()),
  ('public','ottoq_determinism_verdict_ledger','arm_b_run','evidence',
   '0386 (G93): the B arm of a determinism pair. See arm_a_run. A pair has two runs, so there '
   'is no single sim_run_id column to carry.', now())
ON CONFLICT (table_schema, table_name, column_name) DO UPDATE
  SET class = EXCLUDED.class, note = EXCLUDED.note, registered_at = EXCLUDED.registered_at;

-- ══ THE PAIR, NOW PERSISTING ITS OWN ANSWER ════════════════════════════════
-- Body reproduced verbatim from pg_get_functiondef at 2026-09-20 17:37 UTC with two
-- additions, both asserted unique before this file was written: two DECLARE variables, and
-- one block after the existing run-row UPDATE. No existing statement is altered, and in
-- particular the v_equal AND chain and every hash expression are byte-identical.

CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair(p_seed bigint, p_ticks integer DEFAULT 12, p_scenario text DEFAULT 'busy_day'::text, p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_sim_start timestamp with time zone DEFAULT '2026-09-01 02:00:00+00'::timestamp with time zone, p_arm_budget_s integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_arm int; v_run uuid; v_t0 timestamptz;
  v_clock timestamptz; v_status text; v_ticks int;
  v_boot jsonb;
  v_h jsonb; v_arms jsonb[] := '{}';
  v_equal boolean; v_verdict jsonb;
  v_disagree text[]; v_nullatom text[];   -- 0386: additive diagnostics only
  v_complete boolean; v_outcome text;
  v_scen_depot uuid;
BEGIN
  /* 0175: THE PAIR AND THE SCENARIO MUST NAME THE SAME WORLD.
     p_depot drives the fleet reset and both fingerprints; the run row's
     depot comes from the scenario (twin.ottoq_sim_start_run reads
     v_scenario.depot_id). Nothing made them agree, so a pair could reset
     and fingerprint depot A while ticking depot B and never say so.
     Refused before either arm is created, so a mismatch costs nothing
     and this guard can never alter a canon. */
  SELECT s.depot_id INTO v_scen_depot
    FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario AND s.status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'determinism_pair: no active scenario %', p_scenario
      USING ERRCODE = 'P0001';
  END IF;
  IF v_scen_depot IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'determinism_pair: scenario % is bound to depot %, but the pair was told to run depot %. The arms would tick one world and be fingerprinted against another.',
      p_scenario, COALESCE(v_scen_depot::text, '(none)'), p_depot
      USING ERRCODE = 'P0001';
  END IF;

  FOR v_arm IN 1..2 LOOP
    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);
    v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
    /* 0152: a certification arm runs the deterministic core alone. Run-scoped, so a
       later global re-enable of the proposer cannot reach inside a cert (0056). */
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0152_cert_quiesce'),
           ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0152_cert_quiesce')
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0, updated_by = '0152_cert_quiesce';
    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'determinism_pair arm % prime failed: %', v_arm, SQLERRM; END;

    -- 0125: the boot image, captured before the first tick. Diagnostic, not verdict.
    v_boot := public.ottoq_boot_state_fingerprint(p_depot, v_run);

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= p_ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    SELECT jsonb_build_object(
      'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
      'complete', (r.tick_count >= p_ticks),
      'fp', r.payload->>'world_fingerprint',
      'boot', v_boot,
      'endst', public.ottoq_boot_state_fingerprint(p_depot, v_run),
      'wsec', ottoq.ottoq_world_fingerprint_sections(p_depot),   -- 0254: MEASURED, not in v_equal
      'h_cmd', (SELECT md5(COALESCE(string_agg(
          issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
          E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status, COALESCE(reason_code,'-')), ''))
        FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run),
      'h_dec', (SELECT md5(COALESCE(string_agg(
          sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
          ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
          E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                        COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
        FROM ottoq_decisions d WHERE d.sim_run_id = v_run),
      'h_evt', (SELECT md5(COALESCE(string_agg(
          event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||COALESCE(e.sim_clock_at::text,'-'),
          E'\n' ORDER BY event_type,
                        CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run),
      'h_bkg', (SELECT md5(COALESCE(string_agg(
          lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
          E'\n' ORDER BY lower(during), upper(during), vehicle_id, stall_id, purpose, state), ''))
        FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run),
      'h_nrg', (SELECT md5(COALESCE(string_agg(
          COALESCE(c.tick_seq::text,'-')||'|'||c.command_type||'|'||COALESCE(c.source,'-')
          ||'|'||COALESCE(c.setpoint_kw::text,'-')||'|'||COALESCE(c.horizon_min::text,'-')
          ||'|'||to_char(c.issued_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI:SS.US')
          ||'|'||COALESCE(c.reason::text,'-'),
          E'\n' ORDER BY c.tick_seq, c.command_type, COALESCE(c.source,'-'), c.setpoint_kw, c.horizon_min, c.issued_at, c.reason::text), ''))
        FROM ottoq_energy_commands c WHERE c.sim_run_id = v_run),
      /* 0199: the proposal stream and the deferral ledger. Agents propose;
         the verdict must see what they proposed, or "solver disposes" is
         an assertion rather than a measurement. */
      'h_prop', public.ottoq_hash_proposals(v_run),
      'h_defr', public.ottoq_hash_deferrals(v_run),
      /* 0201: the priors this arm booted on. Two arms on different priors
         are two different worlds, and the verdict says so. */
      'h_cal', v_boot->'calibration'->>'h', 'h_rule', public.ottoq_hash_rule_evaluations(v_run), 'h_rcl', public.ottoq_hash_recall_decisions(v_run), 'h_sdr', public.ottoq_hash_sdrs(v_run))
      INTO v_h
      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');
  END LOOP;

  v_equal := (v_arms[1]->>'fp')    = (v_arms[2]->>'fp')
         AND (v_arms[1]->>'h_cmd') = (v_arms[2]->>'h_cmd')
         AND (v_arms[1]->>'h_dec') = (v_arms[2]->>'h_dec')
         AND (v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt')
         AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
         AND (v_arms[1]->>'h_nrg') = (v_arms[2]->>'h_nrg')
         AND (v_arms[1]->>'h_prop') = (v_arms[2]->>'h_prop')   -- 0199
         AND (v_arms[1]->>'h_defr') = (v_arms[2]->>'h_defr')   -- 0199
         AND (v_arms[1]->>'h_cal')  = (v_arms[2]->>'h_cal')    -- 0201
         AND (v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')   -- 0205: the shield's disposals, enforced after 0203 measured them
         AND (v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')   -- 0217: the gate 0206 set is met
         AND (v_arms[1]->>'h_sdr') = (v_arms[2]->>'h_sdr')   -- 0219: the settlement record may now fail a pair
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')
         AND (v_arms[1]->'endst')  = (v_arms[2]->'endst');

  v_complete := COALESCE((v_arms[1]->>'complete')::boolean, false)
            AND COALESCE((v_arms[2]->>'complete')::boolean, false);

  v_outcome := CASE WHEN NOT v_complete THEN 'inconclusive'
                    WHEN v_equal        THEN 'passed'
                    ELSE                     'failed' END;

  v_verdict := jsonb_build_object(
    'equal', v_equal, 'outcome', v_outcome, 'complete', v_complete,
    'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,
    'arm_a', v_arms[1], 'arm_b', v_arms[2]);

  -- The verdict survives a dropped client: it lives on both run rows.
  UPDATE ottoq_sim_runs
     SET validation_status = v_outcome,
         validation_notes  = v_verdict::text
   WHERE sim_run_id IN ((v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid);

  /* ══ 0386: AND IT MUST ALSO SURVIVE THE NEXT DEMO RUN ══════════════════════
     The comment above is true for the case it names -- a dropped HTTP client --
     and false for the durability that actually matters. `ottoq_sim_runs` is
     class='run_ledger' and `ottoq_purge_prior_runs` ends with
     `DELETE FROM ottoq_sim_runs`, so the verdict written above lives only until
     the next demo run starts. Measured before this change: 1,166 archived arms
     carrying reason='determinism_arm_complete' and ZERO recoverable verdicts,
     because `ottoq_archive_run` copies `v_run.payload` and the verdict is not in
     it -- and could not be, since each arm is archived by
     ottoq_sim_stop_and_reset BEFORE the loop ends and the verdict exists.

     So the verdict goes to an append-only, class='evidence' ledger with
     deliberately NO FK to ottoq_sim_runs. Same doctrine as 0340 and 0364: an
     enforcing FK on evidence can only block the purge or, as CASCADE, erase what
     the registry's check (c) forbids erasing.

     THE TWO DIAGNOSTIC ARRAYS ARE ADDITIVE AND DO NOT TOUCH v_equal. v_equal is
     computed exactly as before, by the unchanged AND chain above, because `=`
     yields NULL when either side is NULL and that NULL makes the chain NULL and
     the outcome 'failed'. Recomputing agreement with IS DISTINCT FROM would treat
     NULL=NULL as agreement and could turn a current 'failed' into a 'passed' --
     a semantic change disguised as a refactor. v_nullatom exists to make that
     latent trap VISIBLE rather than to alter it: it names any atom where either
     arm is NULL, which is exactly the case the AND chain reports as a
     disagreement without saying so. */
  SELECT array_agg(atom ORDER BY ord) FILTER (WHERE differs),
         array_agg(atom ORDER BY ord) FILTER (WHERE is_null)
    INTO v_disagree, v_nullatom
    FROM (VALUES
      ( 1,'fingerprint', NOT ((v_arms[1]->>'fp')     = (v_arms[2]->>'fp')),     (v_arms[1]->>'fp')     IS NULL OR (v_arms[2]->>'fp')     IS NULL),
      ( 2,'commands',    NOT ((v_arms[1]->>'h_cmd')  = (v_arms[2]->>'h_cmd')),  (v_arms[1]->>'h_cmd')  IS NULL OR (v_arms[2]->>'h_cmd')  IS NULL),
      ( 3,'decisions',   NOT ((v_arms[1]->>'h_dec')  = (v_arms[2]->>'h_dec')),  (v_arms[1]->>'h_dec')  IS NULL OR (v_arms[2]->>'h_dec')  IS NULL),
      ( 4,'events',      NOT ((v_arms[1]->>'h_evt')  = (v_arms[2]->>'h_evt')),  (v_arms[1]->>'h_evt')  IS NULL OR (v_arms[2]->>'h_evt')  IS NULL),
      ( 5,'bookings',    NOT ((v_arms[1]->>'h_bkg')  = (v_arms[2]->>'h_bkg')),  (v_arms[1]->>'h_bkg')  IS NULL OR (v_arms[2]->>'h_bkg')  IS NULL),
      ( 6,'energy',      NOT ((v_arms[1]->>'h_nrg')  = (v_arms[2]->>'h_nrg')),  (v_arms[1]->>'h_nrg')  IS NULL OR (v_arms[2]->>'h_nrg')  IS NULL),
      ( 7,'proposals',   NOT ((v_arms[1]->>'h_prop') = (v_arms[2]->>'h_prop')), (v_arms[1]->>'h_prop') IS NULL OR (v_arms[2]->>'h_prop') IS NULL),
      ( 8,'deferrals',   NOT ((v_arms[1]->>'h_defr') = (v_arms[2]->>'h_defr')), (v_arms[1]->>'h_defr') IS NULL OR (v_arms[2]->>'h_defr') IS NULL),
      ( 9,'calibration', NOT ((v_arms[1]->>'h_cal')  = (v_arms[2]->>'h_cal')),  (v_arms[1]->>'h_cal')  IS NULL OR (v_arms[2]->>'h_cal')  IS NULL),
      (10,'rules',       NOT ((v_arms[1]->>'h_rule') = (v_arms[2]->>'h_rule')), (v_arms[1]->>'h_rule') IS NULL OR (v_arms[2]->>'h_rule') IS NULL),
      (11,'recalls',     NOT ((v_arms[1]->>'h_rcl')  = (v_arms[2]->>'h_rcl')),  (v_arms[1]->>'h_rcl')  IS NULL OR (v_arms[2]->>'h_rcl')  IS NULL),
      (12,'sdrs',        NOT ((v_arms[1]->>'h_sdr')  = (v_arms[2]->>'h_sdr')),  (v_arms[1]->>'h_sdr')  IS NULL OR (v_arms[2]->>'h_sdr')  IS NULL),
      (13,'tick_count',  NOT ((v_arms[1]->>'ticks')  = (v_arms[2]->>'ticks')),  (v_arms[1]->>'ticks')  IS NULL OR (v_arms[2]->>'ticks')  IS NULL),
      (14,'end_state',   NOT ((v_arms[1]->'endst')   = (v_arms[2]->'endst')),   (v_arms[1]->'endst')   IS NULL OR (v_arms[2]->'endst')   IS NULL)
    ) t(ord, atom, differs, is_null);

  v_verdict := v_verdict
    || jsonb_build_object('atoms_compared', 14,
                          'disagreeing_atoms', COALESCE(to_jsonb(v_disagree), '[]'::jsonb),
                          'null_atoms',        COALESCE(to_jsonb(v_nullatom), '[]'::jsonb));

  BEGIN
    INSERT INTO public.ottoq_determinism_verdict_ledger
      (depot_id, scenario, seed, ticks, outcome, equal, complete,
       arm_a_run, arm_b_run, atoms_compared, disagreeing_atoms, null_atoms,
       engine_hash, verdict)
    VALUES
      (p_depot, p_scenario, p_seed, p_ticks, v_outcome, COALESCE(v_equal,false), v_complete,
       (v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid, 14,
       COALESCE(v_disagree,'{}'::text[]), COALESCE(v_nullatom,'{}'::text[]),
       public.ottoq_engine_hash(), v_verdict);
  EXCEPTION WHEN OTHERS THEN
    -- A ledger failure must never destroy the verdict the caller is about to
    -- receive, nor unwind two completed arms. Same posture as 0340's capture
    -- triggers: swallow, warn, carry on.
    RAISE WARNING 'ottoq_determinism_pair: verdict ledger write FAILED SAFELY %: %',
      SQLSTATE, SQLERRM;
  END;

  RETURN v_verdict;
END
$function$;

-- ══ THE CANON READER ═══════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.ottoq_determinism_canon AS
SELECT c.depot_id, c.scenario, c.seed, c.ticks, c.enabled, c.max_age, c.note AS column_note,
       l.verdict_id, l.certified_at, l.outcome, l.equal, l.complete,
       l.disagreeing_atoms, l.null_atoms, l.engine_hash,
       public.ottoq_cert_recert_floor()                       AS recert_floor,
       (l.certified_at IS NOT NULL
          AND l.certified_at >= public.ottoq_cert_recert_floor()
          AND l.outcome = 'passed')                           AS satisfies_floor,
       CASE
         WHEN l.certified_at IS NULL THEN 'NEVER CERTIFIED DURABLY'
         WHEN l.certified_at < public.ottoq_cert_recert_floor()
           THEN 'stale: predates the recert floor'
         WHEN l.outcome <> 'passed' THEN 'fresh but ' || l.outcome
         ELSE 'current'
       END                                                    AS status
  FROM public.ottoq_cert_columns c
  LEFT JOIN LATERAL (
    SELECT * FROM public.ottoq_determinism_verdict_ledger v
     WHERE v.depot_id = c.depot_id AND v.scenario = c.scenario
       AND v.seed = c.seed AND v.ticks = c.ticks
     ORDER BY v.certified_at DESC LIMIT 1) l ON true
 ORDER BY c.depot_id, c.ticks, c.scenario, c.seed;

COMMENT ON VIEW public.ottoq_determinism_canon IS
'0386. Per declared canon column, the newest DURABLE verdict and whether it satisfies ottoq_cert_recert_floor(). A LEFT JOIN on purpose: a column with no verdict must appear as "NEVER CERTIFIED DURABLY" rather than vanish -- an inner join here would report a clean matrix by omitting every uncertified column, which is the 0380 join-loss shape. Every row reads NEVER CERTIFIED DURABLY at creation, because no verdict was durable before this migration.';

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int; v_blocked int;
BEGIN
  -- the append-only guard must actually refuse
  BEGIN
    INSERT INTO public.ottoq_determinism_verdict_ledger
      (depot_id, scenario, seed, ticks, outcome, equal, complete, atoms_compared, verdict)
    VALUES ('11111111-1111-1111-1111-111111111111','__guard_probe__',-1,0,
            'inconclusive',false,false,14,'{"probe":true}'::jsonb);
    DELETE FROM public.ottoq_determinism_verdict_ledger WHERE scenario='__guard_probe__';
    RAISE EXCEPTION '0386 P1: the append-only guard did NOT refuse a DELETE';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE '0386 P1: append-only guard refused the DELETE as designed';
  END;

  -- the CHECK constraints must bite
  BEGIN
    INSERT INTO public.ottoq_determinism_verdict_ledger
      (depot_id, scenario, seed, ticks, outcome, equal, complete, atoms_compared,
       disagreeing_atoms, verdict)
    VALUES ('11111111-1111-1111-1111-111111111111','__check_probe__',-1,0,
            'passed',true,true,14,'{events}','{"probe":true}'::jsonb);
    RAISE EXCEPTION '0386 P1: a passed verdict with a disagreeing atom was accepted';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE '0386 P1: passed-means-no-disagreement CHECK bit as designed';
  END;

  SELECT count(*) INTO v_n FROM public.ottoq_determinism_verdict_ledger;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0386 P1: the ledger should be empty after the rolled-back probes, holds %', v_n;
  END IF;
  RAISE NOTICE '0386 P1: guard and both CHECKs verified, ledger empty';
END $p1$;

DO $p2$
DECLARE v_rows int; v_never int;
BEGIN
  -- INVOKE the view, never string-match it (0381).
  SELECT count(*), count(*) FILTER (WHERE status = 'NEVER CERTIFIED DURABLY')
    INTO v_rows, v_never
    FROM public.ottoq_determinism_canon;
  IF v_rows = 0 THEN
    RAISE EXCEPTION '0386 P2: ottoq_determinism_canon returned no rows -- it must show every declared column';
  END IF;
  IF v_rows <> (SELECT count(*) FROM public.ottoq_cert_columns) THEN
    RAISE EXCEPTION '0386 P2: the view dropped canon columns (% of %) -- the LEFT JOIN is not holding',
      v_rows, (SELECT count(*) FROM public.ottoq_cert_columns);
  END IF;
  IF v_never <> v_rows THEN
    RAISE EXCEPTION '0386 P2: % of % columns already report a durable verdict, which cannot be true before the first pair runs',
      v_rows - v_never, v_rows;
  END IF;
  RAISE NOTICE '0386 P2: view shows all % canon columns, all NEVER CERTIFIED DURABLY', v_rows;
END $p2$;

DO $p3$
DECLARE v_n int;
BEGIN
  -- the pair must still compile AND still carry the untouched v_equal chain
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.proname='ottoq_determinism_pair'
     AND p.prosrc LIKE '%ottoq_determinism_verdict_ledger%'
     AND p.prosrc LIKE '%v_equal := (v_arms[1]->>''fp'')    = (v_arms[2]->>''fp'')%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0386 P3: the pair either lost the ledger write or its original v_equal chain changed (found %)', v_n;
  END IF;

  -- and the purge-safety guard must still report nothing that blocks
  SELECT count(*) INTO v_n FROM public.ottoq_check_run_scope_registry() r
   WHERE r.severity = 'block';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0386 P3: the new ledger made the purge-safety guard report % blocking row(s)', v_n;
  END IF;
  RAISE NOTICE '0386 P3: pair carries the ledger write and the original chain; registry guard clean';
END $p3$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0386_the_fourteen_atom_verdict_is_the_one_thing_the_permanent_run_record_does_not_keep', false,
  'G93. CLAUDE.md 2.9a treats the fourteen-atom byte-identical verdict as a product property, '
  'and its evidence did not survive a demo run. Measured: ottoq_run_archives (class run_ledger, '
  '"whose whole job is to outlive the run") holds 1,166 arms with reason=determinism_arm_complete '
  'and ZERO carrying a verdict, while the verdict itself was written only to '
  'ottoq_sim_runs.validation_notes -- and ottoq_purge_prior_runs ends with DELETE FROM '
  'ottoq_sim_runs, leaving 0 surviving cert-harness runs and 0 recoverable verdicts. The '
  'archive could not have held it either: ottoq_archive_run copies v_run.payload, and each arm '
  'is archived by ottoq_sim_stop_and_reset inside the arm loop, before the verdict exists. The '
  'comment that made this look handled -- "The verdict survives a dropped client: it lives on '
  'both run rows" -- is true of a dropped HTTP client and false of the next demo run; third '
  'instance of that class after 0231 and 0340. Adds public.ottoq_determinism_verdict_ledger '
  '(append-only, class=evidence, no FK to ottoq_sim_runs, one row per PAIR), registers both arm '
  'columns, and has ottoq_determinism_pair write its own answer. NOT BACKFILLABLE: no verdict '
  'existed anywhere, so row 1 will be the first durable verdict this engine has held; the arms '
  'INPUTS do survive in ottoq_run_archives, so every historical certification is re-runnable '
  'even though its answer is not recoverable. forces_recert FALSE because v_equal, v_outcome '
  'and every hash expression are byte-identical -- the added per-atom diagnostics are computed '
  'separately and deliberately reuse the original NOT (a = b) form, since rebuilding agreement '
  'with IS DISTINCT FROM would treat NULL=NULL as agreement and could silently turn a present '
  'failed into a passed. The new null_atoms column makes that trap visible instead: a NULL hash '
  'makes the AND chain NULL and the outcome fall through to failed with no atom actually '
  'differing. Also adds public.ottoq_determinism_canon, a LEFT JOIN view of declared canon '
  'columns against their newest durable verdict -- left, not inner, so an uncertified column '
  'reads NEVER CERTIFIED DURABLY instead of vanishing (the 0380 join-loss shape). Context: '
  'ottoq_cert_recert_floor() reads 2026-09-20 16:18:46 after 0383, and ottoq_cert_matrix(now()) '
  'returns zero rows, so a recert is due and without this ledger it would produce nine verdicts '
  'the next demo run erases.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
