-- migration-version: 20261009101257
-- migration-name:    a_fault_owns_the_charge_it_cut
--
-- 0631  **A fault owns the charge it cut, and an attribution is superseded with the grade it stands on.**
--       The hindsight grader (0621) splits what happened after an order into five parts and replays the order with
--       every subset of them in place of the forecast, to say which part made the check wrong. A charge under way at
--       the order that a charger fault ended was split across two parts: the running clock got its early end, the
--       faults got the charger's down time. Replayed with one and not the other, the world is one that did not happen.
--       0631 gives the whole fault to the faults part, and keeps a new attribution beside the first when its grade is
--       superseded, as 0630 keeps a new grade.
--
-- ══ §1 WHY (measured 2026-10-09 05:00-06:00 UTC, midnight-1 AM CT, over the 247 stored grades) ══════════════════════════
--
--   (a) What the record says. ottoq_charge_order_realized reads a charge under way at the order that a fault ended
--       inside the window as a charge that ended at the fault: free at the fault and not censored; the charger's down
--       window, from the fault to the repair, goes to the faults part. 158 such charger records in 93 of the 247 grades,
--       in 21 of the 32 decisions, 12 of the 21 attributions and 8 of the 13 whose verdict hindsight changed. Each
--       fault's event time equals its session's end (16 of 16 faulted sessions on the three graded runs).
--   (b) The forecast errors. The running block scores every uncensored charger, so it scored these as the clock's
--       misses: 62 cut by communication dropouts read the clock 111.09 minutes late on average, 37 aborted sessions
--       64.27, 18 station hardware faults 46.37, 36 connector cables 14.92, 5 ground faults 6.59. The 4,224 charges that
--       completed read it 0.86 minutes early on average, 7.33 minutes off. After 0630 the block reads -1.61 / 9.50, and
--       that is the faults': the remaining-time clock is not what is off.
--   (c) The replay. With the running part and not the faults part, the charger is free at the fault: capacity that
--       never existed. With the faults part and not the running part, the simulator (ottoq_charge_line_schedule, 0621)
--       can only extend a busy charger's time to the repair, since the charge under way at the order is no car it knows
--       to cut, so the charger is busy to the forecast's end instead of free at the repair. Neither world happened, and
--       the Shapley split averages over both. Measured on the 12 attributions, recomputed with the fault owning its cut
--       (a pg_temp copy, read-only): the parts' shares of what made the check wrong barely move (running 27.0% to
--       26.5%, faults 13.7% to 11.8%, arrivals 24.4% to 24.8%, appeared 18.9% to 19.8%, charge times 16.0% to 17.1%),
--       and v(none) and v(all) are unchanged on 12 of 12. So the review's ranking stands; what changes is that each
--       half-replay is now a world that could have happened, and the running block measures the clock.
--   (d) Why the attributions too. An attribution is computed from its grade's record. 0630 refused to regrade an
--       attributed order ("supersede both or neither"); 0631 does both.
--   (e) 24 of the 93, and 9 of the 12 attributions, are grades 0621's own grader gave (code 9f1ff00e, the 61 graded the
--       minutes after it was applied). The grader as it is now reads their record differently outside the chargers
--       (0622's clock, 0623's cut: cars, inbound, appeared) and grades them identically: recomputed now, 61 of 61 match
--       their stored grade in every graded field (expected, hindsight, outcome, moves, forecasts, fidelity), read-only.
--       Their regrades carry that record too, so V3 and V4 hold them to the graded fields and the cut chargers, and the
--       other 69 to their whole record.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq_charge_order_realized: a charge under way at the order that a fault ended inside the window reads, in the
--       running part, as censored at the fault (free no sooner than the fault and no sooner than the check's forecast,
--       cen true), and carries cut, the fault's minute.
--   (b) ottoq_charge_line_realize: the faults part ends a charge under way at its cut, before its down window. With both
--       parts the replay is the one before 0631 (free at the fault, down to the repair), so every grade's expected
--       future, hindsight, outcome, moves and fidelity stand as they were; only its record's chargers and its forecasts'
--       running block change. A record without cut (every stored one) replays as before.
--   (c) public.ottoq_charge_order_reattributions, append-only evidence: an attribution of an order already attributed,
--       computed from its standing grade, in the ledger's columns (computed_at the first's), with reattributed_at, the
--       code it supersedes, the defect and what changed. public.ottoq_charge_order_attributions, a view: the standing
--       attribution, the newest reattribution else the first. public.ottoq_charge_order_attribute_compute(order): the
--       attribution computed and returned, written nowhere; ottoq_charge_order_attribute keeps it the first time and
--       returns the standing one. Its three readers (the pending grader, the track record, the review's first part)
--       read the view. ottoq_hindsight_code_md5 covers the computation.
--   (d) ottoq_charge_order_regrade: an attributed order is regraded and its attribution computed again from the new
--       grade and kept beside the first, under the same defect, instead of refused.
--   (e) The 93 orders of §1(a) are regraded under 'fault_cut_read_as_running_end', the 12 attributions with them.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight and no run running. P1 the nine bodies are 0630's (md5), the four objects are new, the
--   attribution ledger's columns are the ones measured, the functions naming it are exactly its writer and three
--   readers, 0630 is applied, and 61 grades carry 0621's grader's code. V1 the realizer and the replay by meaning; each
--   reader is its 0630 body with the ledger's name swapped and nothing else. V2 the computation reproduces six
--   attributions this does not touch. V3 each regrade: its record's chargers are its standing grade's with exactly the
--   cut chargers censored and cut, its forecasts differ only in the running block, and everything else (expected,
--   hindsight, outcome, moves, fidelity) is as it was; outside its chargers and the run's status its record is as it
--   was, but on 0621's grades (§1(e)). V4 each reattribution: v(none) and v(all) as the first's, the five values
--   summing to v(all) - v(none), the verdict change as it was, and, but on 0621's grades, every subset holding both or
--   neither of running and faults as the first's. V5 the running block
--   and the parts' shares before and after. V6 the readers run. Executed by tests/test_agent_fault_cut_sql.py on the
--   miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: as 0630, evidence only. ottoq_charge_line_realize is read only by
--   the grader and the attribution; the simulator, the rollout and the door do not call it.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0631_pre' AND object_kind = 'function';
--   then DROP FUNCTION public.ottoq_charge_order_attribute_compute(bigint); DROP VIEW public.ottoq_charge_order_attributions;
--   and, only if its rows are kept elsewhere first, DROP TABLE public.ottoq_charge_order_reattributions and its registry
--   row; DELETE FROM public.ottoq_cert_lineage WHERE name = '0631_a_fault_owns_the_charge_it_cut'. The regrades it
--   wrote stay (evidence); a regrade after the rollback supersedes them.

BEGIN;

-- ── P0: nothing in flight, and no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0631 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0631 P0: a run is running; its charge-order door grades its orders as their windows close. Apply '
                    'between runs';
  END IF;
END $inflight$;

-- ── P1: 0630's bodies; the objects are new; the attribution ledger and its readers are the ones measured ──
DO $premises$
DECLARE r record; v_cols text; v_names text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0630_the_grader_reads_a_runs_stop_as_the_stop') THEN
    RAISE EXCEPTION '0631 P1: 0630 is not applied';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_order_realized(bigint,numeric)',                              '0e094b74c336c79a9a79b55462d6b95c'),
    ('public.ottoq_charge_line_realize(jsonb,jsonb,text[])',                            '4817598bf9c8d45f59f12f8856dcb325'),
    ('public.ottoq_charge_order_attribute(bigint)',                                     'f201944dab17f4617e62415e3e37fa7d'),
    ('public.ottoq_charge_order_regrade(bigint,text,text)',                             'ad1000c16c9fa08c24e5df06232d7c79'),
    ('public.ottoq_hindsight_code_md5()',                                               '7bdea5fe534e534c5c720db5c9205b48'),
    ('public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)',  'f0c17c9d588dcb36b03ab5100f45c204'),
    ('public.ottoq_charge_order_track_record(uuid,uuid,integer)',                       'cd808d47d6a7e35b809e13d4de6146ce'),
    ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)',             '0378d5cdcd43661631130847c2f5eb56'),
    ('public.ottoq_charge_order_grade_compute(bigint,numeric)',                         'aac0190c09b0fce7546ca987acb8e8a6'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0631 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_charge_order_attribute_compute(bigint)') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_attributions') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_reattributions') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0631_a_fault_owns_the_charge_it_cut') THEN
    RAISE EXCEPTION '0631 P1: already applied';
  END IF;
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_charge_order_attribution'::regclass AND a.attnum > 0
     AND NOT a.attisdropped;
  IF v_cols IS DISTINCT FROM 'order_id,sim_run_id,depot_id,parts,subset_values,shapley,verdict_changed,code_md5,'
                             'computed_at' THEN
    RAISE EXCEPTION '0631 P1: the attribution ledger''s columns are not the ones measured: %', v_cols;
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_names
    FROM pg_proc p
   WHERE p.prosrc ~ 'ottoq_charge_order_attribution(?![a-z_0-9])'
     AND p.oid NOT IN ('public.ottoq_charge_order_attribute(bigint)'::regprocedure,
                       'public.ottoq_charge_order_regrade(bigint,text,text)'::regprocedure,
                       'public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)'::regprocedure,
                       'public.ottoq_charge_order_track_record(uuid,uuid,integer)'::regprocedure,
                       'public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)'::regprocedure);
  IF v_names IS NOT NULL THEN
    RAISE EXCEPTION '0631 P1: these name the attribution ledger and 0631 was not written against them: %', v_names;
  END IF;
  -- §1(e): the grades 0621's own grader gave, which V3 and V4 hold to their graded fields
  IF (SELECT count(*) FROM public.ottoq_charge_order_hindsight WHERE code_md5 = '9f1ff00e6c58b29403a8453578cc23a2')
     IS DISTINCT FROM (SELECT count(*) FROM public.ottoq_charge_order_hindsight WHERE graded_at < '2026-10-08 16:24:12+00') THEN
    RAISE EXCEPTION '0631 P1: the grades by 0621''s grader are not the ones graded before 0622 was applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0631_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure,
                 'public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure,
                 'public.ottoq_charge_order_attribute(bigint)'::regprocedure,
                 'public.ottoq_charge_order_regrade(bigint,text,text)'::regprocedure,
                 'public.ottoq_hindsight_code_md5()'::regprocedure,
                 'public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)'::regprocedure,
                 'public.ottoq_charge_order_track_record(uuid,uuid,integer)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)'::regprocedure);

