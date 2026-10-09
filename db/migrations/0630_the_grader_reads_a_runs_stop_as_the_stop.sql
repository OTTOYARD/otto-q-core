-- migration-version: 20261009100905
-- migration-name:    the_grader_reads_a_runs_stop_as_the_stop
--
-- 0630  **The grader reads a run's stop as the stop, and a grade found wrong is superseded beside the first.**
--       The kernel grades every agent charge order its check judged (0621) against what happened in the 90 sim-minutes
--       after it. For each charger the check modelled busy at the order, the grade reads when the charge under way
--       ended. A run's stop ends every open charge on the run's own clock, and the grader read those as charges that
--       ended there. 0630 reads them as charges still running at the cut, grades the orders that read them again, and
--       keeps each new grade beside the first, with the defect named.
--
-- ══ §1 WHY (measured 2026-10-09 04:30-05:20 UTC, 11:30 PM-12:20 AM CT the night of the 8th) ════════════════════════════
--
--   (a) The defect. ottoq_charge_order_realized reads, for each charger the check modelled busy at the order (free > 0),
--       the latest session started before the order and not ended by it: its end if that came by the cut, else the
--       charger is censored at the cut. The cut is the earlier of the window (90 minutes) and the run's clock. The
--       operator's stop (ottoq_sim_release_depot, G248) closes every open session as cancelled, stopped_reason
--       'sim_reset', on the run's own clock: 4,039 such sessions over 163 runs, every one ended at its run's last
--       clock, none before it. So for an order whose window reached the stop, every charger still busy at the stop
--       read "free at the cut, not censored": a charge the stop interrupted was graded as a charge that ended there.
--   (b) Its reach. 99 of the 247 stored grades, every one whose window the stop cut short: 50 of b2efcc07's 136, 47 of
--       d9d49732's 109, both of c4ee1572's (the production session of 0423 §4). 3,119 charger records in them, 5 of
--       them decisions, none attributed. The other 148 are untouched: 86 were graded while their run ran (their windows
--       closed first), 1 closed before its run's stop, and the 61 graded by 0621's own grader (code 9f1ff00e, the
--       minutes after it was applied) all closed while d9d49732 ran.
--   (c) What it did. The forecasts' running block (ottoq_charge_order_forecast_errors) scores only uncensored chargers,
--       so it scored these: the self-review's first area, "Charges under way ended sooner than it expected", read them
--       ending a mean 47.73 minutes early. V5 prints the block before and after.
--   (d) An earlier count of this defect read 44 grades, not 99. It rebuilt the cut as the order's clock plus the stored
--       observed_min, which is rounded to the hundredth of a minute, and the stop is the cut exactly: the rebuilt cut
--       fell a fraction of a minute short of the stop on 55 of the 99. Everything here reads the realizer's own cut.
--   (e) Why supersede and not rewrite. The grades are append-only evidence (0621): a grade is what the grader said
--       when it said it, and that it was wrong is evidence too. So the first grade stays, the grader as it is now
--       grades the order again, and the new grade is kept beside the first, naming the defect and what changed. The
--       readers read the standing grade: the newest regrade, else the first.
--   (f) Rehearsed on live before writing this, read-only, with a pg_temp copy of the patched realizer over all 247:
--       for the 99, exactly the first record with each charger the stop interrupted censored (free no sooner than the
--       cut, and no sooner than the check's own forecast); for the other 87 by the same grader, exactly the first record
--       but for run_status on the 86 graded while their run ran (the grade records the run as it stood when graded;
--       recomputed, those 8 sampled read the same grade in every other field). And 0621's grade, computed by a copy of
--       its body, reproduced the stored grades exactly. A grade costs 0.37-0.55 s, a realized record 0.19 s.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq_charge_order_realized: the charge under way at the order ends at its session's end unless the session
--       was ended by the run's stop (stopped_reason 'sim_reset'); such a charger reads as a charge still running at the
--       cut does: censored, free no sooner than the cut. Nothing else in the record changes (§1(f)).
--   (b) public.ottoq_charge_order_grades, a view: one row per graded order, the standing grade, in the ledger's own
--       columns and order: the order's newest regrade, else its first grade.
--   (c) public.ottoq_charge_order_regrades, a new append-only evidence table: a grade of an order already graded, by the
--       grader as it is now, in the ledger's columns (graded_at is the first grade's, so the standing grade sits in the
--       windows readers count by), with regraded_at, the code of the grade it supersedes, the defect (a short code)
--       and what changed (the grade's fields, the chargers whose record changed, the outcome before and after).
--   (d) public.ottoq_charge_order_grade_compute(order, window): 0621's grade computed and returned, written nowhere,
--       as a row of (b). ottoq_charge_order_grade keeps it the first time and returns the standing grade; the regrade
--       keeps it beside the first. One computation for both. ottoq_hindsight_code_md5 covers it.
--   (e) public.ottoq_charge_order_regrade(order, defect, note): grades an order again and keeps it in (c). Refused: no
--       grade to supersede, the order's run purged, an attribution computed from the grade it would supersede, the
--       grader unchanged since the standing grade. A person's tool run in a migration that names the defect; no cron
--       and no agent calls it, and it changes no decision, rule or setting (rule 10).
--   (f) The eight readers of the ledger read (b): the usage, the attribution, the pending grader, the track record the
--       agent's board carries, the three self-reviews and the clock's calibration. Only the grader names the ledger,
--       to write it.
--   (g) The 99 orders of §1(b) are regraded under 'run_stop_read_as_charge_end'.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, and no run running (a running run's charge-order door grades its orders as their windows
--   close). P1 the eleven bodies are the ones measured, the five objects are new, the ledger's columns are the ones
--   measured, the functions naming the ledger are exactly the grader and its eight readers, each anchor matches once,
--   and no order this regrades has an attribution. V1 the realizer's change and the code md5's list by meaning; each
--   reader is its measured body with the ledger's name swapped, and nothing else. V2 the computation reproduces six
--   grades this does not touch, field for field but the code and, for a grade taken while its run ran, the run's
--   status. V3 each supersession: the regrade's record is its first with exactly the interrupted chargers censored,
--   its code is the grader's now and supersedes the first's, its graded_at is the first's, and the standing grades are
--   the regrades for exactly these orders and the first grades for every other, one per order. V4 only the grader
--   names the ledger. V5 the running block before and after, and every outcome the regrades changed. V6 the readers
--   run: the self-review counts every standing grade, the track record and the usage read them. Executed by
--   tests/test_agent_regrade_sql.py on the miniature depot: a stopped run's interrupted charge is censored and its
--   first grade superseded, a grade after 0630 reads the stop as the stop, the computation is the grade, each refusal.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. The grader and its readers write and read evidence tables only;
--   no kernel decision, dial or seat reads a grade (the agent's board carries the track record, which the agent reads
--   as a proposer whose every order the kernel checks). The charge-order door still grades a running run's closed
--   orders, by the same computation, and a running run has no session its stop ended. No certification arm runs the
--   agent or the charge order (0615).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0630_pre' AND object_kind = 'function';
--   then DROP FUNCTION public.ottoq_charge_order_regrade(bigint, text, text),
--   public.ottoq_charge_order_grade_compute(bigint, numeric); DROP VIEW public.ottoq_charge_order_grades; and, only
--   if its rows are kept elsewhere first (they are evidence), DROP TABLE public.ottoq_charge_order_regrades and its
--   registry row; DELETE FROM public.ottoq_cert_lineage WHERE name = '0630_the_grader_reads_a_runs_stop_as_the_stop'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe), and no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0630 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0630 P0: a run is running; its charge-order door grades its orders as their windows close. Apply '
                    'between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones measured; the objects are new; the ledger and its readers are the ones measured ──
