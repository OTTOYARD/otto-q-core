-- migration-version: PENDING
-- migration-name:    the_runs_row_is_locked_without_its_key_and_taken_first_by_the_stop_door
--
-- 0724  **The live run's row is locked without its key, so a foreign-key check no longer waits for a tick; and the stop
--        door takes that row first, so it no longer deadlocks with the metronome.** (G442, G440)
--
-- ══ §1 WHY (measured 2026-10-14, read-only: the catalog, c5f4ff34's tables and the database's log; last read 20:34:50 UTC)
--
--   (a) THE FOREIGN-KEY WAIT (G442). 61 tables reference public.ottoq_sim_runs(sim_run_id), ottoq_decisions among them
--   (fk_ottoq_decisions_sim_run). Every insert into one of them checks the key with
--     SELECT 1 FROM ONLY "public"."ottoq_sim_runs" x WHERE "sim_run_id" OPERATOR(pg_catalog.=) $1 FOR KEY SHARE OF x
--   (the statement the log prints for every such wait). Three functions take the live run's row FOR UPDATE:
--     public.ottoq_sim_advance_tick_world       SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=... FOR UPDATE
--     public.ottoq_twin_inject_charger_fault    the cockpit's fault door (0552 put the run's row first)
--     twin.ottoq_report_charger_fault           the depot tech's fault door (0552, the same)
--   and FOR UPDATE is the one row lock FOR KEY SHARE conflicts with (PostgreSQL 16, "Conflicting Row-Level Locks",
--   https://www.postgresql.org/docs/16/explicit-locking.html#LOCKING-ROWS, read 2026-10-14). The metronome runs the
--   world step and then the decide step (or the cuOpt refresh) in one transaction and commits after both, so while a beat
--   is in flight every insert from another session that references the live run waits for the beat to commit.
--   On c5f4ff34 (239 agent passes, each released by its decision row; ottoq_tick_clock_log for the world step):
--     decision inserts that began inside a world step             36   waited a mean 4.14 s (p50 4.26, p90 6.16, max 8.13)
--     began in the 5 s after a decide beat's world step ended      27   mean 1.76 s, 12 over a second, max 7.345 s
--     the other 176                                                     mean 0.07 s, max 0.57 s, none over a second
--   (the wait is the decision's created_at to its pass's evidence row; the beat's commit is not logged, so the second
--   row's window is a bound, not a measurement of the decide half). The world step's own logged end is a mean 0.48 s
--   after those 36 inserts began, so they waited for the beat's commit, not the world step's end. The 7.345 s is pass
--   797, the "7.35-second decision insert" 0450 §5 left as its own question: its insert began 0.78 s after tick 364's
--   world step ended, inside that beat's decide step. The in-flight lease releases on the decision row (0450 §5), so the
--   next chain waited too.
--   The log (log_lock_waits; a line only after the 1 s deadlock_timeout), 16:42:40-17:50:00 UTC, c5f4ff34's life: on the
--   live run's row, 78 "still waiting" lines were foreign-key checks (50 PostgREST, among them the agent's decision rows
--   and proposal batches; 28 pg_cron, ottoq_cron_tick -> cuopt_log_gate's INSERT INTO cuopt_invocation_log), against 25
--   for the metronome's own FOR UPDATE and 4 others. And two of the day's four deadlocks had a foreign-key check as their
--   logged edge: 16:38:05 UTC, ottoq_cron_tick -> ottoq_cuopt_defer_arm's INSERT INTO ottoq_cuopt_deferrals (run
--   703616ed) against the metronome's beat; 17:34:06 UTC, the agent's ottoq_proposer_submit_batch ->
--   ottoq_submit_external_proposal INSERT INTO ottoq_external_proposals (c5f4ff34) against the pg_cron session that
--   held the row (its next log line is the decide path's ottoq_activate_due_bay_reservations). 0552's G285 was this
--   shape too: the fault door's OCPP frame insert checking the key against the tick's FOR UPDATE.
--
--   (b) THE STOP DOOR'S DEADLOCK (G440, 0450 §6), from the log. public.ottoq_sim_stop_and_reset disposes the run's
--   pending proposals (ottoq_dispose_external_proposals(run, NULL, NULL, true), an UPDATE of ottoq_external_proposals) and
--   only then updates the run's row (ottoq_sim_mark_stopped). The metronome's beat locks the run's row first (the world
--   step's first statement) and writes the same proposals in its decide step (ottoq_decide_tick's UPDATE ...
--   SET status='enacted', its dispose, or the seat proposer's supersede). One order each way, so a stop during a beat is
--   a cycle:
--     16:42:42.981 UTC  door (operator start -> run_scenario line 81 -> stop_and_reset -> mark_stopped) waits on the
--                       metronome's transaction 33080312 for the run's row (25,17) of 1f325969; the metronome waits on
--                       the door's transaction 33080341 "while updating tuple (1674,1) in relation
--                       ottoq_external_proposals" at ottoq_decide_tick line 1228. The metronome's decide is the victim.
--     16:40:04.205 UTC  the same door edge on the run's row (1,28); the metronome's edge was not logged (the door was
--                       chosen first). It was released before decide_tick's line 53 (its next line, 0.2 s later), and the
--                       only rows the door had written by then were the run's proposals (and their disposition-ledger
--                       rows). The decide step writes those before decide_tick too (ottoq_service_priority_propose ->
--                       ottoq_submit_external_proposal supersedes a car's pending proposal by UPDATE), so that is the
--                       likely edge; it is not in the log. The door is the victim.
--   Nothing else in the door's transaction is in the cycle: ottoq_operator_start_run's advisory lock (the recert
--   runner's key) is taken by no function on the metronome's path (the census of pg_advisory* calls: the metronome takes
--   none), and ottoq_sim_run_scenario writes nothing the beat writes before it reaches the stop (an ON CONFLICT DO
--   NOTHING on ottoq_scenarios, which only it and twin.ottoq_grid_fixture_create write; the rest are reads).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Four anchored patches, each anchor asserted to match exactly once, each function md5-guarded:
--   1-3. The three FOR UPDATE sites take FOR NO KEY UPDATE. That lock conflicts with itself, with FOR UPDATE and with every
--        UPDATE and DELETE (the same table), so ticks still serialize with each other and with both fault doors, and
--        0552's order (the door waits for the beat) holds; it does not conflict with FOR KEY SHARE, so a key check from
--        another session no longer waits for the beat.
--   4.   ottoq_sim_stop_and_reset takes the run's row FOR NO KEY UPDATE before it disposes the proposals: the beat's order.
--        A stop during a beat now waits for the beat to commit and then disposes what is left; a beat that starts during a
--        stop waits for the stop. It takes the row under the 8 s mark_stopped already gives the same row, and puts the
--        caller's lock_timeout back before the teardown goes on, so every other statement runs under the setting it ran
--        under before (mark_stopped still sets 8 s from there on, as it did). The fix is in the stop, so every caller
--        gets it: the operator start (through ottoq_sim_run_scenario), the cockpit's Stop, the governor, the metronome's
--        own ceiling stop, and the harness arms that stop their own runs.
--   Nothing else in any of the four moves (V1 reverses each patch and compares the whole definition, header included,
--   with the snapshot). The tick path stays total: a lock statement adds no branch, and a lock wait that runs out raises
--   where the same row's lock already raised before (mark_stopped's UPDATE; the world step's FOR UPDATE).
--
-- ══ §3 PER SITE: IS THE ROW'S KEY, OR A DELETE, EVER AT STAKE? ═══════════════════════════════════════════════════════
--
--   FOR NO KEY UPDATE promises that the holder will not delete the row or change a key column. The key columns, for a row
--   lock, are those under a unique index a foreign key can use, partial and expression indexes excluded (the page above):
--   here sim_run_id (the primary key) and sim_run_seq (unique); ottoq_one_running_run_per_depot is partial (P2 asserts
--   the set). Comment-stripped over public, twin and ottoq, no UPDATE of ottoq_sim_runs assigns either column, and the
--   one DELETE of the table is ottoq_purge_prior_runs (prior runs, called by the demo start), which none of the four
--   functions reaches (P2 asserts both). So:
--     the world step         reads the row, then UPDATEs clock, tick count, payload, status and ended_at: no key
--     the cockpit fault door reads the row; writes chargers, sessions, stalls: no write to the run's row at all
--     the tech's fault door  reads the running run's id and clock: no write to the run's row at all
--     the stop door          mark_stopped UPDATEs status, ended_at, next_tick_due_at, failure_reason: no key
--   And if one ever did, PostgreSQL takes the stronger lock at that statement (waiting for any key check then), so the
--   weaker mode can cost a wait there, never a wrong row.
--
-- ══ §4 forces_recert FALSE; forces_dial_restart FALSE ════════════════════════════════════════════════════════════════
--
--   A row lock decides only which other sessions wait; within one transaction FOR UPDATE and FOR NO KEY UPDATE return
--   the same row with the same values, and the lock statement added to the stop door reads nothing into any variable.
--   Every certified output is computed inside one function call, so inside one transaction: ottoq_determinism_pair runs
--   both arms in one, and so do the dial and A/B pairs and the sweep and tick-invariance arms. The run row an arm ticks
--   is one it inserted itself and has not committed, which no other session can see, and every harness that stops a run
--   stops its own (stop_and_reset(v_run, '..._arm_complete'), read 2026-10-14). So none of the four locks has ever waited
--   inside an arm, before this file or after it: an arm reads, decides and writes the same rows, at the same moments,
--   and none of the fourteen atoms reads a lock. lock_timeout is put back to what it was. Dial pairs score KPIs from the
--   same single-transaction arms: FALSE. Live runs change in timing only, which live playback already turns into a
--   different world after tick 1 (0416's noise floor): an insert that waited for a beat now commits during it, and a
--   later statement of that beat may read it (READ COMMITTED, as rows committed before the beat took the row already
--   could), so a proposal that lands mid-beat can be disposed one beat sooner. 0552 changed two of these sites' locks and
--   was FALSE/FALSE.
--
-- ══ §5 NOT IN THIS FILE ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - A writer of the run's row still waits for a whole beat: ottoq_agent_chain_claim (the lease, by design), the stop
--     door, ottoq_set_playback. Only key checks stop waiting.
--   - G441 (a two-step start races the first tick) is untouched.
--   - The doors outside these four that write into a live run (vehicle commands, approvals) are not swept (0552 §4).
--
-- ══ §6 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE each definition in ottoq_schema_snapshots WHERE label = '0724_pre' (four rows);
--   DELETE FROM ottoq_cert_lineage WHERE name = '0724_the_runs_row_is_locked_without_its_key_and_taken_first_by_the_stop_door'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0724 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the four definitions this file patches ──
DO $pins$
DECLARE v_md5 text; r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_sim_advance_tick_world(uuid)', '3e0ddbb1b097587bc2c0e9135d7895aa'),
      ('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)', '0cd92ef247e8959fda68b2e6087bd944'),
      ('twin.ottoq_report_charger_fault(uuid,text,text,text)', 'a4339948b3520016e9979dc13faac605'),
      ('public.ottoq_sim_stop_and_reset(uuid,text)', 'bc8ee182436dfcd6bd53f62547ad5d5e')) AS t(sig, md5)
  LOOP
    v_md5 := md5(pg_get_functiondef(r.sig::regprocedure));
    IF v_md5 IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0724 P1: % is not the definition this file was written against (md5 %)', r.sig, v_md5;
    END IF;
  END LOOP;
END $pins$;

-- ── P2: the premises §3 and §1 (b) rest on ──
DO $premises$
DECLARE v_keys text; v_n int; v_fns text; v_src text; v_world int; v_decide int;
BEGIN
  -- the key columns a row lock sees: unique, not partial, not an expression
  SELECT string_agg(a.attname, ',' ORDER BY a.attname) INTO v_keys
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
   WHERE i.indrelid = 'public.ottoq_sim_runs'::regclass AND i.indisunique AND i.indpred IS NULL AND i.indexprs IS NULL;
  IF v_keys IS DISTINCT FROM 'sim_run_id,sim_run_seq' THEN
    RAISE EXCEPTION '0724 P2: ottoq_sim_runs''s key columns are %, not sim_run_id and sim_run_seq', v_keys;
  END IF;
  IF to_regclass('twin.ottoq_sim_runs') IS NOT NULL OR to_regclass('ottoq.ottoq_sim_runs') IS NOT NULL THEN
    RAISE EXCEPTION '0724 P2: an ottoq_sim_runs outside public would capture the unqualified names below';
  END IF;
  -- no UPDATE of the table assigns a key column; the one DELETE is the prior-run purge
  SELECT count(*), string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_n, v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'UPDATE\s+(public\.)?ottoq_sim_runs\M[^;]*?(\mSET|,)\s*(\w+\.)?(sim_run_id|sim_run_seq)\s*=', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_n > 0 THEN
    RAISE EXCEPTION '0724 P2: % UPDATE(s) of ottoq_sim_runs assign a key column (%)', v_n, v_fns;
  END IF;
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs\M';
  IF v_fns IS DISTINCT FROM 'public.ottoq_purge_prior_runs' THEN
    RAISE EXCEPTION '0724 P2: the functions that delete ottoq_sim_runs rows are %, not the prior-run purge alone', v_fns;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid IN ('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure,
                              'public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure,
                              'twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure,
                              'public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure,
                              'public.ottoq_sim_mark_stopped(uuid,text)'::regprocedure,
                              'public.ottoq_demo_metronome(integer)'::regprocedure)
                AND p.prosrc ~* 'ottoq_purge_prior_runs') THEN
    RAISE EXCEPTION '0724 P2: one of the functions this file reasons about calls the prior-run purge';
  END IF;
  -- the stop's second edge: mark_stopped updates the run's row; dispose writes the proposals
  IF regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_sim_mark_stopped(uuid,text)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+ottoq_sim_runs\s+SET\s+status'
     OR regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+public\.ottoq_external_proposals\s' THEN
    RAISE EXCEPTION '0724 P2: mark_stopped no longer updates the run''s row, or dispose no longer writes the proposals';
  END IF;
  -- the beat's order: the world step before the decide step, with no COMMIT between them
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_demo_metronome(integer)'::regprocedure;
  v_world := strpos(v_src, 'public.ottoq_sim_advance_tick_world(');
  v_decide := strpos(v_src, 'public.ottoq_sim_decide_and_dispatch(');
  IF v_world = 0 OR v_decide <= v_world OR substr(v_src, v_world, v_decide - v_world) ~* '\mCOMMIT\M' THEN
    RAISE EXCEPTION '0724 P2: the metronome no longer runs the world step and then the decide step in one transaction';
  END IF;
  -- and the decide step writes the proposals (the metronome's second edge)
  IF regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
       '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') !~* 'UPDATE\s+ottoq_external_proposals\s+p\s+SET\s+status\s*=\s*''enacted''' THEN
    RAISE EXCEPTION '0724 P2: ottoq_decide_tick no longer enacts proposals by UPDATE';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0724_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure,
                 'public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)'::regprocedure,
                 'twin.ottoq_report_charger_fault(uuid,text,text,text)'::regprocedure,
                 'public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure)
 ORDER BY n.nspname, p.proname;

-- ── the patches: each anchor asserted to match exactly once ──
CREATE FUNCTION pg_temp.p0724_patch(p_sig text, p_anchor text, p_new text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_def text := pg_get_functiondef(p_sig::regprocedure);
BEGIN
  IF (length(v_def) - length(replace(v_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
    RAISE EXCEPTION '0724: an anchor in % does not match exactly once: %', p_sig, left(p_anchor, 80);
  END IF;
  RETURN replace(v_def, p_anchor, p_new);
END $fn$;

DO $sub$
DECLARE
  v_world_a constant text := $a$  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
$a$;
  v_world_n constant text := $n$  -- 0724 (G442): FOR NO KEY UPDATE, the mode the row's own updates take. It still serializes ticks with each other
  -- and with the doors (it conflicts with itself and with every UPDATE and DELETE), but it no longer makes a foreign-key
  -- check against this run (an agent's decision row, a proposal, an OCPP frame) wait for the beat to commit.
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR NO KEY UPDATE;
$n$;
  v_inject_a constant text := $a$    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id
     FOR UPDATE;
$a$;
  v_inject_n constant text := $n$    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id
     FOR NO KEY UPDATE;   -- 0724 (G442): the mode the tick takes; the order above is unchanged
$n$;
  v_report_a constant text := $a$   WHERE depot_id = v_depot AND status='running' ORDER BY started_at DESC LIMIT 1
     FOR UPDATE;
$a$;
  v_report_n constant text := $n$   WHERE depot_id = v_depot AND status='running' ORDER BY started_at DESC LIMIT 1
     FOR NO KEY UPDATE;   -- 0724 (G442): the mode the tick takes; the order above is unchanged
$n$;
  v_stop_a1 constant text := $a$DECLARE v_marked boolean;
$a$;
  v_stop_n1 constant text := $n$DECLARE v_marked boolean;
  v_lock_prev text := current_setting('lock_timeout');   -- 0724 (G440)
$n$;
  v_stop_a2 constant text := $a$  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);
$a$;
  v_stop_n2 constant text := $n$  -- 0724 (G440): THE RUN'S ROW FIRST, in the mode the tick takes it, before the proposals. The metronome's beat locks
  -- this row first and then writes the run's proposals; this door disposed the proposals first and then waited for the
  -- row in ottoq_sim_mark_stopped, so a stop during a beat deadlocked with it (2026-10-14 16:40:04 and 16:42:42 UTC).
  -- Under the 8 s mark_stopped gives the same row; the caller's lock_timeout is back for the rest of the teardown.
  PERFORM set_config('lock_timeout', '8000', true);
  PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id FOR NO KEY UPDATE;
  PERFORM set_config('lock_timeout', v_lock_prev, true);
  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);
$n$;
BEGIN
  EXECUTE pg_temp.p0724_patch('public.ottoq_sim_advance_tick_world(uuid)', v_world_a, v_world_n);
  EXECUTE pg_temp.p0724_patch('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)', v_inject_a, v_inject_n);
  EXECUTE pg_temp.p0724_patch('twin.ottoq_report_charger_fault(uuid,text,text,text)', v_report_a, v_report_n);
  EXECUTE pg_temp.p0724_patch('public.ottoq_sim_stop_and_reset(uuid,text)', v_stop_a1, v_stop_n1);
  EXECUTE pg_temp.p0724_patch('public.ottoq_sim_stop_and_reset(uuid,text)', v_stop_a2, v_stop_n2);
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

DO $v$
DECLARE
  v_n int; v_fns text; v_src text; v_lock int; v_dispose int; v_mark int; v_set8 int; v_restore int;
  r record;
BEGIN
  --: V1 nothing else moved: undoing each patch gives back the snapshot byte for byte (header included, so SECURITY
  --:    DEFINER and the search_path are proven unchanged; CREATE OR REPLACE keeps the grants)
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_sim_advance_tick_world(uuid)', 'ottoq_sim_advance_tick_world',
       $n$  -- 0724 (G442): FOR NO KEY UPDATE, the mode the row's own updates take. It still serializes ticks with each other
  -- and with the doors (it conflicts with itself and with every UPDATE and DELETE), but it no longer makes a foreign-key
  -- check against this run (an agent's decision row, a proposal, an OCPP frame) wait for the beat to commit.
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR NO KEY UPDATE;
$n$, $a$  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
$a$, '', ''),
      ('public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)', 'ottoq_twin_inject_charger_fault',
       $n$     FOR NO KEY UPDATE;   -- 0724 (G442): the mode the tick takes; the order above is unchanged
$n$, $a$     FOR UPDATE;
$a$, '', ''),
      ('twin.ottoq_report_charger_fault(uuid,text,text,text)', 'ottoq_report_charger_fault',
       $n$     FOR NO KEY UPDATE;   -- 0724 (G442): the mode the tick takes; the order above is unchanged
$n$, $a$     FOR UPDATE;
$a$, '', ''),
      ('public.ottoq_sim_stop_and_reset(uuid,text)', 'ottoq_sim_stop_and_reset',
       $n$  v_lock_prev text := current_setting('lock_timeout');   -- 0724 (G440)
$n$, '',
       $n$  -- 0724 (G440): THE RUN'S ROW FIRST, in the mode the tick takes it, before the proposals. The metronome's beat locks
  -- this row first and then writes the run's proposals; this door disposed the proposals first and then waited for the
  -- row in ottoq_sim_mark_stopped, so a stop during a beat deadlocked with it (2026-10-14 16:40:04 and 16:42:42 UTC).
  -- Under the 8 s mark_stopped gives the same row; the caller's lock_timeout is back for the rest of the teardown.
  PERFORM set_config('lock_timeout', '8000', true);
  PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id FOR NO KEY UPDATE;
  PERFORM set_config('lock_timeout', v_lock_prev, true);
$n$, '')) AS t(sig, name, new1, old1, new2, old2)
  LOOP
    IF replace(replace(pg_get_functiondef(r.sig::regprocedure), r.new1, r.old1), r.new2, r.old2)
       IS DISTINCT FROM (SELECT s.definition FROM public.ottoq_schema_snapshots s
                          WHERE s.label = '0724_pre' AND s.object_name = r.name
                          ORDER BY s.snapshot_id DESC LIMIT 1) THEN
      RAISE EXCEPTION '0724 V1 FAILED: % changed by more than its row lock', r.sig;
    END IF;
  END LOOP;

  --: V2 the catalog, comment-stripped: no statement takes ottoq_sim_runs FOR UPDATE, and the four sites take it FOR NO
  --:    KEY UPDATE
  SELECT count(*), string_agg(n.nspname || '.' || p.proname, ', ') INTO v_n, v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'ottoq_sim_runs\M[^;]*?\mFOR\s+UPDATE\M', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0724 V2 FAILED: % statement(s) still take ottoq_sim_runs FOR UPDATE (%)', v_n, v_fns;
  END IF;
  SELECT count(*), string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY n.nspname, p.proname) INTO v_n, v_fns
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g'),
                        'ottoq_sim_runs\M[^;]*?\mFOR\s+NO\s+KEY\s+UPDATE\M', 'gi') m
   WHERE n.nspname IN ('public', 'twin', 'ottoq');
  IF v_fns IS DISTINCT FROM 'public.ottoq_sim_advance_tick_world, public.ottoq_sim_stop_and_reset, public.ottoq_twin_inject_charger_fault, twin.ottoq_report_charger_fault' THEN
    RAISE EXCEPTION '0724 V2 FAILED: the FOR NO KEY UPDATE sites on ottoq_sim_runs are %', v_fns;
  END IF;

  --: V3 the stop door, comment-stripped: 8 s, the row, the caller's timeout back, then the proposals, then mark_stopped
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p WHERE p.oid = 'public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure;
  v_set8 := strpos(v_src, 'set_config(''lock_timeout'', ''8000'', true)');
  v_lock := strpos(v_src, 'FOR NO KEY UPDATE');
  v_restore := strpos(v_src, 'set_config(''lock_timeout'', v_lock_prev, true)');
  v_dispose := strpos(v_src, 'ottoq_dispose_external_proposals(');
  v_mark := strpos(v_src, 'ottoq_sim_mark_stopped(');
  IF NOT (0 < v_set8 AND v_set8 < v_lock AND v_lock < v_restore AND v_restore < v_dispose AND v_dispose < v_mark) THEN
    RAISE EXCEPTION '0724 V3 FAILED: the stop door does not take the run''s row first under 8 s and then dispose';
  END IF;
  RAISE NOTICE '0724 V1-V3 PASSED: the three FOR UPDATE sites take FOR NO KEY UPDATE, the stop door takes the run''s row before the proposals, and nothing else moved';
END $v$;

-- ── V4: the patched statements run (no run and no charger match, so nothing is locked or written) ──
DO $vrun$
DECLARE v_done boolean; v_res jsonb; v_none constant uuid := '00000000-0000-0000-0000-000000000724';
BEGIN
  SELECT out_completed INTO v_done FROM public.ottoq_sim_advance_tick_world(v_none);
  v_res := public.ottoq_twin_inject_charger_fault(v_none);
  IF v_done IS DISTINCT FROM true OR v_res ->> 'reason' IS DISTINCT FROM 'run_not_found' THEN
    RAISE EXCEPTION '0724 V4 FAILED: the world step or the fault door did not answer a run that does not exist (%, %)', v_done, v_res;
  END IF;
  RAISE NOTICE '0724 V4 PASSED: the world step and the cockpit fault door run their patched statement and answer a run that does not exist';
END $vrun$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0724_the_runs_row_is_locked_without_its_key_and_taken_first_by_the_stop_door', false, false,
  'G442: the world step and both charger-fault doors took the live run''s ottoq_sim_runs row FOR UPDATE, the one row '
  'lock a foreign-key check (FOR KEY SHARE) waits on, so every insert from another session referencing the live run '
  'waited for the metronome''s beat to commit (c5f4ff34: 36 agent decision inserts begun inside a world step waited a '
  'mean 4.14 s against 0.29 s for the rest); they take FOR NO KEY UPDATE, which still serializes ticks and doors and '
  'still bars a delete. G440: ottoq_sim_stop_and_reset disposed the run''s proposals before mark_stopped locked the row, '
  'the reverse of the beat''s order, and deadlocked with the metronome (16:40:04, 16:42:42 UTC); it now takes the row '
  'first (FOR NO KEY UPDATE under mark_stopped''s 8 s, caller''s lock_timeout restored). Anchored and md5-guarded '
  '(3e0ddbb1, 0cd92ef2, a4339948, bc8ee182), nothing else moved (V1). Every certified output is computed inside one '
  'transaction, where a row lock''s mode changes no row read or written and the added lock reads nothing; no atom reads '
  'a lock: FALSE/FALSE.',
  now());

COMMIT;