-- ── the orders this regrades, read before anything changes: each standing grade with a charger the check modelled busy
--    whose charge under way a fault ended by the realizer's own cut, and those chargers ──
CREATE TEMP TABLE _0631_affected ON COMMIT DROP AS
WITH g AS (
  SELECT h.order_id, h.sim_run_id, h.code_md5, h.realized, h.forecast, s.sim_clock AS t0, s.state,
         GREATEST(LEAST(s.sim_clock + make_interval(secs => GREATEST(COALESCE(h.window_min, 90), 1) * 60),
                        COALESCE(r.sim_clock_current, s.sim_clock)), s.sim_clock) AS cut
    FROM public.ottoq_charge_order_grades h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = h.sim_run_id AND r.purged_at IS NULL),
hit AS (
  SELECT g.order_id, c.id AS charger, c.free AS forecast_free
    FROM g
    CROSS JOIN LATERAL (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'free')::numeric, 0) AS free
                          FROM jsonb_array_elements(COALESCE(g.state -> 'chargers', '[]'::jsonb)) x
                         WHERE (x.value ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
    JOIN LATERAL (SELECT os.ended_at, os.stopped_reason, os.status::text AS st FROM public.ocpp_sessions os
                   WHERE c.free > 0 AND os.sim_run_id = g.sim_run_id AND os.stall_id = c.id::uuid
                     AND os.started_at < g.t0 AND (os.ended_at IS NULL OR os.ended_at > g.t0)
                   ORDER BY os.started_at DESC LIMIT 1) rs ON true
   WHERE rs.ended_at <= g.cut AND (rs.st = 'faulted' OR COALESCE(rs.stopped_reason, '') LIKE 'fault.%'))