DO $premises$
DECLARE r record; v_cols text; v_names text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_order_realized(bigint,numeric)',                              '629145041dff225d0f00965d78e1dab2'),
    ('public.ottoq_charge_order_grade(bigint,numeric)',                                 'cf987b5240e2224e8a4ff815855af11c'),
    ('public.ottoq_hindsight_code_md5()',                                               '322ee2fd27988cd2b6f170daac7753d8'),
    ('public.ottoq_agent_charge_order_usage(uuid,integer)',                             '0e40876ed8200abfdce3687eaf7ab73f'),
    ('public.ottoq_charge_order_attribute(bigint)',                                     'c4d1ce64380380ee84a25ce9b4fa6295'),
    ('public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)',  '350c719bdb07336771bd6032a1d7174e'),
    ('public.ottoq_charge_order_track_record(uuid,uuid,integer)',                       '6915937e83e3db434ea3bd744fcb53f7'),
    ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)',             '97d1401b509819850b68ead0ab3bfde3'),
    ('public.ottoq_charge_clock_calibration(uuid,timestamp with time zone)',            '8c11d790f2402350bd8b79c969a0a398'),
    ('public.ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)',          'c6acb1e84d9e7d5c2b128997dc98be8f'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',  'e8e91cc2f9a26347352c75f52fa47dd7'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0630 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_charge_order_grade_compute(bigint,numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_order_regrade(bigint,text,text)') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_grades') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_regrades') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0630_the_grader_reads_a_runs_stop_as_the_stop') THEN
    RAISE EXCEPTION '0630 P1: already applied';
  END IF;
  -- the ledger's columns, which the view and the regrades keep in its order
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_charge_order_hindsight'::regclass AND a.attnum > 0
     AND NOT a.attisdropped;
  IF v_cols IS DISTINCT FROM 'order_id,sim_run_id,depot_id,sim_clock,window_min,observed_min,status,reason,taken,decision,'
                             'futures,wins,need,p_win,expected,hindsight,outcome,moves,forecast,fidelity,realized,'
                             'code_md5,graded_at' THEN
    RAISE EXCEPTION '0630 P1: the ledger''s columns are not the ones measured: %', v_cols;
  END IF;
  -- every function that names the ledger is the grader or one of the eight readers 0630 swaps
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_names
    FROM pg_proc p
   WHERE p.prosrc ~ 'ottoq_charge_order_hindsight(?![a-z_0-9])'
     AND p.oid NOT IN ('public.ottoq_charge_order_grade(bigint,numeric)'::regprocedure,
                       'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                       'public.ottoq_charge_order_attribute(bigint)'::regprocedure,
                       'public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)'::regprocedure,
                       'public.ottoq_charge_order_track_record(uuid,uuid,integer)'::regprocedure,
                       'public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)'::regprocedure,
                       'public.ottoq_charge_clock_calibration(uuid,timestamp with time zone)'::regprocedure,
                       'public.ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)'::regprocedure,
                       'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);
  IF v_names IS NOT NULL THEN
    RAISE EXCEPTION '0630 P1: these name the ledger and 0630 was not written against them: %', v_names;
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0630_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure,
                 'public.ottoq_charge_order_grade(bigint,numeric)'::regprocedure,
                 'public.ottoq_hindsight_code_md5()'::regprocedure,
                 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                 'public.ottoq_charge_order_attribute(bigint)'::regprocedure,
                 'public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)'::regprocedure,
                 'public.ottoq_charge_order_track_record(uuid,uuid,integer)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_clock_calibration(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- ── the orders this regrades, read before anything changes: each stored grade with a charger the check modelled busy
--    whose charge under way the run's stop ended by the realizer's own cut (§1(d)), and those chargers ──
CREATE TEMP TABLE _0630_affected ON COMMIT DROP AS
WITH g AS (
  SELECT h.order_id, h.sim_run_id, h.depot_id, h.code_md5, h.outcome, h.observed_min, h.graded_at, h.realized,
         s.sim_clock AS t0, s.state,
         GREATEST(LEAST(s.sim_clock + make_interval(secs => GREATEST(COALESCE(h.window_min, 90), 1) * 60),
                        COALESCE(r.sim_clock_current, s.sim_clock)), s.sim_clock) AS cut
    FROM public.ottoq_charge_order_hindsight h
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = h.sim_run_id AND r.purged_at IS NULL),
hit AS (
  SELECT g.order_id, c.id AS charger, c.free AS forecast_free, rs.ended_at
    FROM g
    CROSS JOIN LATERAL (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'free')::numeric, 0) AS free
                          FROM jsonb_array_elements(COALESCE(g.state -> 'chargers', '[]'::jsonb)) x
                         WHERE (x.value ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
    JOIN LATERAL (SELECT os.ended_at, os.stopped_reason FROM public.ocpp_sessions os
                   WHERE c.free > 0 AND os.sim_run_id = g.sim_run_id AND os.stall_id = c.id::uuid
                     AND os.started_at < g.t0 AND (os.ended_at IS NULL OR os.ended_at > g.t0)
                   ORDER BY os.started_at DESC LIMIT 1) rs ON true
   WHERE rs.stopped_reason = 'sim_reset' AND rs.ended_at <= g.cut)
SELECT g.order_id, g.sim_run_id, g.depot_id, g.code_md5, g.outcome, g.observed_min, g.graded_at, g.realized,
       jsonb_agg(jsonb_build_object('id', hit.charger, 'forecast_free', hit.forecast_free) ORDER BY hit.charger) AS chargers,
       -- the record the patched realizer must return: the first, with each charger the stop interrupted censored
       jsonb_set(g.realized, '{chargers}',
                 (SELECT jsonb_object_agg(k.key, CASE WHEN h2.charger IS NULL THEN k.value
                                                      ELSE k.value || jsonb_build_object(
                                                             'free', GREATEST(g.observed_min, h2.forecast_free),
                                                             'cen', true) END)
                    FROM jsonb_each(g.realized -> 'chargers') k
                    LEFT JOIN hit h2 ON h2.order_id = g.order_id AND h2.charger = k.key)) AS want
  FROM g JOIN hit ON hit.order_id = g.order_id
 GROUP BY g.order_id, g.sim_run_id, g.depot_id, g.code_md5, g.outcome, g.observed_min, g.graded_at, g.realized;

DO $p1b$
DECLARE v_attr text;
BEGIN
  SELECT string_agg(a.order_id::text, ', ' ORDER BY a.order_id) INTO v_attr
    FROM _0630_affected a JOIN public.ottoq_charge_order_attribution x ON x.order_id = a.order_id;
  IF v_attr IS NOT NULL THEN
    RAISE EXCEPTION '0630 P1: orders % read a charge the stop ended and have an attribution computed from it; supersede '
                    'both or neither (0630 supersedes grades only)', v_attr;
  END IF;
  RAISE NOTICE '0630: % stored grades read a charge the run''s stop ended (% charger records; % decisions), of % graded',
    (SELECT count(*) FROM _0630_affected), (SELECT COALESCE(sum(jsonb_array_length(chargers)), 0) FROM _0630_affected),
    (SELECT count(*) FROM _0630_affected a JOIN public.ottoq_charge_order_hindsight h USING (order_id) WHERE h.decision),
    (SELECT count(*) FROM public.ottoq_charge_order_hindsight);
END $p1b$;

-- V5's before: the forecasts' running block over the twin depot's last seven days, as the ledger reads it
CREATE TEMP TABLE _0630_running_before ON COMMIT DROP AS
SELECT sum((h.forecast #>> '{running,n}')::numeric) AS n,
       sum((h.forecast #>> '{running,sum_err}')::numeric) AS sum_err,
       sum((h.forecast #>> '{running,sum_abs_err}')::numeric) AS sum_abs_err
  FROM public.ottoq_charge_order_hindsight h
 WHERE h.depot_id = '11111111-1111-1111-1111-111111111111' AND h.graded_at >= now() - interval '7 days';

-- ══ (c) the regrades ══════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_order_regrades (
  --: the ledger's columns, in its order (0621). graded_at is the FIRST grade's, so the standing grade sits in the
  --: windows readers count by; regraded_at is when this grade was computed. NO foreign key (evidence, 0340/0364).
  LIKE public.ottoq_charge_order_hindsight INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
  --: the statement clock, not the transaction's: two regrades of one order in one transaction still stand in order
  regraded_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  --: the code of the grade this one supersedes (ottoq_hindsight_code_md5 when it was given)
  supersedes_code_md5  text NOT NULL,
  --: why, as a short code: 0630's is run_stop_read_as_charge_end
  defect               text NOT NULL,
  --: what changed: the grade's fields, the chargers whose record changed, the outcome before and after, a note
  detail               jsonb NOT NULL,
  PRIMARY KEY (order_id, code_md5),
  CONSTRAINT ottoq_charge_order_regrades_defect_ck CHECK (defect ~ '^[a-z][a-z0-9_]{2,62}$'),
  CONSTRAINT ottoq_charge_order_regrades_new_code_ck CHECK (supersedes_code_md5 <> code_md5)
);

COMMENT ON TABLE public.ottoq_charge_order_regrades IS
'0630. A grade of an agent charge order already graded (ottoq_charge_order_hindsight), by the grader as it is now, kept beside the first when the first is found wrong: the ledger''s columns (graded_at the first grade''s), when it was computed, the code it supersedes, the defect and what changed. ottoq_charge_order_grades reads the newest. Written only by ottoq_charge_order_regrade, in a migration that names the defect. Class=evidence with NO foreign key (0340/0364). Append-only (override: ottoq.hindsight_unlock=on).';

CREATE TRIGGER ottoq_charge_order_regrades_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_order_regrades
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();

ALTER TABLE public.ottoq_charge_order_regrades ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_order_regrades_read ON public.ottoq_charge_order_regrades FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_order_regrades FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_regrades TO anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_charge_order_regrades', 'sim_run_id', 'evidence',
        '0630: a later grade of a graded agent charge order, kept beside the first when the first is found wrong, with '
        'the defect named. Evidence, not engine. NO foreign key to ottoq_sim_runs, as 0340, 0364 and 0621.');

-- ══ (b) the standing grade ════════════════════════════════════════════════════════════════════════════════════════════════
CREATE VIEW public.ottoq_charge_order_grades WITH (security_invoker = true) AS
SELECT h.order_id, h.sim_run_id, h.depot_id, h.sim_clock, h.window_min, h.observed_min, h.status, h.reason, h.taken,
       h.decision, h.futures, h.wins, h.need, h.p_win, h.expected, h.hindsight, h.outcome, h.moves, h.forecast,
       h.fidelity, h.realized, h.code_md5, h.graded_at
  FROM public.ottoq_charge_order_hindsight h
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_regrades r WHERE r.order_id = h.order_id)
UNION ALL
SELECT r.order_id, r.sim_run_id, r.depot_id, r.sim_clock, r.window_min, r.observed_min, r.status, r.reason, r.taken,
       r.decision, r.futures, r.wins, r.need, r.p_win, r.expected, r.hindsight, r.outcome, r.moves, r.forecast,
       r.fidelity, r.realized, r.code_md5, r.graded_at
  FROM public.ottoq_charge_order_regrades r
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_regrades n
                    WHERE n.order_id = r.order_id AND (n.regraded_at, n.code_md5) > (r.regraded_at, r.code_md5));

COMMENT ON VIEW public.ottoq_charge_order_grades IS
'0630. The standing grade of every graded agent charge order, in the ledger''s columns: its newest regrade (ottoq_charge_order_regrades) if it has one, else its first grade (ottoq_charge_order_hindsight). Every reader of the grades reads this; only the grader writes the ledger.';

REVOKE ALL ON public.ottoq_charge_order_grades FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_grades TO anon, authenticated;

-- ══ (d) one computation for the first grade and a regrade ═════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_grade_compute(p_order_id bigint, p_window_min numeric DEFAULT 90)
 RETURNS public.ottoq_charge_order_grades
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0630: one checked order's grade as the grader computes it now, written nowhere: the row ottoq_charge_order_grade keeps
   the first time an order is graded, and the row ottoq_charge_order_regrade keeps beside it when a first grade is found
   wrong. This is 0621's grade (with 0623's forecast errors and stored sides), moved here unchanged. NULL when the order
   has no snapshot. graded_at is now(); code_md5 is ottoq_hindsight_code_md5(), which covers this. */
DECLARE
  g public.ottoq_charge_order_grades;
  s record; o record; v_real jsonb; v_full jsonb; ek jsonb; ea jsonb; hk jsonb; ha jsonb;
  v_exp jsonb; v_hind jsonb; v_reason text; v_taken boolean; v_decision boolean; v_outcome text; v_hc int;
  v_futures int; v_wins int; v_need int; v_w numeric := GREATEST(COALESCE(p_window_min, 90), 1);
BEGIN
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO o FROM ottoq_agent_charge_orders x WHERE x.order_id = p_order_id;
  v_reason := COALESCE(o.projection ->> 'reason', 'unknown');
  v_taken := COALESCE(o.status IN ('accepted', 'partial'), false);
  v_decision := v_reason IN ('worse_in_expected_future', 'no_better_in_expected_future', 'not_enough_futures_won',
                             'wins_most_futures');
  v_futures := CASE WHEN (o.projection ->> 'futures') ~ '^[0-9]+$' THEN (o.projection ->> 'futures')::int END;
  v_wins := CASE WHEN (o.projection ->> 'wins') ~ '^[0-9]+$' THEN (o.projection ->> 'wins')::int END;
  v_need := CASE WHEN (o.projection ->> 'need') ~ '^[0-9]+$' THEN (o.projection ->> 'need')::int END;

  v_real := public.ottoq_charge_order_realized(p_order_id, v_w);
  ek := public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true);
  ea := public.ottoq_charge_line_schedule(s.state, s.agent_order, 0, s.seed, true);
  v_full := public.ottoq_charge_line_realize(s.state, v_real,
                                             ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']);
  hk := public.ottoq_charge_line_schedule(v_full, NULL, 0, s.seed, true);
  ha := public.ottoq_charge_line_schedule(v_full, s.agent_order, 0, s.seed, true);
  v_exp := public.ottoq_charge_line_compare(ek, ea);
  v_hind := public.ottoq_charge_line_compare(hk, ha);
  v_hc := (v_hind ->> 'cmp')::int;
  v_outcome := CASE WHEN NOT v_decision THEN
                      CASE WHEN (hk -> 'first') IS NOT DISTINCT FROM (ha -> 'first') THEN 'no_decision'
                           ELSE 'no_decision_mattered' END
                    WHEN v_taken AND v_hc > 0 THEN 'right_take'
                    WHEN v_taken AND v_hc = 0 THEN 'neutral_take'
                    WHEN v_taken THEN 'wrong_take'
                    WHEN v_hc > 0 THEN 'missed_win'
                    ELSE 'right_refusal' END;

  g.order_id := p_order_id;
  g.sim_run_id := s.sim_run_id;
  g.depot_id := s.depot_id;
  g.sim_clock := s.sim_clock;
  g.window_min := v_w;
  g.observed_min := COALESCE((v_real ->> 'observed_min')::numeric, 0);
  g.status := o.status;
  g.reason := v_reason;
  g.taken := v_taken;
  g.decision := v_decision;
  g.futures := v_futures;
  g.wins := v_wins;
  g.need := v_need;
  g.p_win := CASE WHEN v_decision AND v_futures > 0 THEN round(v_wins::numeric / v_futures, 4) END;
  g.expected := v_exp || jsonb_build_object('kernel', ek - ARRAY['first', 'seats', 'return_seats'],
                                            'agent', ea - ARRAY['first', 'seats', 'return_seats']);
  g.hindsight := v_hind || jsonb_build_object('kernel', hk - ARRAY['first', 'seats', 'return_seats'],
                                              'agent', ha - ARRAY['first', 'seats', 'return_seats']);
  g.outcome := v_outcome;
  g.moves := CASE WHEN v_decision OR v_outcome = 'no_decision_mattered'
                  THEN public.ottoq_charge_order_moves(s.state, ek, ea) ELSE '{}'::text[] END;
  g.forecast := public.ottoq_charge_order_forecast_errors(s.state, v_real, CASE WHEN v_taken THEN ea ELSE ek END);
  g.fidelity := public.ottoq_charge_order_fidelity(CASE WHEN v_taken THEN ha ELSE hk END, v_real);
  g.realized := COALESCE(v_real, '{}'::jsonb);
  g.code_md5 := public.ottoq_hindsight_code_md5();
  g.graded_at := now();
  RETURN g;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_order_grade_compute(bigint, numeric) IS
'0630. One checked order''s grade as the grader computes it now, written nowhere: what ottoq_charge_order_grade keeps the first time and ottoq_charge_order_regrade keeps beside a first grade found wrong. 0621''s grade, moved here unchanged. NULL without a snapshot.';

-- ══ the grade keeps the computation the first time and returns the standing grade ═══════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_order_grade(p_order_id bigint, p_window_min numeric DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: one checked order, graded once: the check's expected future (scenario 0 of its own rollout) and the world that
   came, each replayed both ways by the same simulator from the same state; the outcome; what the order changed; how
   each forecast fared; how close the simulator came given the real inputs. Writes only its own ledger.
   0623: the forecast errors grade the outflow too, against the expected future of the order that ran; the stored
   sides leave out their traces.
   0630: computed by ottoq_charge_order_grade_compute, which a regrade shares; kept here the first time; and what this
   returns is the order's standing grade (ottoq_charge_order_grades: its newest regrade, else its first grade). */
DECLARE
  v_row jsonb; g public.ottoq_charge_order_grades;
BEGIN
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_grades x WHERE x.order_id = p_order_id;
  IF v_row IS NOT NULL THEN RETURN v_row; END IF;
  g := public.ottoq_charge_order_grade_compute(p_order_id, p_window_min);
  IF g.order_id IS NULL THEN RETURN NULL; END IF;
  INSERT INTO ottoq_charge_order_hindsight
    (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min, status, reason, taken, decision, futures,
     wins, need, p_win, expected, hindsight, outcome, moves, forecast, fidelity, realized, code_md5)
  VALUES (g.order_id, g.sim_run_id, g.depot_id, g.sim_clock, g.window_min, g.observed_min, g.status, g.reason,
          g.taken, g.decision, g.futures, g.wins, g.need, g.p_win, g.expected, g.hindsight, g.outcome, g.moves,
          g.forecast, g.fidelity, g.realized, g.code_md5)
  ON CONFLICT (order_id) DO NOTHING;
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_grades x WHERE x.order_id = p_order_id;
  RETURN v_row;
END $fn$;

-- ══ the anchored patches: (a) the realizer, and the code md5's list; each anchor once, the stored definition after ═══════
CREATE TEMP TABLE _0630_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0630_patch VALUES
('public.ottoq_charge_order_realized(bigint,numeric)', 1,
$old$a fault after the cut blanked them (§1(g)). */$old$,
$new$a fault after the cut blanked them (§1(g)).
   0630: a charge the run's stop ended (stopped_reason sim_reset, which the stop writes on every charge still open, on
   the run's own clock) did not end there: the charger it held reads as one still busy at the cut does, censored and
   free no sooner than the cut. 0621-0629 read such a charger as free at the cut, uncensored. */$new$),
('public.ottoq_charge_order_realized(bigint,numeric)', 2,
$old$(SELECT os.stall_id, os.ended_at FROM ocpp_sessions os$old$,
$new$(SELECT os.stall_id,
                              -- 0630: the run's stop ends no charge: it is still under way at the cut
                              CASE WHEN os.stopped_reason = 'sim_reset' THEN NULL ELSE os.ended_at END AS ended_at
                         FROM ocpp_sessions os$new$),
('public.ottoq_hindsight_code_md5()', 1,
$old$  -- 0623: and the outflow's draws and its forecast errors.$old$,
$new$  -- 0623: and the outflow's draws and its forecast errors.
  -- 0630: and the grade's computation, which the first grade and a regrade share.$new$),
('public.ottoq_hindsight_code_md5()', 2,
$old$                      'public.ottoq_charge_order_grade(bigint,numeric)',$old$,
$new$                      'public.ottoq_charge_order_grade(bigint,numeric)',
                      'public.ottoq_charge_order_grade_compute(bigint,numeric)',$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0630_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0630_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0630 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0630 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ (e) a regrade ═════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_regrade(p_order_id bigint, p_defect text, p_note text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0630: grade a graded order again, by the grader as it is now, and keep the new grade beside the first in
   ottoq_charge_order_regrades, naming why (p_defect, a short code) and what changed. The first grade stays as it was
   (append-only evidence); ottoq_charge_order_grades reads the newest. A person's tool, run in a migration that names the
   defect: no cron and no agent calls it, and it changes no decision, rule or setting (rule 10). Refused: a defect not
   named as a short code; no grade to supersede; the order's run purged, so what happened can no longer be read; an
   attribution computed from the grade it would supersede; the grader unchanged since the standing grade, so a regrade
   would repeat it. */
DECLARE
  f public.ottoq_charge_order_grades; g public.ottoq_charge_order_grades; v_old jsonb; v_new jsonb; v_detail jsonb;
BEGIN
  IF p_defect IS NULL OR p_defect !~ '^[a-z][a-z0-9_]{2,62}$' THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: name the defect as a short code, not %', COALESCE(p_defect, 'NULL')
      USING ERRCODE = '22023';
  END IF;
  SELECT * INTO f FROM ottoq_charge_order_grades x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: order % has no grade to supersede', p_order_id USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = f.sim_run_id AND r.purged_at IS NULL) THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: order %''s run % was purged: what happened can no longer be read',
      p_order_id, f.sim_run_id USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_charge_order_attribution a WHERE a.order_id = p_order_id) THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: order % has an attribution computed from the grade this would '
                    'supersede; supersede both or neither', p_order_id USING ERRCODE = '22023';
  END IF;
  g := public.ottoq_charge_order_grade_compute(p_order_id, f.window_min);
  IF g.order_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: order % has no snapshot', p_order_id USING ERRCODE = '22023';
  END IF;
  IF g.code_md5 = f.code_md5 THEN
    RAISE EXCEPTION 'ottoq_charge_order_regrade: the grader has not changed since order % was graded (code %): a regrade '
                    'would repeat it', p_order_id, left(f.code_md5, 8) USING ERRCODE = '22023';
  END IF;
  v_old := to_jsonb(f);
  v_new := to_jsonb(g);
  v_detail := jsonb_strip_nulls(jsonb_build_object(
    'changed', (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb) FROM jsonb_object_keys(v_new) k
                 WHERE k NOT IN ('code_md5', 'graded_at') AND v_new -> k IS DISTINCT FROM v_old -> k),
    'chargers', (SELECT COALESCE(jsonb_agg(z.k ORDER BY z.k), '[]'::jsonb)
                   FROM (SELECT jsonb_object_keys(COALESCE(f.realized -> 'chargers', '{}'::jsonb))
                         UNION
                         SELECT jsonb_object_keys(COALESCE(g.realized -> 'chargers', '{}'::jsonb))) z(k)
                  WHERE f.realized #> ARRAY['chargers', z.k] IS DISTINCT FROM g.realized #> ARRAY['chargers', z.k]),
    'outcome', jsonb_build_object('was', f.outcome, 'now', g.outcome),
    'note', p_note));
  INSERT INTO ottoq_charge_order_regrades
    (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min, status, reason, taken, decision, futures,
     wins, need, p_win, expected, hindsight, outcome, moves, forecast, fidelity, realized, code_md5, graded_at,
     supersedes_code_md5, defect, detail)
  VALUES (g.order_id, g.sim_run_id, g.depot_id, g.sim_clock, g.window_min, g.observed_min, g.status, g.reason,
          g.taken, g.decision, g.futures, g.wins, g.need, g.p_win, g.expected, g.hindsight, g.outcome, g.moves,
          g.forecast, g.fidelity, g.realized, g.code_md5, f.graded_at,
          f.code_md5, p_defect, v_detail)
  ON CONFLICT (order_id, code_md5) DO NOTHING;
  RETURN jsonb_build_object('order_id', p_order_id, 'defect', p_defect, 'supersedes', f.code_md5, 'code_md5', g.code_md5)
         || v_detail;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_order_regrade(bigint, text, text) IS
'0630. Grade a graded agent charge order again, by the grader as it is now, and keep it beside the first in ottoq_charge_order_regrades with the defect named and what changed. A person''s tool, run in a migration; refused without a grade to supersede, on a purged run, with an attribution, or when the grader has not changed.';

REVOKE ALL ON FUNCTION public.ottoq_charge_order_grade_compute(bigint, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_order_regrade(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_grade_compute(bigint, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_regrade(bigint, text, text) TO service_role;

-- ══ (f) the readers read the standing grade: each its measured body with the ledger's name swapped, and nothing else ════
CREATE TEMP TABLE _0630_readers (fn text, refs int) ON COMMIT DROP;
INSERT INTO _0630_readers VALUES
  ('public.ottoq_agent_charge_order_usage(uuid,integer)',                             4),
  ('public.ottoq_charge_order_attribute(bigint)',                                     1),
  ('public.ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)',  3),
  ('public.ottoq_charge_order_track_record(uuid,uuid,integer)',                       2),
  ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)',            14),
  ('public.ottoq_charge_clock_calibration(uuid,timestamp with time zone)',            1),
  ('public.ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)',          2),
  ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',  6);

DO $readers$
DECLARE r record; v_pre text; v_def text; n int;
BEGIN
  FOR r IN SELECT * FROM _0630_readers ORDER BY fn LOOP
    v_pre := pg_get_functiondef(to_regprocedure(r.fn));
    n := (SELECT count(*) FROM regexp_matches(v_pre, 'ottoq_charge_order_hindsight(?![a-z_0-9])', 'g'));
    IF n IS DISTINCT FROM r.refs OR strpos(v_pre, 'ottoq_charge_order_grades') > 0 THEN
      RAISE EXCEPTION '0630 (f): % names the ledger % times (measured %), or already names the view', r.fn, n, r.refs;
    END IF;
    v_def := regexp_replace(v_pre, 'ottoq_charge_order_hindsight(?![a-z_0-9])', 'ottoq_charge_order_grades', 'g');
    IF regexp_replace(v_def, 'ottoq_charge_order_grades(?![a-z_0-9])', 'ottoq_charge_order_hindsight', 'g')
       IS DISTINCT FROM v_pre THEN
      RAISE EXCEPTION '0630 V1: % swapped back is not its measured body', r.fn;
    END IF;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(r.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0630 V1: % is not stored as swapped', r.fn;
    END IF;
  END LOOP;
END $readers$;

-- ══ V1, by meaning: the realizer's running charger reads the stop as no end; the code md5 covers the computation ══════
DO $v1$
DECLARE v_real text; v_md5 text;
BEGIN
  v_real := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure),
                                          '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_real, 'CASE WHEN os.stopped_reason = ''sim_reset'' THEN NULL ELSE os.ended_at END AS ended_at') = 0
     OR strpos(v_real, 'CASE WHEN os.stopped_reason = ''sim_reset'' THEN NULL ELSE os.ended_at END AS ended_at')
        > strpos(v_real, 'ORDER BY os.started_at DESC LIMIT 1) rs ON true') THEN
    RAISE EXCEPTION '0630 V1: the running charger''s session does not read the stop as no end';
  END IF;
  v_md5 := pg_get_functiondef('public.ottoq_hindsight_code_md5()'::regprocedure);
  IF strpos(v_md5, '''public.ottoq_charge_order_grade_compute(bigint,numeric)''') = 0 THEN
    RAISE EXCEPTION '0630 V1: the code md5 does not cover the grade''s computation';
  END IF;
END $v1$;

-- ══ V2: the computation reproduces grades this does not touch ════════════════════════════════════════════════════════════
DO $v2$
DECLARE r record; g jsonb; h jsonb; n int := 0; v_t timestamptz := clock_timestamp();
BEGIN
  FOR r IN
    SELECT x.order_id, x.graded_at < COALESCE(s.ended_at, 'infinity'::timestamptz) AS while_running
      FROM public.ottoq_charge_order_hindsight x
      JOIN public.ottoq_sim_runs s ON s.sim_run_id = x.sim_run_id AND s.purged_at IS NULL
     WHERE x.code_md5 = (SELECT h2.code_md5 FROM public.ottoq_charge_order_hindsight h2 ORDER BY h2.graded_at DESC LIMIT 1)
       AND NOT EXISTS (SELECT 1 FROM _0630_affected a WHERE a.order_id = x.order_id)
     ORDER BY md5(x.order_id::text) LIMIT 6
  LOOP
    g := to_jsonb(public.ottoq_charge_order_grade_compute(r.order_id, 90)) - ARRAY['code_md5', 'graded_at'];
    h := (SELECT to_jsonb(x) FROM public.ottoq_charge_order_hindsight x WHERE x.order_id = r.order_id)
         - ARRAY['code_md5', 'graded_at'];
    IF r.while_running THEN
      g := jsonb_set(g, '{realized,run_status}', 'null');
      h := jsonb_set(h, '{realized,run_status}', 'null');
    END IF;
    IF g IS DISTINCT FROM h THEN
      RAISE EXCEPTION '0630 V2: order %''s grade computed now is not its stored grade (fields %)', r.order_id,
        (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(g) k WHERE g -> k IS DISTINCT FROM h -> k);
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0630 V2: % grades this does not touch computed again field for field (% ms)', n,
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000);
END $v2$;

-- ══ (g) the regrades ══════════════════════════════════════════════════════════════════════════════════════════════════════
DO $regrade$
DECLARE r record; v jsonb; n int := 0; v_t timestamptz := clock_timestamp();
BEGIN
  FOR r IN SELECT order_id FROM _0630_affected ORDER BY order_id LOOP
    v := public.ottoq_charge_order_regrade(r.order_id, 'run_stop_read_as_charge_end',
           '0630: the run''s stop ended a charge the check modelled under way; it was graded as a charge that ended');
    n := n + 1;
  END LOOP;
  RAISE NOTICE '0630: % grades superseded (% ms)', n, round(extract(epoch FROM clock_timestamp() - v_t) * 1000);
END $regrade$;

-- ══ V3: each supersession is exactly the defect corrected ════════════════════════════════════════════════════════════════
DO $v3$
DECLARE v_bad text; v_code text := public.ottoq_hindsight_code_md5(); v_n_view int; v_n_ledger int; v_dup int;
BEGIN
  SELECT string_agg(a.order_id::text, ', ' ORDER BY a.order_id) INTO v_bad
    FROM _0630_affected a
    LEFT JOIN public.ottoq_charge_order_regrades r ON r.order_id = a.order_id
    LEFT JOIN public.ottoq_charge_order_grades g ON g.order_id = a.order_id
   WHERE r.order_id IS NULL
      OR r.realized IS DISTINCT FROM a.want
      OR r.code_md5 IS DISTINCT FROM v_code
      OR r.supersedes_code_md5 IS DISTINCT FROM a.code_md5
      OR r.graded_at IS DISTINCT FROM a.graded_at
      OR r.defect IS DISTINCT FROM 'run_stop_read_as_charge_end'
      OR (SELECT jsonb_agg(c ORDER BY c) FROM jsonb_array_elements_text(r.detail -> 'chargers') c)
         IS DISTINCT FROM (SELECT jsonb_agg(c ->> 'id' ORDER BY c ->> 'id') FROM jsonb_array_elements(a.chargers) c)
      OR to_jsonb(g) IS DISTINCT FROM (to_jsonb(r) - ARRAY['regraded_at', 'supersedes_code_md5', 'defect', 'detail']);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0630 V3: these regrades are not the first grade with exactly the interrupted chargers censored, '
                    'by the grader now, standing: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_charge_order_regrades r WHERE NOT EXISTS
               (SELECT 1 FROM _0630_affected a WHERE a.order_id = r.order_id)) THEN
    RAISE EXCEPTION '0630 V3: a regrade of an order the stop did not touch';
  END IF;
  SELECT count(*), count(*) - count(DISTINCT order_id) INTO v_n_view, v_dup FROM public.ottoq_charge_order_grades;
  SELECT count(*) INTO v_n_ledger FROM public.ottoq_charge_order_hindsight;
  IF v_n_view <> v_n_ledger OR v_dup <> 0 OR EXISTS (
       SELECT 1 FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_grades g USING (order_id)
        WHERE NOT EXISTS (SELECT 1 FROM _0630_affected a WHERE a.order_id = h.order_id)
          AND to_jsonb(g) IS DISTINCT FROM to_jsonb(h)) THEN
    RAISE EXCEPTION '0630 V3: the standing grades are not one per graded order, the first grade for every order this '
                    'did not touch (% standing, % graded, % twice)', v_n_view, v_n_ledger, v_dup;
  END IF;
  RAISE NOTICE '0630 V3: % regrades, each its first grade with exactly the chargers the stop interrupted censored; % '
               'standing grades, one per graded order', (SELECT count(*) FROM public.ottoq_charge_order_regrades), v_n_view;
END $v3$;

-- ══ V4: only the grader names the ledger, to write it ═════════════════════════════════════════════════════════════════════
DO $v4$
DECLARE v_names text; v_grade text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_names
    FROM pg_proc p
   WHERE p.oid <> 'public.ottoq_charge_order_grade(bigint,numeric)'::regprocedure
     AND p.prosrc LIKE '%ottoq_charge_order_hindsight%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
         ~ 'ottoq_charge_order_hindsight(?![a-z_0-9])';
  v_grade := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_charge_order_grade(bigint,numeric)'::regprocedure),
                                           '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF v_names IS NOT NULL
     OR (SELECT count(*) FROM regexp_matches(v_grade, 'ottoq_charge_order_hindsight(?![a-z_0-9])', 'g')) <> 1
     OR strpos(v_grade, 'INSERT INTO ottoq_charge_order_hindsight') = 0 THEN
    RAISE EXCEPTION '0630 V4: the ledger is named outside the grader''s one write: %', COALESCE(v_names, 'the grade');
  END IF;
END $v4$;

-- ══ V5: the running block before and after; every outcome the regrades changed ═══════════════════════════════════════════
DO $v5$
DECLARE b record; a record; v_out text;
BEGIN
  SELECT * INTO b FROM _0630_running_before;
  SELECT sum((g.forecast #>> '{running,n}')::numeric) AS n, sum((g.forecast #>> '{running,sum_err}')::numeric) AS sum_err,
         sum((g.forecast #>> '{running,sum_abs_err}')::numeric) AS sum_abs_err
    INTO a
    FROM public.ottoq_charge_order_grades g
   WHERE g.depot_id = '11111111-1111-1111-1111-111111111111' AND g.graded_at >= now() - interval '7 days';
  SELECT string_agg(t.k || ' ' || t.n, ', ' ORDER BY t.n DESC, t.k) INTO v_out
    FROM (SELECT (r.detail #>> '{outcome,was}') || ' -> ' || (r.detail #>> '{outcome,now}') AS k, count(*) AS n
            FROM public.ottoq_charge_order_regrades r
           WHERE r.detail #>> '{outcome,was}' IS DISTINCT FROM r.detail #>> '{outcome,now}'
           GROUP BY 1) t;
  RAISE NOTICE '0630 V5: the charges under way at an order, twin depot, last 7 days: before % uncensored, mean error % '
               'min, MAE % min; after % uncensored, mean error % min, MAE % min. Outcomes changed: %',
    b.n, round(b.sum_err / NULLIF(b.n, 0), 2), round(b.sum_abs_err / NULLIF(b.n, 0), 2),
    a.n, round(a.sum_err / NULLIF(a.n, 0), 2), round(a.sum_abs_err / NULLIF(a.n, 0), 2), COALESCE(v_out, 'none');
END $v5$;

-- ══ V6: the readers run on the standing grades ════════════════════════════════════════════════════════════════════════════
DO $v6$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_run uuid; v_tr jsonb; v_u jsonb;
        v_n int; v_t timestamptz := clock_timestamp();
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_charge_order_grades
   WHERE depot_id = c_twin AND graded_at >= now() - interval '7 days';
  IF v_n = 0 THEN
    RAISE NOTICE '0630 V6: nothing graded at the twin depot in 7 days: the readers have nothing to read here';
    RETURN;
  END IF;
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  IF COALESCE((v ->> 'graded')::int, -1) <> v_n THEN
    RAISE EXCEPTION '0630 V6: the self-review read % graded orders, the standing grades are %', v ->> 'graded', v_n;
  END IF;
  SELECT sim_run_id INTO v_run FROM public.ottoq_charge_order_grades WHERE depot_id = c_twin
   ORDER BY graded_at DESC, order_id DESC LIMIT 1;
  v_tr := public.ottoq_charge_order_track_record(v_run, c_twin, 7);
  v_u := public.ottoq_agent_charge_order_usage(v_run, 5);
  IF v_tr IS NULL OR v_u IS NULL THEN
    RAISE EXCEPTION '0630 V6: the track record or the usage read nothing on run %', v_run;
  END IF;
  RAISE NOTICE '0630 V6: the self-review read % standing grades in % ms; its first area: %', v_n,
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT (x.value ->> 'title') || ' :: ' || left(x.value ->> 'finding', 220)
                FROM jsonb_array_elements(v -> 'improvement_areas') x ORDER BY (x.value ->> 'rank')::int LIMIT 1), 'none');
END $v6$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0630_the_grader_reads_a_runs_stop_as_the_stop', false, false,
  'ottoq_charge_order_realized reads a charge the run''s stop ended (sim_reset) as still under way at the cut; the '
  'grade is computed by ottoq_charge_order_grade_compute, kept first by ottoq_charge_order_grade and beside a wrong '
  'first grade by ottoq_charge_order_regrade in ottoq_charge_order_regrades (append-only evidence); every reader reads '
  'ottoq_charge_order_grades, the standing grade; the grades the stop had misread are regraded. FALSE/FALSE: the grader '
  'and its readers write and read evidence only; no kernel decision, dial or seat reads a grade (the agent reads its '
  'track record as a proposer), and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
