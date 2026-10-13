-- migration-version: 20261013201139
-- migration-name:    the_board_calls_eighty_percent_a_priority_band_not_a_floor
--
-- 0717  **The agent's board calls a car's 80% a priority band, not a ready floor.** (G434; CLAUDE.md rule 9.)
--
-- ══ §1 WHY (measured 2026-10-13, read-only, between the commits of 19:39:26 UTC and this file) ══════════════════════
--
--   public.ottoq_agent_asset_depth builds the board's assets block and its attention list, and the cockpit's
--   intelligence stack reads the same function. For every car below its need profile's min_ready_soc_pct (80% on the
--   twin depot) the attention list says "soc 49% below ready floor 80%". The departure gate does not use 80%: it holds a
--   car to its target minus one (twin.ottoq_sim_advance_service_flow, GREATEST(floor, min_ready_soc_pct,
--   ottoq_effective_target_soc_at(car) - 1)), and the target is 100% unless the owner set less (0539). So the board
--   names as a floor a number that is neither the target nor the gate, and the agent repeated it as a target: of the
--   7,566 distinct directive texts on record, 114 told operators to charge to 80% ("charge to 80%+ for readiness",
--   "rapid top-up to 80% ready floor"). Agent v30 (deployed 20:06:39 UTC) states the target in its prompt and refuses
--   such a directive; this file removes the wording that taught it.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   One substitution in ottoq_agent_asset_depth (md5-guarded on 70f53e41698532607f5aa2aff0288265), the attention reason:
--     before  'soc 49% below ready floor 80%'
--     after   'soc 49%, in the priority band under 80% (charges to its owner''s target, not to 80%)'
--   The score, the ordering, the soc block (its field below_min_ready included) and everything else are unchanged; the
--   v30 prompt already says what below_min_ready is.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Its callers are ottoq_agent_board (the agent's board, built only for the agent) and ottoq_intelligence_stack (the
--   cockpit). No tick, decide path, check or atom reads either; certification arms never build the agent's board.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0717_pre';
--   DELETE FROM ottoq_cert_lineage WHERE name = '0717_the_board_calls_eighty_percent_a_priority_band_not_a_floor'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0717 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definition this file was written against ──
DO $premises$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)'::regprocedure))
    INTO v_md5;
  IF v_md5 IS DISTINCT FROM '70f53e41698532607f5aa2aff0288265' THEN
    RAISE EXCEPTION '0717 P1: ottoq_agent_asset_depth is not the definition this file was written against (md5 %)', v_md5;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0717_pre', 'function', 'public', 'ottoq_agent_asset_depth', pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p WHERE p.oid = 'public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)'::regprocedure;

-- ── the substitution, asserted to match exactly once ──
DO $sub$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)'::regprocedure);
  v_old constant text := $o$ARRAY['soc '||round(current_soc)||'% below ready floor '||round(COALESCE(min_ready_soc_pct,30))||'%']$o$;
  v_new constant text := $n$ARRAY['soc '||round(current_soc)||'%, in the priority band under '||round(COALESCE(min_ready_soc_pct,30))||'% (charges to its owner''s target, not to '||round(COALESCE(min_ready_soc_pct,30))||'%)']$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION '0717: the reason anchor does not match exactly once';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)'::regprocedure);
        v_old text := (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0717_pre' AND s.object_name = 'ottoq_agent_asset_depth' ORDER BY s.snapshot_id DESC LIMIT 1);
BEGIN
  --: V1 the wording is gone and the new wording is there; nothing else in the body moved
  IF v_def LIKE '%below ready floor%' OR v_def NOT LIKE '%in the priority band under%' THEN
    RAISE EXCEPTION '0717 V1 FAILED: the reason text is not as written';
  END IF;
  IF replace(v_def, $n$ARRAY['soc '||round(current_soc)||'%, in the priority band under '||round(COALESCE(min_ready_soc_pct,30))||'% (charges to its owner''s target, not to '||round(COALESCE(min_ready_soc_pct,30))||'%)']$n$, 'X')
     <> replace(v_old, $o$ARRAY['soc '||round(current_soc)||'% below ready floor '||round(COALESCE(min_ready_soc_pct,30))||'%']$o$, 'X') THEN
    RAISE EXCEPTION '0717 V1 FAILED: the body changed by more than the reason text';
  END IF;
  --: V2 still SECURITY DEFINER and STABLE (CREATE OR REPLACE keeps its grants)
  IF NOT (SELECT p.prosecdef AND p.provolatile = 's' FROM pg_proc p
           WHERE p.oid = 'public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)'::regprocedure) THEN
    RAISE EXCEPTION '0717 V2 FAILED: the function lost SECURITY DEFINER or STABLE';
  END IF;
  RAISE NOTICE '0717 V1-V2 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0717_the_board_calls_eighty_percent_a_priority_band_not_a_floor', false, false,
  'G434 (rule 9): ottoq_agent_asset_depth''s attention reason said "soc N% below ready floor 80%", a number that is '
  'neither the car''s target (100% unless its owner set less) nor the departure gate (target minus one), and the agent '
  'repeated it as a charge target in 114 distinct directives. It now says the car is in the priority band under 80% and '
  'charges to its owner''s target. One substitution, md5-guarded; read only by the agent''s board and the cockpit''s '
  'intelligence stack, never by a tick, check or atom: FALSE/FALSE.',
  now());

COMMIT;
