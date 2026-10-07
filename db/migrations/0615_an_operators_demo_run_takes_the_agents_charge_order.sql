-- migration-version: 20261007183516
-- migration-name:    an_operators_demo_run_takes_the_agents_charge_order
--
-- 0615  **An operator's demo run takes the agent's charge order.** 0614 built the order and left its dial at 0
--       everywhere. Chase, 2026-10-07: *"Yes let's definitely implement the advanced agent build ... always go with
--       highest and best and most robust depth of build for strengthening our intelligence and OTTO-Q layer."* One
--       run-scoped write at arming: `agent_charge_order` = 1 on a run an operator started (`run_by = 'operator_demo'`).
--       Separate from 0614 so it can be reverted on its own.
--
-- ══ §1 WHY ONLY THE OPERATOR'S RUN ════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_agentic_arm` arms every run that is not a certification arm, from both start doors (0323). Over the last 30
--   days those were 23 operator_demo runs, every one in real time, and 49 ab_harness runs, every one inside a single
--   transaction (started_at = ended_at). The agent is fired through pg_net, which sends after commit, so on an
--   ab_harness arm it finds the run already ended and records nothing: arming the dial there would change no decision,
--   but it would add a key to every sweep arm's dial set. So the write is gated on run_by = 'operator_demo', the runs the
--   agent serves, and a sweep's arm reads exactly the dials it read before. cert_harness never reaches it: the arm
--   refuses such a run by raising, above this block.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_agentic_arm`, after its ten keys: on an operator_demo run, `ottoq_policy_set('run', run, 'agent_charge_order',
--   1, by)`, the receipt read like the others (refused or clamped raises). The ttl (15 ticks) and the pin (90 sim
--   minutes) stay at their catalog defaults. Nothing else.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the arm is the body measured on 2026-10-07 (md5 of its source), 0614's dial is
--   catalogued with default 0, and the arm does not already write it. The anchor matches once. V1 (comment-stripped,
--   two passes as 0551): the write appears once, inside `IF v_run_by = 'operator_demo' THEN`, with its receipt read;
--   the ten keys of the loop are the ones before this file. Executed against the live arm body by
--   tests/test_agent_charge_order_sql.py: an operator's run is armed with the order, an ab_harness run is not, a
--   cert_harness run is still refused.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. No certification arm is ever armed, no ab_harness arm reaches the
--   new block, and no canon, sweep or dial pair runs as operator_demo.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0615_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0615_an_operators_demo_run_takes_the_agents_charge_order'.
--   A run already armed keeps its run-scoped dial until it ends; ottoq_policy_set('run', run, 'agent_charge_order', 0,
--   by) turns one off.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0615 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the arm is the body measured; 0614 is in; the arm does not already write the order ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agentic_arm(uuid,text)'::regprocedure)
     IS DISTINCT FROM '9c51a75220aca41ed17402f0151b4362' THEN
    RAISE EXCEPTION '0615 P1: ottoq_agentic_arm is not the body measured (md5 9c51a752); read it again';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'agent_charge_order' AND default_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0615 P1: 0614''s agent_charge_order dial is not catalogued with default 0';
  END IF;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_agentic_arm(uuid,text)'::regprocedure),
            'agent_charge_order') > 0
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                 WHERE name = '0615_an_operators_demo_run_takes_the_agents_charge_order') THEN
    RAISE EXCEPTION '0615 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0615_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agentic_arm(uuid,text)'::regprocedure;

-- ══ the arm ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $arm$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure);
  c_old := $old$  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,
$old$;
  c_new := $new$  --: 0615. THE AGENT'S CHARGE ORDER (0614), on an operator's run only: the runs the agent serves in real time.
  --: An ab_harness arm runs in one transaction, so the agent never reaches it, and its dial set stays the one before
  --: 0615. A cert_harness run never gets here: it is refused above.
  IF v_run_by = 'operator_demo' THEN
    v_r := public.ottoq_policy_set('run', p_sim_run_id, 'agent_charge_order', 1::numeric, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) OR COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: agent_charge_order was not armed as asked -> %', v_r
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END IF;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,
$new$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0615 arm: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $arm$;

-- ══ V1: the write is gated on the operator's run, once, with its receipt read; the loop's ten keys are unchanged ═════
DO $v1$
DECLARE v_new text; v_old text;
BEGIN
  v_new := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_old := regexp_replace(regexp_replace((SELECT s.definition FROM public.ottoq_schema_snapshots s
                                           WHERE s.label = '0615_pre' AND s.object_name = 'ottoq_agentic_arm'
                                           ORDER BY s.definition LIMIT 1),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (length(v_new) - length(replace(v_new, 'agent_charge_order', ''))) / length('agent_charge_order') <> 2 THEN
    RAISE EXCEPTION '0615 V1: agent_charge_order should appear twice in the arm (the write and its message)';
  END IF;
  IF v_new !~ 'IF v_run_by = ''operator_demo'' THEN\s+v_r := public\.ottoq_policy_set\(''run'', p_sim_run_id, ''agent_charge_order'', 1::numeric, p_by\);\s+IF NOT COALESCE\(\(v_r->>''ok''\)::boolean, false\) OR COALESCE\(\(v_r->>''clamped''\)::boolean, false\) THEN' THEN
    RAISE EXCEPTION '0615 V1: the write is not gated on the operator''s run with its receipt read';
  END IF;
  IF substring(v_new FROM 'SELECT \* FROM \(VALUES(.*?)\) AS t\(param_key, value\)')
     IS DISTINCT FROM substring(v_old FROM 'SELECT \* FROM \(VALUES(.*?)\) AS t\(param_key, value\)')
     OR substring(v_new FROM 'SELECT \* FROM \(VALUES(.*?)\) AS t\(param_key, value\)') IS NULL THEN
    RAISE EXCEPTION '0615 V1: the arm''s ten keys moved';
  END IF;
  IF strpos(v_new, 'IF v_run_by = ''cert_harness'' THEN') = 0
     OR strpos(v_new, 'IF v_run_by = ''cert_harness'' THEN') > strpos(v_new, 'IF v_run_by = ''operator_demo'' THEN') THEN
    RAISE EXCEPTION '0615 V1: the cert_harness refusal no longer comes first';
  END IF;
END $v1$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0615_an_operators_demo_run_takes_the_agents_charge_order', false, false,
  'ottoq_agentic_arm sets 0614''s agent_charge_order = 1 on a run with run_by = operator_demo, after its ten keys, the '
  'receipt read. FALSE/FALSE: no certification arm is ever armed (refused by raising), no ab_harness arm reaches the '
  'block (their dial set is the one before 0615), and no canon, sweep or dial pair runs as operator_demo.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