SELECT g.order_id, g.code_md5, g.realized, g.forecast,
       jsonb_agg(hit.charger ORDER BY hit.charger) AS chargers,
       -- the record the patched realizer must return: the standing one, with each charger a fault cut censored there
       -- and cut, its down window kept
       jsonb_set(g.realized, '{chargers}',
                 (SELECT jsonb_object_agg(k.key, CASE WHEN h2.charger IS NULL THEN k.value
                                                      ELSE k.value || jsonb_build_object(
                                                             'free', GREATEST((k.value ->> 'free')::numeric, h2.forecast_free),
                                                             'cen', true,
                                                             'cut', (k.value ->> 'free')::numeric) END)
                    FROM jsonb_each(g.realized -> 'chargers') k
                    LEFT JOIN hit h2 ON h2.order_id = g.order_id AND h2.charger = k.key)) AS want
  FROM g JOIN hit ON hit.order_id = g.order_id
 GROUP BY g.order_id, g.code_md5, g.realized, g.forecast;

DO $affected$
BEGIN
  IF EXISTS (SELECT 1 FROM _0631_affected a, jsonb_array_elements_text(a.chargers) c
              WHERE jsonb_typeof(a.realized #> ARRAY['chargers', c]) IS DISTINCT FROM 'object'
                 OR COALESCE((a.realized #>> ARRAY['chargers', c, 'cen'])::boolean, true)) THEN
    RAISE EXCEPTION '0631: a charger a fault cut is not in its standing record as an uncensored end';
  END IF;
  RAISE NOTICE '0631: % standing grades read a charge a fault cut as the running clock''s end (% charger records; % '
               'decisions; % attributed; % by 0621''s grader), of % graded',
    (SELECT count(*) FROM _0631_affected), (SELECT COALESCE(sum(jsonb_array_length(chargers)), 0) FROM _0631_affected),
    (SELECT count(*) FROM _0631_affected a JOIN public.ottoq_charge_order_grades g USING (order_id) WHERE g.decision),
    (SELECT count(*) FROM _0631_affected a JOIN public.ottoq_charge_order_attribution x USING (order_id)),
    (SELECT count(*) FROM _0631_affected a WHERE a.code_md5 = '9f1ff00e6c58b29403a8453578cc23a2'),
    (SELECT count(*) FROM public.ottoq_charge_order_grades);
END $affected$;

-- V4's and V5's before: the standing attributions, and the running block and the parts' shares over the twin depot
CREATE TEMP TABLE _0631_attr_before ON COMMIT DROP AS
SELECT a.* FROM public.ottoq_charge_order_attribution a;

CREATE TEMP TABLE _0631_before ON COMMIT DROP AS
SELECT (SELECT sum((g.forecast #>> '{running,n}')::numeric) FROM public.ottoq_charge_order_grades g
         WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days') AS n,
       (SELECT sum((g.forecast #>> '{running,sum_err}')::numeric) FROM public.ottoq_charge_order_grades g
         WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days') AS sum_err,
       (SELECT sum((g.forecast #>> '{running,sum_abs_err}')::numeric) FROM public.ottoq_charge_order_grades g
         WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days') AS sum_abs_err,
       (SELECT jsonb_object_agg(z.part, z.share) FROM (
          SELECT p.key AS part, round(sum(abs((p.value ->> 'cmp')::numeric)) / NULLIF(sum(sum(abs((p.value ->> 'cmp')::numeric))) OVER (), 0), 3) AS share
            FROM public.ottoq_charge_order_attribution a JOIN public.ottoq_charge_order_grades g ON g.order_id = a.order_id
            CROSS JOIN LATERAL jsonb_each(a.shapley) p
           WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days'
           GROUP BY p.key) z) AS shares;

-- ══ (c) the reattributions and the standing attribution ═══════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_order_reattributions (
  --: the attribution ledger's columns, in its order (0621). computed_at is the FIRST attribution's; reattributed_at is
  --: when this one was computed (the statement clock). NO foreign key (evidence, 0340/0364).
  LIKE public.ottoq_charge_order_attribution INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
  reattributed_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  --: the code of the attribution this one supersedes
  supersedes_code_md5  text NOT NULL,
  --: why: the defect of the regrade it stands on
  defect               text NOT NULL,
  --: what changed: the verdict change before and after, the parts' values before, a note
  detail               jsonb NOT NULL,
  PRIMARY KEY (order_id, code_md5),
  CONSTRAINT ottoq_charge_order_reattributions_defect_ck CHECK (defect ~ '^[a-z][a-z0-9_]{2,62}$'),
  CONSTRAINT ottoq_charge_order_reattributions_new_code_ck CHECK (supersedes_code_md5 <> code_md5)
);

COMMENT ON TABLE public.ottoq_charge_order_reattributions IS
'0631. An attribution of an agent charge order already attributed (ottoq_charge_order_attribution), computed again from its standing grade when that grade is superseded (ottoq_charge_order_regrade): the ledger''s columns (computed_at the first''s), when it was computed, the code it supersedes, the defect and what changed. ottoq_charge_order_attributions reads the newest. Class=evidence with NO foreign key (0340/0364). Append-only (override: ottoq.hindsight_unlock=on).';

CREATE TRIGGER ottoq_charge_order_reattributions_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_order_reattributions
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();

ALTER TABLE public.ottoq_charge_order_reattributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_order_reattributions_read ON public.ottoq_charge_order_reattributions FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_order_reattributions FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_reattributions TO anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_charge_order_reattributions', 'sim_run_id', 'evidence',
        '0631: a later attribution of an attributed agent charge order, computed from the grade that superseded the '
        'first. Evidence, not engine. NO foreign key to ottoq_sim_runs, as 0340, 0364, 0621 and 0630.');

CREATE VIEW public.ottoq_charge_order_attributions WITH (security_invoker = true) AS
SELECT a.order_id, a.sim_run_id, a.depot_id, a.parts, a.subset_values, a.shapley, a.verdict_changed, a.code_md5,
       a.computed_at
  FROM public.ottoq_charge_order_attribution a
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_reattributions r WHERE r.order_id = a.order_id)
UNION ALL
SELECT r.order_id, r.sim_run_id, r.depot_id, r.parts, r.subset_values, r.shapley, r.verdict_changed, r.code_md5,
       r.computed_at
  FROM public.ottoq_charge_order_reattributions r
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_reattributions n
                    WHERE n.order_id = r.order_id
                      AND (n.reattributed_at, n.code_md5) > (r.reattributed_at, r.code_md5));

COMMENT ON VIEW public.ottoq_charge_order_attributions IS
'0631. The standing attribution of every attributed agent charge order, in the ledger''s columns: its newest reattribution (ottoq_charge_order_reattributions) if it has one, else its first (ottoq_charge_order_attribution). Every reader of attributions reads this; only the attribution writes the ledger.';

REVOKE ALL ON public.ottoq_charge_order_attributions FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_attributions TO anon, authenticated;

CREATE FUNCTION public.ottoq_charge_order_attribute_compute(p_order_id bigint)
 RETURNS public.ottoq_charge_order_attributions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0631: one graded order's attribution as it is computed now, from its standing grade (ottoq_charge_order_grades),
   written nowhere: what ottoq_charge_order_attribute keeps the first time, and what ottoq_charge_order_regrade keeps
   beside a first attribution when it supersedes the grade it stood on. 0621's attribution, moved here unchanged: v(S) is
   the comparison of the agent's order with the kernel's, replayed with only the parts of what happened in S in place of
   the forecast; a part's Shapley value is weight |S|! (4 - |S|)! / 5! on v(S + part) - v(S); the five sum, on each of
   cmp, on_time, lateness and flow, to v(all) - v(none). NULL without a grade or a snapshot. computed_at is now(). */
DECLARE
  r_out public.ottoq_charge_order_attributions;
  h record; s record; c_parts constant text[] := ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults'];
  v_cmp int[] := '{}'; v_dot numeric[] := '{}'; v_dl numeric[] := '{}'; v_df numeric[] := '{}';
  mask int; b int; sz int; w numeric; st jsonb; k jsonb; a jsonb; c jsonb; v_vals jsonb := '[]'::jsonb;
  p_cmp numeric; p_dot numeric; p_dl numeric; p_df numeric; v_sh jsonb := '{}'::jsonb; up int;
BEGIN
  SELECT * INTO h FROM ottoq_charge_order_grades x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  FOR mask IN 0 .. 31 LOOP
    st := public.ottoq_charge_line_realize(s.state, h.realized,
            ARRAY(SELECT c_parts[g + 1] FROM generate_series(0, 4) g WHERE (mask >> g) & 1 = 1));
    k := public.ottoq_charge_line_simulate(st, NULL, 0, s.seed);
    a := public.ottoq_charge_line_simulate(st, s.agent_order, 0, s.seed);
    c := public.ottoq_charge_line_compare(k, a);
    v_cmp[mask + 1] := (c ->> 'cmp')::int;
    v_dot[mask + 1] := (c ->> 'd_on_time')::numeric;
    v_dl[mask + 1] := (c ->> 'd_late')::numeric;
    v_df[mask + 1] := (c ->> 'd_flow')::numeric;
    v_vals := v_vals || jsonb_build_array(jsonb_build_array(v_cmp[mask + 1], v_dot[mask + 1], v_dl[mask + 1], v_df[mask + 1]));
  END LOOP;
  FOR b IN 0 .. 4 LOOP
    p_cmp := 0; p_dot := 0; p_dl := 0; p_df := 0;
    FOR mask IN 0 .. 31 LOOP
      CONTINUE WHEN (mask >> b) & 1 = 1;
      sz := (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1) + ((mask >> 3) & 1) + ((mask >> 4) & 1);
      w := (CASE sz WHEN 0 THEN 24 WHEN 1 THEN 6 WHEN 2 THEN 4 WHEN 3 THEN 6 ELSE 24 END)::numeric / 120;
      up := (mask | (1 << b)) + 1;
      p_cmp := p_cmp + w * (v_cmp[up] - v_cmp[mask + 1]);
      p_dot := p_dot + w * (v_dot[up] - v_dot[mask + 1]);
      p_dl := p_dl + w * (v_dl[up] - v_dl[mask + 1]);
      p_df := p_df + w * (v_df[up] - v_df[mask + 1]);
    END LOOP;
    v_sh := v_sh || jsonb_build_object(c_parts[b + 1], jsonb_build_object(
              'cmp', round(p_cmp, 4), 'on_time', round(p_dot, 4), 'late', round(p_dl, 4), 'flow', round(p_df, 4)));
  END LOOP;
  r_out.order_id := p_order_id;
  r_out.sim_run_id := s.sim_run_id;
  r_out.depot_id := s.depot_id;
  r_out.parts := c_parts;
  r_out.subset_values := v_vals;
  r_out.shapley := v_sh;
  r_out.verdict_changed := sign(v_cmp[32]) IS DISTINCT FROM sign(v_cmp[1]);
  r_out.code_md5 := public.ottoq_hindsight_code_md5();
  r_out.computed_at := now();
  RETURN r_out;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_order_attribute_compute(bigint) IS
'0631. One graded order''s attribution computed now from its standing grade, written nowhere: what ottoq_charge_order_attribute keeps the first time and ottoq_charge_order_regrade keeps beside a first attribution whose grade it supersedes. 0621''s attribution, moved here unchanged.';

REVOKE ALL ON FUNCTION public.ottoq_charge_order_attribute_compute(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_attribute_compute(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.ottoq_charge_order_attribute(p_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: why hindsight differs from the check, for one graded order. v(S) is the comparison of the agent's order with
   the kernel's, replayed with only the parts of what happened in S put in place of the forecast (all 32 subsets of the
   five, each replayed both ways, from the realized record the grade kept). A part's Shapley value is its contribution
   averaged over every order in which the parts could be put in: weight |S|! (4 - |S|)! / 5! on v(S + part) - v(S). The
   five sum, on each of cmp, on_time, lateness and flow, to v(all) - v(none) = hindsight - the expected future.
   0631: computed by ottoq_charge_order_attribute_compute, which a regrade shares; kept here the first time; and what
   this returns is the order's standing attribution (ottoq_charge_order_attributions). */
DECLARE
  v_row jsonb; r public.ottoq_charge_order_attributions;
BEGIN
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_attributions x WHERE x.order_id = p_order_id;
  IF v_row IS NOT NULL THEN RETURN v_row; END IF;
  r := public.ottoq_charge_order_attribute_compute(p_order_id);
  IF r.order_id IS NULL THEN RETURN NULL; END IF;
  INSERT INTO ottoq_charge_order_attribution
    (order_id, sim_run_id, depot_id, parts, subset_values, shapley, verdict_changed, code_md5)
  VALUES (r.order_id, r.sim_run_id, r.depot_id, r.parts, r.subset_values, r.shapley, r.verdict_changed, r.code_md5)
  ON CONFLICT (order_id) DO NOTHING;
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_attributions x WHERE x.order_id = p_order_id;
  RETURN v_row;
END $fn$;

-- ══ the anchored patches: (a) the realizer, (b) the replay, (d) the regrade, and the code md5's list ══════════════════════
CREATE TEMP TABLE _0631_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0631_patch VALUES
('public.ottoq_charge_order_realized(bigint,numeric)', 1,
$old$free no sooner than the cut. 0621-0629 read such a charger as free at the cut, uncensored. */$old$,
$new$free no sooner than the cut. 0621-0629 read such a charger as free at the cut, uncensored.
   0631: a charge under way that a fault ended inside the window is the fault's: the running clock reads it censored at
   the fault (free no sooner than the fault, nor than the check's forecast), and cut is the fault's minute, where the
   faults part ends it (ottoq_charge_line_realize) before its down window. 0621-0630 read it as the clock's end. */$new$),
('public.ottoq_charge_order_realized(bigint,numeric)', 2,
$old$           'free', CASE WHEN rs.stall_id IS NULL THEN NULL
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                        THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2)
                        ELSE GREATEST(v_obs, c.free) END,
           'cen', CASE WHEN rs.stall_id IS NOT NULL THEN NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut) END,
           'dn', dn.w)))$old$,
$new$           'free', CASE WHEN rs.stall_id IS NULL THEN NULL
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut AND NOT rs.fault
                        THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2)
                        -- 0631: a fault ended it: the clock's charge ran at least until the fault
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                        THEN GREATEST(round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2), c.free)
                        ELSE GREATEST(v_obs, c.free) END,
           'cen', CASE WHEN rs.stall_id IS NOT NULL
                       THEN NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut AND NOT rs.fault) END,
           -- 0631: and the faults part ends it at the fault
           'cut', CASE WHEN rs.fault AND rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                       THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2) END,
           'dn', dn.w)))$new$),
('public.ottoq_charge_order_realized(bigint,numeric)', 3,
$old$                              CASE WHEN os.stopped_reason = 'sim_reset' THEN NULL ELSE os.ended_at END AS ended_at
                         FROM ocpp_sessions os$old$,
$new$                              CASE WHEN os.stopped_reason = 'sim_reset' THEN NULL ELSE os.ended_at END AS ended_at,
                              -- 0631: a fault ended it
                              (os.status::text = 'faulted' OR COALESCE(os.stopped_reason, '') LIKE 'fault.%') AS fault
                         FROM ocpp_sessions os$new$),
('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', 1,
$old$   and the cars nobody modelled that joined the line. */$old$,
$new$   and the cars nobody modelled that joined the line.
   0631: faults also ends a charge under way that a fault cut, at its cut, before its down window: the fault's whole
   effect is the faults part's, and the running part reads such a charge censored at the fault. A record without cut
   (every one before 0631) replays as before. */$new$),
('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', 2,
$old$    IF v_f AND jsonb_typeof(r -> 'dn') = 'array' THEN e := e || jsonb_build_object('dn', r -> 'dn'); END IF;
$old$,
$new$    IF v_f AND jsonb_typeof(r -> 'dn') = 'array' THEN e := e || jsonb_build_object('dn', r -> 'dn'); END IF;
    IF v_f AND jsonb_typeof(r -> 'cut') = 'number' THEN e := e || jsonb_build_object('free', r -> 'cut'); END IF;  -- 0631
$new$),
('public.ottoq_hindsight_code_md5()', 1,
$old$  -- 0630: and the grade's computation, which the first grade and a regrade share.$old$,
$new$  -- 0630: and the grade's computation, which the first grade and a regrade share.
  -- 0631: and the attribution's.$new$),
('public.ottoq_hindsight_code_md5()', 2,
$old$                      'public.ottoq_charge_order_attribute(bigint)',$old$,
$new$                      'public.ottoq_charge_order_attribute(bigint)',
                      'public.ottoq_charge_order_attribute_compute(bigint)',$new$),
('public.ottoq_charge_order_regrade(bigint,text,text)', 1,
$old$   named as a short code; no grade to supersede; the order's run purged, so what happened can no longer be read; an
   attribution computed from the grade it would supersede; the grader unchanged since the standing grade, so a regrade
   would repeat it. */$old$,
$new$   named as a short code; no grade to supersede; the order's run purged, so what happened can no longer be read; the
   grader unchanged since the standing grade, so a regrade would repeat it.
   0631: an attributed order's attribution stands on the grade this supersedes, so it is computed again from the new
   grade and kept beside the first (ottoq_charge_order_reattributions), under the same defect: both, never one. */$new$),
('public.ottoq_charge_order_regrade(bigint,text,text)', 2,
$old$  f public.ottoq_charge_order_grades; g public.ottoq_charge_order_grades; v_old jsonb; v_new jsonb; v_detail jsonb;$old$,
$new$  f public.ottoq_charge_order_grades; g public.ottoq_charge_order_grades; v_old jsonb; v_new jsonb; v_detail jsonb;
  fa public.ottoq_charge_order_attributions; ga public.ottoq_charge_order_attributions; v_attr boolean;  -- 0631$new$),
('public.ottoq_charge_order_regrade(bigint,text,text)', 3,
$old$  IF EXISTS (SELECT 1 FROM ottoq_charge_order_attribution a WHERE a.order_id = p_order_id) THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: order % has an attribution computed from the grade this would '
                    'supersede; supersede both or neither', p_order_id USING ERRCODE = '22023';
  END IF;$old$,
$new$  -- 0631: an attribution stands on the grade this supersedes: it is superseded with it, below
  SELECT * INTO fa FROM ottoq_charge_order_attributions x WHERE x.order_id = p_order_id;
  v_attr := FOUND;$new$),
('public.ottoq_charge_order_regrade(bigint,text,text)', 4,
$old$  ON CONFLICT (order_id, code_md5) DO NOTHING;
  RETURN jsonb_build_object('order_id', p_order_id, 'defect', p_defect, 'supersedes', f.code_md5, 'code_md5', g.code_md5)
         || v_detail;$old$,
$new$  ON CONFLICT (order_id, code_md5) DO NOTHING;
  -- 0631: and its attribution, computed again from the grade just kept (now the standing one)
  IF v_attr THEN
    ga := public.ottoq_charge_order_attribute_compute(p_order_id);
    IF ga.order_id IS NULL OR ga.code_md5 IS NOT DISTINCT FROM fa.code_md5 THEN
      RAISE EXCEPTION 'ottoq_charge_order_regrade: order %''s attribution could not be computed again under a new code',
        p_order_id USING ERRCODE = '22023';
    END IF;
    INSERT INTO ottoq_charge_order_reattributions
      (order_id, sim_run_id, depot_id, parts, subset_values, shapley, verdict_changed, code_md5, computed_at,
       supersedes_code_md5, defect, detail)
    VALUES (ga.order_id, ga.sim_run_id, ga.depot_id, ga.parts, ga.subset_values, ga.shapley, ga.verdict_changed,
            ga.code_md5, fa.computed_at, fa.code_md5, p_defect,
            jsonb_strip_nulls(jsonb_build_object(
              'verdict_changed', jsonb_build_object('was', fa.verdict_changed, 'now', ga.verdict_changed),
              'shapley_was', fa.shapley, 'note', p_note)))
    ON CONFLICT (order_id, code_md5) DO NOTHING;
    v_detail := v_detail || jsonb_build_object('reattributed', true);
  END IF;
  RETURN jsonb_build_object('order_id', p_order_id, 'defect', p_defect, 'supersedes', f.code_md5, 'code_md5', g.code_md5)
         || v_detail;$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0631_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0631_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0631 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0631 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ (c) the readers read the standing attribution: each its 0630 body with the ledger's name swapped, nothing else ══════
CREATE TEMP TABLE _0631_readers (fn text, refs int) ON COMMIT DROP;
INSERT INTO _0631_readers VALUES
  ('public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)',  1),
  ('public.ottoq_charge_order_track_record(uuid,uuid,integer)',                       3),
  ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)',             3);

DO $readers$
DECLARE r record; v_pre text; v_def text; n int;
BEGIN
  FOR r IN SELECT * FROM _0631_readers ORDER BY fn LOOP
    v_pre := pg_get_functiondef(to_regprocedure(r.fn));
    n := (SELECT count(*) FROM regexp_matches(v_pre, 'ottoq_charge_order_attribution(?![a-z_0-9])', 'g'));
    IF n IS DISTINCT FROM r.refs OR v_pre ~ 'ottoq_charge_order_attributions(?![a-z_0-9])' THEN
      RAISE EXCEPTION '0631 (c): % names the ledger % times (measured %), or already names the view', r.fn, n, r.refs;
    END IF;
    v_def := regexp_replace(v_pre, 'ottoq_charge_order_attribution(?![a-z_0-9])', 'ottoq_charge_order_attributions', 'g');
    IF regexp_replace(v_def, 'ottoq_charge_order_attributions(?![a-z_0-9])', 'ottoq_charge_order_attribution', 'g')
       IS DISTINCT FROM v_pre THEN
      RAISE EXCEPTION '0631 V1: % swapped back is not its measured body', r.fn;
    END IF;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(r.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0631 V1: % is not stored as swapped', r.fn;
    END IF;
  END LOOP;
END $readers$;

-- ══ V1, by meaning ════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_real text; v_rz text; v_md5 text; v_names text; v_attr text;
BEGIN
  v_real := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure),
                                          '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_real, '''cut'', CASE WHEN rs.fault AND rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut') = 0
     OR strpos(v_real, 'NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut AND NOT rs.fault)') = 0
     OR strpos(v_real, 'AS fault') = 0 THEN
    RAISE EXCEPTION '0631 V1: the realizer does not read a fault''s cut as the fault''s';
  END IF;
  v_rz := pg_get_functiondef('public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure);
  IF strpos(v_rz, 'IF v_f AND jsonb_typeof(r -> ''cut'') = ''number'' THEN e := e || jsonb_build_object(''free'', r -> ''cut'')')
       < strpos(v_rz, 'IF v_r AND jsonb_typeof(r -> ''free'') = ''number''')
     OR strpos(v_rz, 'IF v_f AND jsonb_typeof(r -> ''cut'') = ''number''') = 0 THEN
    RAISE EXCEPTION '0631 V1: the replay does not end a cut charge after the running part sets its end';
  END IF;
  v_md5 := pg_get_functiondef('public.ottoq_hindsight_code_md5()'::regprocedure);
  IF strpos(v_md5, '''public.ottoq_charge_order_attribute_compute(bigint)''') = 0 THEN
    RAISE EXCEPTION '0631 V1: the code md5 does not cover the attribution''s computation';
  END IF;
  -- only the attribution names its ledger, to write it
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_names
    FROM pg_proc p
   WHERE p.oid <> 'public.ottoq_charge_order_attribute(bigint)'::regprocedure
     AND p.prosrc LIKE '%ottoq_charge_order_attribution%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
         ~ 'ottoq_charge_order_attribution(?![a-z_0-9])';
  v_attr := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_charge_order_attribute(bigint)'::regprocedure),
                                          '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_names IS NOT NULL
     OR (SELECT count(*) FROM regexp_matches(v_attr, 'ottoq_charge_order_attribution(?![a-z_0-9])', 'g')) <> 1
     OR strpos(v_attr, 'INSERT INTO ottoq_charge_order_attribution') = 0 THEN
    RAISE EXCEPTION '0631 V1: the attribution ledger is named outside its one write: %', COALESCE(v_names, 'the writer');
  END IF;
END $v1$;

-- ══ V2: the computation reproduces attributions this does not touch ═════════════════════════════════════════════════════
DO $v2$
DECLARE r record; g jsonb; h jsonb; n int := 0; v_t timestamptz := clock_timestamp();
BEGIN
  FOR r IN
    SELECT a.order_id FROM _0631_attr_before a
     WHERE NOT EXISTS (SELECT 1 FROM _0631_affected x WHERE x.order_id = a.order_id)
       AND EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades gg JOIN public.ottoq_sim_runs s
                     ON s.sim_run_id = gg.sim_run_id AND s.purged_at IS NULL WHERE gg.order_id = a.order_id)
     ORDER BY md5(a.order_id::text) LIMIT 6
  LOOP
    g := to_jsonb(public.ottoq_charge_order_attribute_compute(r.order_id)) - ARRAY['code_md5', 'computed_at'];
    h := (SELECT to_jsonb(x) FROM _0631_attr_before x WHERE x.order_id = r.order_id) - ARRAY['code_md5', 'computed_at'];
    IF g IS DISTINCT FROM h THEN
      RAISE EXCEPTION '0631 V2: order %''s attribution computed now is not its stored one (fields %)', r.order_id,
        (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(g) k WHERE g -> k IS DISTINCT FROM h -> k);
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0631 V2: % attributions this does not touch computed again field for field (% ms)', n,
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000);
END $v2$;

-- ══ (e) the regrades, each attributed order's attribution with it ═════════════════════════════════════════════════════════
CREATE TEMP TABLE _0631_standing_before ON COMMIT DROP AS
SELECT g.* FROM public.ottoq_charge_order_grades g WHERE g.order_id IN (SELECT order_id FROM _0631_affected);

DO $regrade$
DECLARE r record; v jsonb; n int := 0; m int := 0; v_t timestamptz := clock_timestamp();
BEGIN
  FOR r IN SELECT order_id FROM _0631_affected ORDER BY order_id LOOP
    v := public.ottoq_charge_order_regrade(r.order_id, 'fault_cut_read_as_running_end',
           '0631: a fault ended a charge the check modelled under way; it was graded as the running clock''s end');
    n := n + 1;
    m := m + CASE WHEN COALESCE((v ->> 'reattributed')::boolean, false) THEN 1 ELSE 0 END;
  END LOOP;
  RAISE NOTICE '0631: % grades superseded, % attributions with them (% ms)', n, m,
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000);
END $regrade$;

-- ══ V3: each regrade changes the record's cut chargers and the forecasts' running block, and nothing else ══════════════
DO $v3$
DECLARE v_bad text; v_code text := public.ottoq_hindsight_code_md5(); v_n_view int; v_n_ledger int; v_dup int;
BEGIN
  SELECT string_agg(a.order_id::text, ', ' ORDER BY a.order_id) INTO v_bad
    FROM _0631_affected a
    JOIN _0631_standing_before b ON b.order_id = a.order_id
    LEFT JOIN public.ottoq_charge_order_grades g ON g.order_id = a.order_id
   WHERE g.code_md5 IS DISTINCT FROM v_code
      OR g.realized -> 'chargers' IS DISTINCT FROM a.want -> 'chargers'
      -- outside its chargers and the run's status (recorded as it stood when graded), the record is as it was, but on the
      -- grades 0621's own grader gave (§1(e))
      OR (a.code_md5 <> '9f1ff00e6c58b29403a8453578cc23a2'
          AND (g.realized - ARRAY['chargers', 'run_status']) IS DISTINCT FROM (a.want - ARRAY['chargers', 'run_status']))
      OR (g.forecast - 'running') IS DISTINCT FROM (b.forecast - 'running')
      OR (to_jsonb(g) - ARRAY['realized', 'forecast', 'code_md5'])
         IS DISTINCT FROM (to_jsonb(b) - ARRAY['realized', 'forecast', 'code_md5'])
      OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_regrades r
                      WHERE r.order_id = a.order_id AND r.code_md5 = v_code AND r.defect = 'fault_cut_read_as_running_end'
                        AND r.supersedes_code_md5 = b.code_md5
                        AND (SELECT jsonb_agg(c ORDER BY c) FROM jsonb_array_elements_text(r.detail -> 'chargers') c)
                            IS NOT DISTINCT FROM a.chargers);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0631 V3: these regrades are not their standing grade with exactly the cut chargers censored and '
                    'the running block rescored, and nothing else: %', v_bad;
  END IF;
  SELECT count(*), count(*) - count(DISTINCT order_id) INTO v_n_view, v_dup FROM public.ottoq_charge_order_grades;
  SELECT count(*) INTO v_n_ledger FROM public.ottoq_charge_order_hindsight;
  IF v_n_view <> v_n_ledger OR v_dup <> 0 THEN
    RAISE EXCEPTION '0631 V3: the standing grades are not one per graded order (% standing, % graded)', v_n_view, v_n_ledger;
  END IF;
  RAISE NOTICE '0631 V3: % regrades, each its standing grade with exactly the chargers a fault cut censored and cut, the '
               'running block rescored, and the expected future, hindsight, outcome, moves and fidelity as they were; '
               '% of them by 0621''s grader, read now outside their chargers as 0622-0623 read a record',
    (SELECT count(*) FROM _0631_affected),
    (SELECT count(*) FROM _0631_affected a WHERE a.code_md5 = '9f1ff00e6c58b29403a8453578cc23a2');
