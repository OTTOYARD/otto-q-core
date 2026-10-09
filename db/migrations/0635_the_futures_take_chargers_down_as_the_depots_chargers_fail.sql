-- migration-version: 20261009103141
-- migration-name:    the_futures_take_chargers_down_as_the_depots_chargers_fail
--
-- 0635  **The futures take chargers down as the depot's chargers fail.**
--       The kernel's check on an agent's charge order rolls the charge line forward in sampled futures, and no future
--       ever took a charger down: a fault inside the window was a surprise to every one of them, and a charger down at
--       the order never came back. The depot's chargers fail often enough to matter: about one fast charge in ten and one
--       L2 charge in twelve ends in a fault, and a faulted charger is usually down for the rest of the window. 0635 learns
--       each kind of charger's fault rate per minute of charging and its repair curve every night, and the futures draw
--       from both: a charge faults at its kind's rate, its car rejoins the line owing the rest (rule 9), the charger is
--       down for a drawn repair, and a charger down at the order comes back after what is left of its repair.
--
-- ══ §1 WHY (measured 2026-10-09 07:10-07:40 UTC, 2:10-2:40 AM CT) ═══════════════════════════════════════════════════════
--
--   (a) The self-review ranks it: "Charger faults it never sampled moved its verdicts", 13.7% of what made the check
--       wrong, 3 of 21 attributed orders moved (11.8% once 0631 gives a fault the whole of the charge it cut). And "It
--       never adds back a charger whose hold ends": the chargers it left out at the order served 1.18 charges a window.
--   (b) The rate. The charge ledger (evidence) records why each charge ended: in the 21 days to now, 2,444 of 29,148
--       charges at the twin depot ended in a fault (connector cable 559, communication dropout 450, thermal emergency
--       251, ...). On fine-tick runs, 179 fast charges faulted over 92,188 charging minutes (0.00194 a minute, 0.116 an
--       hour) and 210 L2 charges over 298,577 (0.00070, 0.042). Run to run the rate moves no more than chance does on a
--       run's exposure (fast p10-p90 0.065-0.174 an hour over 26 runs of 10 hours or more).
--   (c) Out of sample. Fit through b2efcc07's start: its 32.9 fast-charging hours expected 3.8 faults and saw 4; its
--       114.2 L2 hours expected 4.9 and saw 3 (P(3 or fewer) 0.28).
--   (d) The repair, from the fault events (87 fast and 100 L2 in the fit's population): median 30 and 57 minutes, p90
--       175 and 350, never under 10, the longest 626 and 714. A charger that faults inside a 90-minute window is
--       usually down for the rest of it. At the twin depot's 10 fast and 30 L2 chargers, mostly busy, a 90-minute
--       window carries about 1.7 + 1.9 = 3.6 faults.
--   (e) A charger down at the order is left out of the state (0620) and never comes back. When it went down is known
--       (ottoq_ocpp_chargers.station_state_changed_at, on the run's own clock), and how long repairs last is learned, so
--       what is left of its repair is the repair curve given it has lasted so long. The twin's planned repair (its fault
--       event's repair_minutes) is never read at the order: a real charger's repair is not known when it faults, and a
--       path that works only because this is a simulation breaks the swap test.
--   (f) Rule 9: a car whose charger faulted is re-queued to finish. The simulator already does that for a down window
--       (0621): the charge on it stops and its car rejoins the line owing the rest. A charge under way at the order that
--       a drawn fault cuts rejoins the line the same way, owing the rest on the kind it was on.
--   (g) Rule 10 names it: production learns overnight "which chargers fault". A learned estimate, refitted nightly, never
--       a rule or a setting; the draws are the check's, and the check only says yes or no to an agent's order.
--   (h) Rehearsed on live 2026-10-09 07:40-07:55 UTC (read-only, on temporary copies of these functions): the fit reads
--       0.1165 faults an hour of fast charging and 0.0422 of L2 in 1.6 s. Rolled again with them, the 32 contested orders
--       at the twin depot (12 futures each, the depot's chargers as each order saw them) won 244 futures and lost 117,
--       against 229 and 121 without; the majority moved on 2 of 32; each sampled future drew a mean 13.7 faults over
--       its 480-minute horizon (the futures roll the whole line forward, not only the window) and put 0.4 cars a future
--       back in line from a charge under way; a rollout took a mean 990 ms against 844. One run's orders: a reading,
--       not a range.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_charge_fault_fits (append-only evidence, a depot's, no run column: it outlives every purge);
--       public.ottoq_charge_fault_params(depot, through, window): per kind, the hazard of a fault per minute of charging
--       (the ledger's charges a fault ended, over its charging minutes) and the repair curve (quantiles at 0, 0.05, ...,
--       1 of the minutes the fault events record), fine-tick runs when they hold 30 faults of the kind; usable from 30
--       faults and 30 repairs. public.ottoq_fit_charge_fault_model writes a fit; public.ottoq_charge_fault_model reads the
--       latest. `ottoq-learn-charge-faults-nightly` refits it at 11:24 UTC (6:24 AM CT), after the other nightly fits.
--   (b) public.ottoq_fault_draw_minutes(hazard, u) and public.ottoq_fault_repair_draw(curve, u, down): the minutes of
--       charging to a fault, and the repair still to go for a charger down so long. Pure.
--   (c) ottoq_charge_line_state: with the run's new dial agent_charge_order_faults at 1 (its default) and a usable fault
--       fit, the state carries `faults`: each usable kind's hazard and repair curve, and `down`, each charger of a usable
--       kind down at the order with the minutes it has been down on the run's own clock, or, when it went down before the
--       run began (its stamp is another run's clock), the minutes since the run began, which it has been down at least
--       (`lb`). The chargers list is untouched, so nothing else reads a down charger as free. With the dial at 0 or no
--       usable fit, 0634's state exactly.
--   (d) ottoq_charge_line_schedule: with `faults`, a charger down at the order comes back after the rest of its repair
--       (in the expected future at the curve's conditional median, in a sampled future at its own draw); and in a sampled
--       future each charge the line seats, and each charge under way at the order, faults at its kind's hazard: the
--       charger goes down at the fault for a drawn repair, and its car rejoins the line owing the rest. The expected
--       future draws no fault (it is the median world, and the grader's replays run it). Totals add faults_drawn and
--       requeued. Without `faults`, 0634's result key for key.
--   (e) ottoq_charge_line_realize: with the faults part, the faults that happened replace the state's (real down windows
--       and real returns from repair), so the state's `faults` is dropped from that replay.
--   (f) The self-review: orders made without faults in their futures, graded once the depot has a usable fault fit,
--       are history for the faults part (built); orders that carried them say what is left.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 the four bodies are the ones 0634 left, the objects are new. V1 the draws by
--   arithmetic; each patch by meaning. V2 the simulator unchanged without `faults`: the latest stored states, both sides,
--   the expected future and a sampled one, key for key against the body as it stood. V3 the fit, and out of sample on the
--   latest run with 20 graded orders: its faults against what the fit through its first order expected. V4 the state
--   and a rollout with faults on a stored contested order. V5 the self-review. Executed by
--   tests/test_agent_charger_faults_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0620-0634: the state and the simulator are read by the check
--   on an agent's charge order, the agent's board and the grader; no kernel decision, dial or seat reads them, and no
--   certification arm runs the agent or the charge order (0615). The dial is new, a person's, and defaults to 1.
--
-- ROLLBACK: set agent_charge_order_faults to 0 on the runs that should not see it (0634's state, exactly), or EXECUTE each
--   `definition` in ottoq_schema_snapshots WHERE label = '0635_pre' AND object_kind = 'function'; then
--   SELECT cron.unschedule('ottoq-learn-charge-faults-nightly'); the fits stay (evidence); DROP FUNCTION
--   public.ottoq_fault_draw_minutes(float8, float8), public.ottoq_fault_repair_draw(float8[], float8, float8),
--   public.ottoq_charge_fault_params(uuid, timestamptz, interval), public.ottoq_fit_charge_fault_model(uuid, timestamptz,
--   interval, text) and public.ottoq_charge_fault_model(uuid); DELETE FROM public.ottoq_policy_param_catalog WHERE
--   param_key = 'agent_charge_order_faults'; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0635_the_futures_take_chargers_down_as_the_depots_chargers_fail'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0635 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0635 P0: a run is running; its check reads the state and the simulator this changes. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones 0634 left; the objects are new ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)',                  'aaeb42d6882d8eb4983016884f097577'),
    ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)',                  '63a335d1575fe91c102ae3cc870266d5'),
    ('public.ottoq_charge_line_realize(jsonb,jsonb,text[])',                                 'a96b3801e265dfa83a4ad0f704fc4e51'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',       '774c9e1ad6cee829b516cc46f51a90a1'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0635 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regclass('public.ottoq_charge_fault_fits') IS NOT NULL
     OR to_regprocedure('public.ottoq_fault_repair_draw(double precision[],double precision,double precision)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_faults')
     OR EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-learn-charge-faults-nightly')
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0635_the_futures_take_chargers_down_as_the_depots_chargers_fail') THEN
    RAISE EXCEPTION '0635 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0635_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- what V2 compares against: the simulator as it stood, on the latest stored states, both sides, futures 0 and 3
CREATE TEMP TABLE _0635_pre ON COMMIT DROP AS
SELECT s.order_id, x.k, x.side,
       public.ottoq_charge_line_schedule(s.state, CASE WHEN x.side = 'agent' THEN s.agent_order END, x.k, s.seed, true) AS out
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots WHERE depot_id = '11111111-1111-1111-1111-111111111111'
         ORDER BY order_id DESC LIMIT 8) s
  CROSS JOIN (VALUES (0, 'kernel'), (0, 'agent'), (3, 'kernel'), (3, 'agent')) x(k, side);

-- ══ (c) the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_faults', 0, 1, 1, false,
  'ottoq_charge_line_state, ottoq_charge_line_schedule (0635 the charger faults)',
  '0635: whether the kernel''s check on an agent''s charge order draws charger faults in its futures at the rate and '
  'repair the depot''s own chargers show (ottoq_charge_fault_model), and brings a charger down at the order back after '
  'what is left of its repair. 1 draws them; 0 is 0634''s check exactly. A person''s dial, never the agent''s (rule 10).');

-- ══ (a) the fits ══════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_fault_fits (
  fit_id           bigserial PRIMARY KEY,
  depot_id         uuid NOT NULL,
  model            text NOT NULL CHECK (model = 'charge_fault_v1'),
  fitted_at        timestamptz NOT NULL DEFAULT now(),
  --: the real-clock window of evidence read (the ledger's recorded_at), not a sim clock
  evidence_from    timestamptz,
  evidence_through timestamptz,
  n_evidence       integer NOT NULL,
  n_runs           integer NOT NULL,
  --: a kind of charger has a usable rate and repair curve
  usable           boolean NOT NULL,
  --: ottoq_charge_fault_params: by_kind {h, faults, charge_min, repairs, rq, usable, population}
  params           jsonb NOT NULL,
  code_md5         text NOT NULL,
  fitted_by        text NOT NULL DEFAULT current_user,
  note             text
);

COMMENT ON TABLE public.ottoq_charge_fault_fits IS
'0635. One row per fit of a depot''s charger faults, charge_fault_v1: per kind of charger, the hazard of a fault per minute of charging (the charge ledger''s charges a fault ended over its charging minutes) and the repair curve (quantiles of the minutes its fault events record). Written by ottoq_fit_charge_fault_model (at apply and nightly at 11:24 UTC), read through ottoq_charge_fault_model by the charge line''s state, whose futures draw faults from it. An estimate, never a rule or a setting (CLAUDE.md rule 10). Append-only (override: ottoq.learned_estimates_unlock=on). No run column: it belongs to the depot and outlives every purge.';

CREATE INDEX ottoq_charge_fault_fits_latest_idx ON public.ottoq_charge_fault_fits (depot_id, fit_id DESC);

CREATE FUNCTION public.ottoq_charge_fault_fits_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.learned_estimates_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_charge_fault_fits is append-only: % refused. A new fit is a new row. Set ottoq.learned_estimates_unlock=on in '
    'the session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_charge_fault_fits_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_fault_fits
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_fault_fits_append_only();

ALTER TABLE public.ottoq_charge_fault_fits ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_fault_fits_read ON public.ottoq_charge_fault_fits FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_fault_fits FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_fault_fits TO anon, authenticated;

CREATE FUNCTION public.ottoq_charge_fault_params(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                 p_window interval DEFAULT '21 days')
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  /* 0635: charge_fault_v1's parameters for a depot from the evidence in (through - window, through] (real clock), read-only.
     Per kind of charger (dcfc, l2): h, the hazard of a fault per minute of charging: the charge ledger's charges a fault
     ended (stopped_reason 'fault.%') over every charge's minutes; and rq, the repair curve: the quantiles at 0, 0.05, ...,
     1 of the minutes the faults' events record (charge.session_faulted's repair_minutes, joined to the ledger by session).
     As every part of the learned models, the runs at ticks of a minute or less when they hold 30 faults of the kind,
     else every run. A kind is usable from 30 faults and 30 repairs. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_by      jsonb;
  v_n       int;
  v_runs    int;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_charge_fault_params: a depot is required'; END IF;
  WITH l AS (
    SELECT l.session_id, l.sim_run_id, l.charger_type AS k, l.duration_min::float8 AS m,
           COALESCE(l.stopped_reason, '') LIKE 'fault.%' AS f, COALESCE(l.tick_minutes <= 1, false) AS fine
      FROM public.ottoq_charge_duration_ledger l
     WHERE l.depot_id = p_depot AND l.recorded_at > v_from AND l.recorded_at <= v_through
       AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0
  ), pop AS (
    SELECT l.k, count(*) FILTER (WHERE l.f AND l.fine) >= c_min_n AS use_fine FROM l GROUP BY l.k
  ), u AS (
    SELECT l.* FROM l JOIN pop ON pop.k = l.k WHERE l.fine OR NOT pop.use_fine
  ), rep AS (
    SELECT u.k, (e.payload ->> 'repair_minutes')::float8 AS r
      FROM u
      JOIN public.ottoq_events e ON e.entity_id = u.session_id AND e.event_type = 'charge.session_faulted'
     WHERE u.f AND e.occurred_at <= v_through AND (e.payload ->> 'repair_minutes') ~ '^[0-9]+(\.[0-9]+)?$'
  ), kk AS (
    SELECT u.k, count(*) FILTER (WHERE u.f) AS faults, sum(u.m) AS mins, count(DISTINCT u.sim_run_id) AS runs,
           (SELECT pop.use_fine FROM pop WHERE pop.k = u.k) AS fine,
           (SELECT count(*) FROM rep WHERE rep.k = u.k) AS repairs
      FROM u GROUP BY u.k
  )
  SELECT COALESCE(jsonb_object_agg(kk.k, jsonb_build_object(
           'h', round((kk.faults / NULLIF(kk.mins, 0))::numeric, 7), 'faults', kk.faults,
           'charge_min', round(kk.mins::numeric, 1), 'runs', kk.runs, 'repairs', kk.repairs,
           'population', CASE WHEN kk.fine THEN 'fine_ticks' ELSE 'all_ticks' END,
           'rq', CASE WHEN kk.repairs > 0 THEN (
                   SELECT jsonb_agg(round(q.v::numeric, 2) ORDER BY q.u)
                     FROM (SELECT gs.u, (SELECT percentile_cont(gs.u) WITHIN GROUP (ORDER BY rep.r) FROM rep WHERE rep.k = kk.k) AS v
                             FROM (SELECT generate_series(0, 20) / 20.0 AS u) gs) q) END,
           'usable', kk.faults >= c_min_n AND kk.repairs >= c_min_n AND kk.mins > 0)), '{}'::jsonb),
         COALESCE(sum(kk.faults), 0)::int,
         (SELECT count(DISTINCT u.sim_run_id) FROM u)::int
    INTO v_by, v_n, v_runs FROM kk;
  RETURN jsonb_build_object('by_kind', v_by, 'n_faults', v_n, 'n_runs', v_runs, 'min_n', c_min_n,
                            'from', 'the charge ledger (charging minutes and the charges a fault ended) and the fault events (repair)');
END
$fn$;

CREATE FUNCTION public.ottoq_fit_charge_fault_model(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                    p_window interval DEFAULT '21 days', p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  /* 0635: fit charge_fault_v1 for a depot and write one row: ottoq_charge_fault_params; usable when a kind is. */
DECLARE
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_id      bigint;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_fit_charge_fault_model: a depot is required'; END IF;
  v_p := public.ottoq_charge_fault_params(p_depot, v_through, COALESCE(p_window, interval '21 days'));
  INSERT INTO public.ottoq_charge_fault_fits
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'charge_fault_v1', v_from, v_through, COALESCE((v_p ->> 'n_faults')::int, 0),
          COALESCE((v_p ->> 'n_runs')::int, 0),
          EXISTS (SELECT 1 FROM jsonb_each(COALESCE(v_p -> 'by_kind', '{}'::jsonb)) k WHERE (k.value ->> 'usable')::boolean),
          v_p,
          md5(pg_get_functiondef('public.ottoq_fit_charge_fault_model(uuid,timestamptz,interval,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_fault_params(uuid,timestamptz,interval)'::regprocedure)),
          p_note)
  RETURNING fit_id INTO v_id;
  RETURN v_id;
END
$fn$;

CREATE FUNCTION public.ottoq_charge_fault_model(p_depot uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0635: the latest fit of a depot's charger faults, or NULL when there is none
  SELECT jsonb_build_object('fit_id', f.fit_id, 'model', f.model, 'fitted_at', f.fitted_at, 'usable', f.usable,
                            'n_evidence', f.n_evidence, 'n_runs', f.n_runs, 'params', f.params)
    FROM public.ottoq_charge_fault_fits f
   WHERE f.depot_id = p_depot
   ORDER BY f.fit_id DESC
   LIMIT 1
$fn$;

-- ══ (b) the draws ═════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_fault_draw_minutes(p_h double precision, p_u double precision)
RETURNS double precision
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0635: the minutes of charging to a fault at hazard p_h a minute, at probability p_u: -ln(1 - u) / h. Never, with no
  -- hazard. Pure.
  SELECT CASE WHEN p_h IS NULL OR p_h <= 0 OR p_u IS NULL THEN 'Infinity'::float8
              ELSE -ln(1 - LEAST(GREATEST(p_u, 0), 0.999999)) / p_h END
$fn$;

CREATE FUNCTION public.ottoq_fault_repair_draw(p_q double precision[], p_u double precision,
                                               p_down double precision DEFAULT 0)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
  /* 0635: the minutes of repair still to go for a charger down p_down minutes, at probability p_u of what is left, on
     the repair curve p_q (its quantiles at 0, 0.05, ..., 1, piecewise linear between them). The curve's share at or
     below p_down is F (a repair as short as p_down would be over); the repair is the curve's quantile at F + (1 - F) u,
     less p_down, and at least half a minute. A charger down as long as the curve's longest is given the curve's median
     again. NULL with no curve. Pure. */
DECLARE
  n int := COALESCE(cardinality(p_q), 0);
  a float8 := GREATEST(COALESCE(p_down, 0), 0);
  u float8 := LEAST(GREATEST(COALESCE(p_u, 0.5), 0), 1);
  f float8 := 0; v float8; x float8; k int; i int;
BEGIN
  IF n < 2 OR p_q[1] IS NULL OR p_q[n] IS NULL THEN
    RETURN NULL;
  END IF;
  IF a >= p_q[n] THEN
    x := 0.5 * (n - 1);
    k := floor(x)::int;
    RETURN GREATEST(p_q[k + 1] + (x - k) * (p_q[LEAST(k + 2, n)] - p_q[k + 1]), 0.5);
  END IF;
  IF a >= p_q[1] THEN
    FOR i IN 1 .. n - 1 LOOP
      IF p_q[i + 1] > a THEN
        f := ((i - 1) + CASE WHEN p_q[i + 1] > p_q[i] THEN (a - p_q[i]) / (p_q[i + 1] - p_q[i]) ELSE 0 END) / (n - 1);
        EXIT;
      END IF;
    END LOOP;
  END IF;
  x := (f + (1 - f) * u) * (n - 1);
  k := LEAST(floor(x)::int, n - 1);
  v := CASE WHEN k >= n - 1 THEN p_q[n] ELSE p_q[k + 1] + (x - k) * (p_q[k + 2] - p_q[k + 1]) END;
  RETURN GREATEST(v - a, 0.5);
END
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_fault_draw_minutes(double precision, double precision) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_fault_repair_draw(double precision[], double precision, double precision)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_fault_model(uuid) TO anon, authenticated, service_role;

-- ══ (c) (d) (e) (f) the anchored patches: each anchor once, the stored definition after ══════════════════════════════════
CREATE TEMP TABLE _0635_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0635_patch VALUES
-- (c) the state
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 1,
$old$   state exactly. */$old$,
$new$   state exactly.
   0635: with the run's agent_charge_order_faults dial at 1 (its default) and a usable fault fit
   (ottoq_charge_fault_model), the state carries `faults`: each usable kind's hazard of a fault per minute of charging
   (h) and its repair curve (rq), and `down`, each charger of a usable kind down at the order with the minutes it has
   been down on the run's own clock (a), or, when it went down before the run began, the minutes since the run began,
   which it has been down at least (lb true). The chargers list is untouched. With the dial at 0 or no usable fit,
   0634's state exactly. */$new$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 2,
$old$  v_bycls boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_drain_by_class', 1), 1) >= 1;   -- 0628$old$,
$new$  v_bycls boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_drain_by_class', 1), 1) >= 1;   -- 0628
  v_fm jsonb; v_r0 timestamptz;                                                                     -- 0635$new$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 3,
$old$  RETURN v_state;$old$,
$new$  -- 0635: the depot's charger faults, and the chargers down at the order, unless a person has turned it off for this run
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_faults', 1), 1) >= 1 THEN
    v_fm := public.ottoq_charge_fault_model(p_depot_id);
    IF COALESCE((v_fm ->> 'usable')::boolean, false) THEN
      SELECT r.sim_clock_start INTO v_r0 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
      v_state := v_state || jsonb_build_object('faults',
        jsonb_build_object('v', 1, 'model', v_fm -> 'fit_id')
        || COALESCE((SELECT jsonb_object_agg(k.key, jsonb_build_object('h', k.value -> 'h', 'rq', k.value -> 'rq'))
                       FROM jsonb_each(COALESCE(v_fm #> '{params,by_kind}', '{}'::jsonb)) k
                      WHERE COALESCE((k.value ->> 'usable')::boolean, false)), '{}'::jsonb)
        || jsonb_build_object('down', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'id', s.id, 'k', s.stall_type::text,
                      'a', round((extract(epoch FROM (p_clock - CASE WHEN c.station_state_changed_at BETWEEN v_r0 AND p_clock
                                                                     THEN c.station_state_changed_at ELSE v_r0 END)) / 60.0)::numeric, 2),
                      'lb', NOT COALESCE(c.station_state_changed_at BETWEEN v_r0 AND p_clock, false))
                    ORDER BY s.stall_type, s.id)
               FROM stalls s
               JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
              WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2') AND c.station_state = 'Faulted'
                AND COALESCE((v_fm #>> ARRAY['params', 'by_kind', s.stall_type::text, 'usable'])::boolean, false)), '[]'::jsonb)));
    END IF;
  END IF;
  RETURN v_state;$new$),
-- (d) the simulator
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 1,
$old$   down to its rung at its own drain and spread. Without them, 0627's result, key for key. */$old$,
$new$   down to its rung at its own drain and spread. Without them, 0627's result, key for key.
   0635: with a `faults` block (ottoq_charge_line_state, the run's agent_charge_order_faults dial at 1), each charger down
   at the order (`down`) comes back after the rest of its repair (ottoq_fault_repair_draw on its kind's curve, given the
   minutes it has been down: the conditional median in the expected future, its own draw in a sampled one). And in a
   sampled future each charge the line seats, and each charge under way at the order, faults at its kind's hazard per
   minute of charging (ottoq_fault_draw_minutes; keyed by the charger and its count of seats, so both sides of a
   comparison meet the same faults): the charger goes down at the fault for a drawn repair, and its car rejoins the line
   owing the rest (0621's down window; a car under way rejoins as a car owing the rest on the kind it was on, rule 9).
   The expected future draws no fault. Totals add faults_drawn and requeued. Without the block, 0634's result, key for
   key. */$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 2,
$old$  r_lam float8 := 0; r_to float8 := 0; r_dr float8 := 0; v_te float8; v_e0 float8; v_owe float8;$old$,
$new$  r_lam float8 := 0; r_to float8 := 0; r_dr float8 := 0; v_te float8; v_e0 float8; v_owe float8;
  -- 0635: the charger faults
  f_on boolean := COALESCE(jsonb_typeof(p_state -> 'faults') = 'object', false);
  f_hd float8 := 0; f_hl float8 := 0; f_qd float8[]; f_ql float8[]; f_n int := 0; f_rq int := 0;
  s_n int[] := '{}'; v_tf float8; v_rp float8;$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 3,
$old$  FOR v_inbound IN SELECT unnest(ARRAY[false, true]) LOOP$old$,
$new$  IF f_on THEN                                                                                     -- 0635
    f_hd := GREATEST(COALESCE((p_state #>> '{faults,dcfc,h}')::float8, 0), 0);
    f_hl := GREATEST(COALESCE((p_state #>> '{faults,l2,h}')::float8, 0), 0);
    SELECT array_agg((x.value #>> '{}')::float8 ORDER BY x.o) INTO f_qd
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{faults,dcfc,rq}') = 'array'
                                     THEN p_state #> '{faults,dcfc,rq}' ELSE '[]'::jsonb END) WITH ORDINALITY x(value, o);
    SELECT array_agg((x.value #>> '{}')::float8 ORDER BY x.o) INTO f_ql
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{faults,l2,rq}') = 'array'
                                     THEN p_state #> '{faults,l2,rq}' ELSE '[]'::jsonb END) WITH ORDINALITY x(value, o);
    -- a kind with a rate and no repair curve cannot say how long its charger is down: it draws no fault
    IF f_qd IS NULL OR cardinality(f_qd) < 2 THEN f_hd := 0; END IF;
    IF f_ql IS NULL OR cardinality(f_ql) < 2 THEN f_hl := 0; END IF;
  END IF;
  FOR v_inbound IN SELECT unnest(ARRAY[false, true]) LOOP$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 4,
$old$    -- 0623: the car charging on it leaves when its charge ends
$old$,
$new$    s_n[m] := 0;                                                                                   -- 0635
    -- 0635: in a sampled future the charge under way faults at its kind's hazard: the charger goes down at the fault
    -- for a drawn repair, and its car rejoins the line owing the rest on the kind it was on; it leaves once charged
    IF f_on AND COALESCE(p_scenario, 0) > 0 AND s_free[m] > 0 THEN
      v_tf := public.ottoq_fault_draw_minutes(CASE s_k[m] WHEN 'dcfc' THEN f_hd ELSE f_hl END,
                public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':fault:0'));
      IF v_tf < s_free[m] AND v_tf <= v_hor THEN
        v_rp := COALESCE(public.ottoq_fault_repair_draw(CASE s_k[m] WHEN 'dcfc' THEN f_qd ELSE f_ql END,
                  public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':repair:0'), 0), 0);
        nd := nd + 1; d_j[nd] := m; d_a[nd] := v_tf; d_b[nd] := v_tf + v_rp; d_done[nd] := false;
        f_n := f_n + 1;
        IF (e ->> 'car') IS NOT NULL THEN
          n := n + 1;
          c_id[n] := e ->> 'car'; c_idr[n] := COALESCE((o_idr ->> c_id[n])::int, 0);
          c_w0[n] := 0; c_g[n] := 10; c_imm[n] := false; c_soc[n] := 50; c_due[n] := NULL;
          c_dok[n] := (s_k[m] = 'dcfc'); c_lok[n] := (s_k[m] = 'l2');
          c_md[n] := s_free[m] - v_tf; c_ml[n] := s_free[m] - v_tf;
          c_av[n] := v_tf; c_gate[n] := v_tf; c_inb[n] := false;
          c_rank[n] := NULL; c_okind[n] := NULL;
          c_vk[n] := 0; c_void[n] := false; c_ret[n] := NULL; c_dep[n] := NULL;
          n_live := n_live + 1;
          f_rq := f_rq + 1;
        END IF;
        s_free[m] := v_tf;
        CONTINUE;
      END IF;
    END IF;
    -- 0623: the car charging on it leaves when its charge ends
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 5,
$old$  -- 0623: the cars charged and still parked leave from now, on what is left of their dwell$old$,
$new$  -- 0635: each charger down at the order comes back after the rest of its repair, on its kind's curve given how long it
  -- has been down: the conditional median in the expected future, its own draw in a sampled one
  IF f_on THEN
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state #> '{faults,down}', '[]'::jsonb)) WITH ORDINALITY x(value, o)
              ORDER BY x.o
    LOOP
      CONTINUE WHEN (e ->> 'id') IS NULL OR (e ->> 'k') NOT IN ('dcfc', 'l2');
      CONTINUE WHEN (CASE e ->> 'k' WHEN 'dcfc' THEN f_qd ELSE f_ql END) IS NULL;
      m := m + 1;
      s_id[m] := e ->> 'id'; s_k[m] := e ->> 'k'; s_car[m] := NULL; s_n[m] := 0;
      s_free[m] := public.ottoq_fault_repair_draw(CASE s_k[m] WHEN 'dcfc' THEN f_qd ELSE f_ql END,
                     CASE WHEN COALESCE(p_scenario, 0) > 0
                          THEN public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':back')
                          ELSE 0.5 END,
                     COALESCE((e ->> 'a')::float8, 0));
    END LOOP;
  END IF;

  -- 0623: the cars charged and still parked leave from now, on what is left of their dwell$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 6,
$old$      s_car[best] := i;                                                     -- 0621$old$,
$new$      s_car[best] := i;                                                     -- 0621
      -- 0635: in a sampled future this charge faults at its kind's hazard: the charger goes down at the fault for a drawn
      -- repair, and the car rejoins the line owing the rest (0621's down window)
      IF f_on AND COALESCE(p_scenario, 0) > 0 THEN
        s_n[best] := COALESCE(s_n[best], 0) + 1;
        v_tf := public.ottoq_fault_draw_minutes(CASE s_k[best] WHEN 'dcfc' THEN f_hd ELSE f_hl END,
                  public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[best] || ':fault:' || s_n[best]));
        IF v_tf < v_dur AND t + v_tf <= v_hor THEN
          v_rp := COALESCE(public.ottoq_fault_repair_draw(CASE s_k[best] WHEN 'dcfc' THEN f_qd ELSE f_ql END,
                    public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[best] || ':repair:' || s_n[best]), 0), 0);
          nd := nd + 1; d_j[nd] := best; d_a[nd] := t + v_tf; d_b[nd] := t + v_tf + v_rp; d_done[nd] := false;
          f_n := f_n + 1;
        END IF;
      END IF;$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 7,
$old$      FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i)
     WHERE z.i > n0;$old$,
$new$      FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i)
     WHERE z.i > n0 AND c_vk[z.i] > 0;                                                             -- 0635: returns only$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 8,
$old$  IF COALESCE(p_trace, false) THEN
    v_out := v_out || jsonb_build_object('seats', COALESCE(($old$,
$new$  IF f_on THEN                                                                                     -- 0635
    v_out := v_out || jsonb_build_object('faults_drawn', f_n, 'requeued', f_rq);
  END IF;
  IF COALESCE(p_trace, false) THEN
    v_out := v_out || jsonb_build_object('seats', COALESCE(($new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 9,
$old$          FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i) WHERE z.i > n0 AND NOT c_void[z.i]), '[]'::jsonb));$old$,
$new$          FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i) WHERE z.i > n0 AND NOT c_void[z.i] AND c_vk[z.i] > 0), '[]'::jsonb));$new$),
-- (e) the realizer
('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', 1,
$old$   (every one before 0631) replays as before. */$old$,
$new$   (every one before 0631) replays as before.
   0635: with faults, the faults that happened replace the state's own (its `faults`: the rates the futures draw from
   and the chargers down at the order), so the replay drops them. */$new$),
('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', 2,
$old$    RETURN p_state || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch, 'outflow', v_out);$old$,
$new$    RETURN CASE WHEN v_f THEN p_state - 'faults' ELSE p_state END                                -- 0635
           || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch, 'outflow', v_out);$new$),
('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', 3,
$old$  RETURN p_state || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);$old$,
$new$  RETURN CASE WHEN v_f THEN p_state - 'faults' ELSE p_state END                                  -- 0635
         || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);$new$),
-- (f) the self-review
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 1,
$old$  v_arr_built boolean := false;                                                                    -- 0627$old$,
$new$  v_arr_built boolean := false;                                                                    -- 0627
  v_flt_built boolean := false; v_flt_carried boolean := false;                                     -- 0635
  c_flt_note constant text := ' These orders were made before the futures took chargers down as the depot''s chargers '
                              'fail, so this is history until new orders are graded.';
  c_flt_act constant text := 'Grade the next armed run''s orders: the futures now draw charger faults at the depot''s own '
                             'rate and bring each charger back after its repair.';$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 2,
$old$  -- (7) when cars came home, chargers that faulted, how long charges took: the part alone, where nothing above names it$old$,
$new$  -- 0635: orders whose futures drew no fault, graded once the depot has a usable fault fit, are history for the faults
  -- part; orders that carried the faults say what is left
  v_flt_carried := EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades h
                             JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
                            WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                              AND jsonb_typeof(s.state -> 'faults') = 'object');
  v_flt_built := NOT v_flt_carried
                 AND COALESCE((public.ottoq_charge_fault_model(p_depot_id) ->> 'usable')::boolean, false);
  -- (7) when cars came home, chargers that faulted, how long charges took: the part alone, where nothing above names it$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 3,
$old$                     WHEN x.part = 'arrivals' AND v_arr_built THEN 'built' ELSE 'open' END;           -- 0627$old$,
$new$                     WHEN x.part = 'arrivals' AND v_arr_built THEN 'built'
                     WHEN x.part = 'faults' AND v_flt_built THEN 'built' ELSE 'open' END;           -- 0627, 0635$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 7,
$old$                           WHEN 'faults' THEN 'Charger faults it never sampled moved its verdicts'$old$,
$new$                           WHEN 'faults' THEN CASE WHEN v_flt_carried THEN 'Charger faults moved its verdicts'   -- 0635
                                                   ELSE 'Charger faults it never sampled moved its verdicts' END$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 4,
$old$                      WHEN 'faults' THEN 'Its futures never take a charger down: a fault inside the window is a surprise to every one of them.'$old$,
$new$                      WHEN 'faults' THEN CASE WHEN v_flt_carried                                          -- 0635
                                              THEN 'Its futures take chargers down at the depot''s own rate; what is left is which charger and when.'
                                              ELSE 'Its futures never take a charger down: a fault inside the window is a surprise to every one of them.' END$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 5,
$old$                 || CASE WHEN v_status = 'built' THEN CASE WHEN x.part = 'arrivals' THEN c_arr_note ELSE v_note END$old$,
$new$                 || CASE WHEN v_status = 'built' THEN CASE WHEN x.part = 'arrivals' THEN c_arr_note
                                                          WHEN x.part = 'faults' THEN c_flt_note ELSE v_note END   -- 0635$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 6,
$old$                  WHEN 'faults' THEN 'Sample charger faults in the futures at the depot''s own fault rate and repair time.'$old$,
$new$                  WHEN 'faults' THEN CASE WHEN v_status = 'built' THEN c_flt_act                           -- 0635
                                          WHEN v_flt_carried THEN 'More futures sample this better; nothing to rebuild.'
                                          ELSE 'Sample charger faults in the futures at the depot''s own fault rate and repair time.' END$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0635_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0635_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0635 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0635 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the draws by arithmetic; each patch by meaning ═════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  c_q constant float8[] := ARRAY[10, 10, 10, 10, 13, 16.5, 19, 22.1, 25.8, 28, 30, 38.2, 48.2, 65.2, 81, 98.5, 118.4,
                                 150.8, 175.4, 238.7, 626];
  v_def text;
BEGIN
  -- the hazard: half the draws fault within ln 2 / h minutes; no hazard, never
  IF abs(public.ottoq_fault_draw_minutes(0.002, 0.5) - ln(2) / 0.002) > 1e-9
     OR public.ottoq_fault_draw_minutes(0, 0.5) <> 'Infinity'::float8 THEN
    RAISE EXCEPTION '0635 V1: the fault draw reads % at h 0.002', public.ottoq_fault_draw_minutes(0.002, 0.5);
  END IF;
  -- the repair: a fresh fault at u 0.5 is the curve's median (30); down 30 minutes, its median is what is left of the
  -- curve's upper half (the quantile at 0.75, 98.5, less 30); down exactly the shortest repair (10, the curve's lowest
  -- 15%), what is left above it (the quantile at 0.575, 43.2, less 10); down longer than the longest, the median again;
  -- no curve, NULL
  IF abs(public.ottoq_fault_repair_draw(c_q, 0.5, 0) - 30) > 1e-9
     OR abs(public.ottoq_fault_repair_draw(c_q, 0.5, 30) - (98.5 - 30)) > 1e-9
     OR abs(public.ottoq_fault_repair_draw(c_q, 0.5, 10) - (43.2 - 10)) > 1e-9
     OR abs(public.ottoq_fault_repair_draw(c_q, 0.5, 700) - 30) > 1e-9
     OR public.ottoq_fault_repair_draw(NULL, 0.5, 0) IS NOT NULL
     OR abs(public.ottoq_fault_repair_draw(c_q, 0, 0) - 10) > 1e-9
     OR abs(public.ottoq_fault_repair_draw(c_q, 1, 0) - 626) > 1e-9 THEN
    RAISE EXCEPTION '0635 V1: the repair draw reads % fresh, % after 30 minutes, % past the longest',
      public.ottoq_fault_repair_draw(c_q, 0.5, 0), public.ottoq_fault_repair_draw(c_q, 0.5, 30),
      public.ottoq_fault_repair_draw(c_q, 0.5, 700);
  END IF;
  v_def := pg_get_functiondef('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure);
  IF strpos(v_def, ':fault:'' || s_n[best]') = 0 OR strpos(v_def, '#> ''{faults,down}''') = 0
     OR strpos(v_def, 'WHERE z.i > n0 AND c_vk[z.i] > 0;') = 0 THEN
    RAISE EXCEPTION '0635 V1: the simulator does not draw faults as meant';
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure),
            '''agent_charge_order_faults'', 1), 1) >= 1') = 0
     OR strpos(pg_get_functiondef('public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure),
               'CASE WHEN v_f THEN p_state - ''faults'' ELSE p_state END') = 0 THEN
    RAISE EXCEPTION '0635 V1: the state or the realizer is not as meant';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_faults'
                    AND default_value = 1 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0635 V1: the dial is not catalogued as a person''s, default 1';
  END IF;
  RAISE NOTICE '0635 V1: a fault at h 0.002 comes at a median % minutes of charging; a repair on the depot''s fast curve % fresh, % more after 30 minutes down, % past its longest; the simulator, the state, the realizer and the dial as meant',
    round(public.ottoq_fault_draw_minutes(0.002, 0.5)::numeric, 1), public.ottoq_fault_repair_draw(c_q, 0.5, 0),
    public.ottoq_fault_repair_draw(c_q, 0.5, 30), public.ottoq_fault_repair_draw(c_q, 0.5, 700);
END $v1$;

-- ══ V2: without `faults`, the simulator is 0634's, key for key ════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_n int; v_diff int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE public.ottoq_charge_line_schedule(s.state, CASE WHEN p.side = 'agent' THEN s.agent_order END,
                                                                            p.k, s.seed, true) IS DISTINCT FROM p.out)
    INTO v_n, v_diff
    FROM _0635_pre p JOIN public.ottoq_charge_order_snapshots s ON s.order_id = p.order_id;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0635 V2: % of % stored simulations changed without a faults block', v_diff, v_n;
  END IF;
  RAISE NOTICE '0635 V2: % stored simulations (% states x both sides x futures 0 and 3) unchanged', v_n, v_n / 4;
END $v2$;

-- ══ V3: the fit, and out of sample on the latest run with 20 graded orders ══════════════════════════════════════════════
DO $v3$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  v_id bigint; v_m jsonb; v_t timestamptz := clock_timestamp(); g record; v_p jsonb; r record; v_out text := '';
BEGIN
  v_id := public.ottoq_fit_charge_fault_model(c_twin, now(), interval '21 days', '0635: the first fit of the depot''s charger faults');
  v_m := public.ottoq_charge_fault_model(c_twin);
  IF (v_m ->> 'fit_id')::bigint IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION '0635 V3: the depot''s fault model is not the fit %', v_id;
  END IF;
  RAISE NOTICE '0635 V3: charge_fault_v1 fit % in % s, usable %: %', v_id,
    round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1), v_m ->> 'usable',
    COALESCE((SELECT string_agg(k.key || ' ' || round((k.value ->> 'h')::numeric * 60, 4) || ' an hour of charging ('
                                || (k.value ->> 'faults') || ' faults, ' || (k.value ->> 'repairs') || ' repairs, median '
                                || (k.value -> 'rq' ->> 10) || ' minutes, p90 ' || (k.value -> 'rq' ->> 18) || ')', '; ' ORDER BY k.key)
                FROM jsonb_each(COALESCE(v_m #> '{params,by_kind}', '{}'::jsonb)) k), 'none');
  SELECT x.run, x.through INTO g
    FROM (SELECT s.sim_run_id AS run, min(s.recorded_at) AS through
            FROM public.ottoq_charge_order_grades h
            JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
           WHERE h.depot_id = c_twin
           GROUP BY s.sim_run_id
          HAVING count(DISTINCT s.order_id) >= 20
           ORDER BY max(s.recorded_at) DESC LIMIT 1) x;
  IF g.run IS NULL THEN
    RAISE NOTICE '0635 V3: no run has 20 graded orders; the out-of-sample reading is executed by the tests';
    RETURN;
  END IF;
  v_p := public.ottoq_charge_fault_params(c_twin, g.through, interval '21 days');
  FOR r IN
    SELECT l.charger_type AS k, count(*) FILTER (WHERE COALESCE(l.stopped_reason, '') LIKE 'fault.%') AS faults,
           sum(l.duration_min) AS mins
      FROM public.ottoq_charge_duration_ledger l
     WHERE l.sim_run_id = g.run AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0
     GROUP BY 1 ORDER BY 1
  LOOP
    v_out := v_out || format('%s: %s charging hours expected %s faults, %s came; ', r.k, round(r.mins / 60.0, 1),
                             round((r.mins * COALESCE((v_p #>> ARRAY['by_kind', r.k, 'h'])::numeric, 0))::numeric, 1), r.faults);
  END LOOP;
  RAISE NOTICE '0635 V3: out of sample on run % (the fit through its first order): %', left(g.run::text, 8),
    COALESCE(NULLIF(v_out, ''), 'no charges recorded');
END $v3$;

-- ══ V4: the state, and a rollout with faults on a stored contested order ═══════════════════════════════════════════════
DO $v4$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  s record; v_st jsonb; v_with jsonb; v_without jsonb; v_fm jsonb; v_t timestamptz;
BEGIN
  v_fm := public.ottoq_charge_fault_model(c_twin);
  IF NOT COALESCE((v_fm ->> 'usable')::boolean, false) THEN
    RAISE NOTICE '0635 V4: no usable fault fit; the state and the rollout are executed by the tests';
    RETURN;
  END IF;
  SELECT sn.* INTO s FROM public.ottoq_charge_order_snapshots sn
   WHERE sn.depot_id = c_twin AND jsonb_typeof(sn.agent_order) = 'object' AND sn.agent_order <> '{}'::jsonb
   ORDER BY sn.order_id DESC LIMIT 1;
  IF s.order_id IS NULL THEN
    RAISE NOTICE '0635 V4: no stored order with an agent''s order to roll';
    RETURN;
  END IF;
  -- the stored state with the depot's faults as the state would now carry them (none down: the order's chargers were
  -- read then)
  v_st := s.state || jsonb_build_object('faults', jsonb_build_object('v', 1, 'model', v_fm -> 'fit_id', 'down', '[]'::jsonb)
            || COALESCE((SELECT jsonb_object_agg(k.key, jsonb_build_object('h', k.value -> 'h', 'rq', k.value -> 'rq'))
                           FROM jsonb_each(v_fm #> '{params,by_kind}') k WHERE (k.value ->> 'usable')::boolean), '{}'::jsonb));
  v_t := clock_timestamp();
  v_without := public.ottoq_charge_line_rollout(s.state, s.agent_order, 12, s.seed);
  v_with := public.ottoq_charge_line_rollout(v_st, s.agent_order, 12, s.seed);
  RAISE NOTICE '0635 V4: order % (% s for both rollouts): without faults % won, % tied, % lost of %; with them % won, % tied, % lost (faults drawn in its 3rd future: kernel %, agent %)',
    s.order_id, round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 2),
    v_without ->> 'wins', v_without ->> 'ties', v_without ->> 'losses', v_without ->> 'futures',
    v_with ->> 'wins', v_with ->> 'ties', v_with ->> 'losses',
    public.ottoq_charge_line_schedule(v_st, NULL, 3, s.seed, false) ->> 'faults_drawn',
    public.ottoq_charge_line_schedule(v_st, s.agent_order, 3, s.seed, false) ->> 'faults_drawn';
END $v4$;

-- ══ V5: the self-review reads it ═══════════════════════════════════════════════════════════════════════════════════════════
DO $v5$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  RAISE NOTICE '0635 V5: the self-review in % ms; its faults areas: %', round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT string_agg((x.value ->> 'status') || ' ' || (x.value ->> 'area') || ': ' || left(x.value ->> 'finding', 160), ' | ')
                FROM jsonb_array_elements(v -> 'improvement_areas') x WHERE x.value ->> 'part' = 'faults'), 'none');
END $v5$;

SELECT cron.schedule('ottoq-learn-charge-faults-nightly', '24 11 * * *',
  $cron$SELECT public.ottoq_fit_charge_fault_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days', 'nightly');$cron$);

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0635_the_futures_take_chargers_down_as_the_depots_chargers_fail', false, false,
  'charge_fault_v1 learns each kind of charger''s fault hazard per minute of charging and its repair curve nightly '
  '(ottoq_charge_fault_fits, ottoq-learn-charge-faults-nightly); the charge line''s state carries them and the chargers '
  'down at the order behind the person''s dial agent_charge_order_faults (1; 0 is 0634''s check); the simulator brings '
  'a down charger back after its repair and, in a sampled future, faults charges at the depot''s rate with the car '
  're-queued to finish (rule 9); the realizer replays real faults in their place; the self-review marks older orders as '
  'history. FALSE/FALSE as 0620-0634: read by the check on an agent''s charge order, the agent''s board and the grader; no '
  'kernel decision, dial or seat reads them, and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