END $v3$;

-- ══ V4: each reattribution is the same game with its halves made whole ══════════════════════════════════════════════════
DO $v4$
DECLARE v_bad text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _0631_affected a JOIN _0631_attr_before b USING (order_id);
  SELECT string_agg(b.order_id::text, ', ' ORDER BY b.order_id) INTO v_bad
    FROM _0631_affected a JOIN _0631_attr_before b USING (order_id)
    LEFT JOIN public.ottoq_charge_order_attributions n ON n.order_id = b.order_id
   WHERE n.code_md5 IS NOT DISTINCT FROM b.code_md5
      OR n.verdict_changed IS DISTINCT FROM b.verdict_changed
      OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_reattributions r
                      WHERE r.order_id = b.order_id AND r.code_md5 = n.code_md5 AND r.supersedes_code_md5 = b.code_md5
                        AND r.defect = 'fault_cut_read_as_running_end' AND r.computed_at = b.computed_at)
      -- v(none) and v(all) are the first's
      OR n.subset_values -> 0 IS DISTINCT FROM b.subset_values -> 0
      OR n.subset_values -> 31 IS DISTINCT FROM b.subset_values -> 31
      -- every subset holding both or neither of running (bit 3) and faults (bit 4) is the first's, but on the grades
      -- 0621's own grader gave, whose record now reads the other parts as 0622-0623 do (§1(e))
      OR (a.code_md5 <> '9f1ff00e6c58b29403a8453578cc23a2'
          AND EXISTS (SELECT 1 FROM generate_series(0, 31) m
                       WHERE ((m >> 3) & 1) = ((m >> 4) & 1)
                         AND n.subset_values -> m IS DISTINCT FROM b.subset_values -> m))
      -- the five values sum to v(all) - v(none) on each measure
      OR EXISTS (SELECT 1 FROM generate_series(0, 3) i
                  WHERE abs((SELECT sum((p.value ->> (ARRAY['cmp', 'on_time', 'late', 'flow'])[i + 1])::numeric)
                               FROM jsonb_each(n.shapley) p)
                            - ((n.subset_values -> 31 ->> i)::numeric - (n.subset_values -> 0 ->> i)::numeric)) > 0.002);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0631 V4: these reattributions are not the same game with only the half-replays changed: %', v_bad;
  END IF;
  RAISE NOTICE '0631 V4: % reattributions, each with v(none) and v(all) as before and its five values summing to v(all) - '
               'v(none); every subset holding both or neither of running and faults as before on the % not by 0621''s '
               'grader', v_n,
    (SELECT count(*) FROM _0631_affected a JOIN _0631_attr_before b USING (order_id)
      WHERE a.code_md5 <> '9f1ff00e6c58b29403a8453578cc23a2');
END $v4$;

-- ══ V5: the running block and the parts' shares, before and after ══════════════════════════════════════════════════════
DO $v5$
DECLARE b record; a record; v_shares jsonb;
BEGIN
  SELECT * INTO b FROM _0631_before;
  SELECT sum((g.forecast #>> '{running,n}')::numeric) AS n, sum((g.forecast #>> '{running,sum_err}')::numeric) AS sum_err,
         sum((g.forecast #>> '{running,sum_abs_err}')::numeric) AS sum_abs_err
    INTO a
    FROM public.ottoq_charge_order_grades g
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days';
  SELECT jsonb_object_agg(z.part, z.share) INTO v_shares FROM (
    SELECT p.key AS part, round(sum(abs((p.value ->> 'cmp')::numeric)) / NULLIF(sum(sum(abs((p.value ->> 'cmp')::numeric))) OVER (), 0), 3) AS share
      FROM public.ottoq_charge_order_attributions x JOIN public.ottoq_charge_order_grades g ON g.order_id = x.order_id
      CROSS JOIN LATERAL jsonb_each(x.shapley) p
     WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days'
     GROUP BY p.key) z;
  RAISE NOTICE '0631 V5: the charges under way at an order, twin depot, last 7 days: before % uncensored, mean error % '
               'min, MAE % min; after % uncensored, mean error % min, MAE % min. What made the check wrong, share by part: '
               'before %, after %',
    b.n, round(b.sum_err / NULLIF(b.n, 0), 2), round(b.sum_abs_err / NULLIF(b.n, 0), 2),
    a.n, round(a.sum_err / NULLIF(a.n, 0), 2), round(a.sum_abs_err / NULLIF(a.n, 0), 2), b.shares, v_shares;
END $v5$;

-- ══ V6: the readers run on the standing attributions ══════════════════════════════════════════════════════════════════════
DO $v6$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_run uuid; v_tr jsonb; v_n int;
        v_t timestamptz := clock_timestamp();
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_charge_order_grades
   WHERE depot_id = c_twin AND graded_at >= now() - interval '7 days';
  IF v_n = 0 THEN
    RAISE NOTICE '0631 V6: nothing graded at the twin depot in 7 days: the readers have nothing to read here';
    RETURN;
  END IF;
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  IF COALESCE((v ->> 'graded')::int, -1) <> v_n THEN
    RAISE EXCEPTION '0631 V6: the self-review read % graded orders, the standing grades are %', v ->> 'graded', v_n;
  END IF;
  SELECT sim_run_id INTO v_run FROM public.ottoq_charge_order_grades WHERE depot_id = c_twin
   ORDER BY graded_at DESC, order_id DESC LIMIT 1;
  v_tr := public.ottoq_charge_order_track_record(v_run, c_twin, 7);
  IF v_tr IS NULL THEN
    RAISE EXCEPTION '0631 V6: the track record read nothing on run %', v_run;
  END IF;
  RAISE NOTICE '0631 V6: the self-review read % standing grades in % ms; its areas: %', v_n,
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT string_agg((x.value ->> 'rank') || '. ' || (x.value ->> 'title'), ' | '
                                ORDER BY (x.value ->> 'rank')::int)
                FROM jsonb_array_elements(v -> 'improvement_areas') x
               WHERE (x.value ->> 'rank')::int <= 4), 'none');
END $v6$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0631_a_fault_owns_the_charge_it_cut', false, false,
  'ottoq_charge_order_realized reads a charge under way that a fault ended inside the window as censored at the fault in '
  'the running part, with cut, the fault''s minute; ottoq_charge_line_realize ends it there in the faults part; the '
  'attribution is computed by ottoq_charge_order_attribute_compute, kept first by ottoq_charge_order_attribute and beside '
  'a superseded first by ottoq_charge_order_regrade in ottoq_charge_order_reattributions (append-only evidence); its '
  'readers read ottoq_charge_order_attributions; the grades that read a fault''s cut as the clock''s end are regraded '
  'with their attributions. FALSE/FALSE: evidence only, as 0630; the replay is the grader''s and the attribution''s.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
