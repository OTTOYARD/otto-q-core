-- migration-version: 20261017185512
-- migration-name:    a_promise_stays_honest_while_the_car_waits
--
-- 0742  **A promise stays honest while the car waits.** OTTO-Q's ready-by estimate was right at arrival and wrong
--       afterwards: asked again about a car whose charge was done and that was still waiting, it said "ready now" for
--       nearly every one. It now estimates a car from where it is, drawn given how long it has already waited, and says it
--       does not know when a car has waited longer than any its history holds. Under a dial, the twin re-estimates every
--       promised car every 30 sim-minutes, with what the owner app says at that moment, so tonight's two promise arms
--       grade the estimate an owner would get on looking again, not only at arrival. Research wing, rule 10: it measures.
--
-- ══ §1 WHY (G455) ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Rehearsed on last night's records with the estimator's own allowance (Kaplan-Meier with its lower bounds, the prior
--   until a kind has 8 cars), for every car whose charge was done and that was still waiting at each whole hour of the
--   run. 0739's estimator calls such a car 'no_charge': a visit that never charged, measured from arrival with that
--   allowance, and the time since arrival is subtracted from each draw and floored at zero. So a car past the allowance's
--   short no-charge times draws zeros, and its promise is "ready now":
--     arm 82 (busy day, 10 posts)   239 of 247 car-hours "ready now"; the cars waited a median 35 more minutes;
--                                   ready by the promise's median 0.000, by its 90th percentile 0.004;
--     arm 81 (busy day, 20 posts)   1,692 of 1,710; a median 165 more minutes; 0.000 and 0.002;
--     arm 83 (normal day, 10 posts) 50 of 56; a median 18 more minutes; 0.036 and 0.089.
--   Drawn instead from the after-charge allowance, given the minutes since the charge closed, on the three normal-day
--   arms (83, 86, 84) where the wait so far is under the allowance's median: ready by the median 0.644, 0.682 and 0.657,
--   by the 90th percentile 0.889, 0.932 and 0.862; above its median 0.556, 0.381 and 0.344, and 0.889, 0.850 and 0.724.
--   On arm 83 the median's mean absolute error fell from 25.1 to 14.7 minutes; on the busy days it rose (57.1 to 138.9 and
--   233.1 to 253.4), because the cars there that did get ready were the few that got a bay, and the median now speaks for
--   the many that did not. The busy days stay poor (by the 90th
--   percentile 0.398 on arm 82 and 0.229 on arm 81): there the two service bays face about 3.6 times the work they can do
--   (G453), most waiting cars had lost their bay slot, and no history of finished cars can see a queue that does not
--   empty. A car's own bay booking as a floor lifted arm 82's 90th percentile only to 0.421 (96 of its 247 car-hours had
--   one) and cost the normal day's median 10 minutes of error, so it is not built. A wait longer than any the allowance
--   holds: 0 car-hours on the normal days, 5 and 34 on the busy days. That estimate is now "unknown", not "ready now".
--   Why it matters now: G454 proposes that the owner app say the promise. An owner who looked again an hour after arrival
--   would have been told "ready now" by 0739's estimator in 97-99% of the hours their car was waiting after its charge.
--   Tonight's promise arms grade arrivals only; this file makes them grade the second look too.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_ready_promise, eight anchored patches. Two situations:
--         - 'ready': the readiness check has passed, so 0 minutes;
--         - 'after_charge': the charge is done and the car is still waiting. It draws from the after-charge allowance, by
--           whether bay work remains, given the minutes since the charge closed, or since its last bay work if that came
--           after.
--       'no_charge' and 'unplanned' keep their allowances measured from arrival, now drawn given the minutes since arrival.
--       The draw is the allowance above the share of it the car has already waited. A car that has waited at least as long
--       as any its allowance holds gets no estimate (NULL), flagged beyond_history. Where the wait so far is no longer than
--       the allowance's shortest (every arrival in practice), the draws are exactly 0739's.
--   (b) twin.ottoq_sim_record_ready_promises, three patches:
--         - a promise is made only with a time;
--         - under dial ready_promise_refresh_min (0..240, default 0), each promised car's newest open visit is
--           re-estimated every that many sim-minutes while it is open, with the owner app's time beside it, into the new
--           ledger;
--         - that block runs first, in its own exception block.
--   (c) public.ottoq_ready_promise_updates: the evidence ledger of re-estimates. Append-only, no foreign key to runs, row
--       security on, registered as evidence. The server may read and insert and nothing else: the project's default
--       privileges give service_role every right on a new table, TRUNCATE among them, and a TRUNCATE fires no row trigger,
--       so all of them are revoked and only SELECT and INSERT given back (0736's ledger carries the defaults; G456).
--   (d) public.ottoq_ready_promise_update_grade(run): each re-estimate against the readiness check, censored as 0736's
--       grade is. It reads by situation and by time since arrival, with the owner app's time graded beside it.
--   (e) ottoq_ready_promises' situation check admits 'after_charge' and 'ready' (no row holds either; a first promise made
--       after arrival could).
--   (f) The two promise cells queued for tonight, dcfc10.otto_q.answer_in_tick.promise (promise_normal_2026_10_17) and
--       dcfc10.otto_q.promise (promise_busy_2026_10_17), carry ready_promise_refresh_min 30. Neither has run.
--   Not changed: the tick, the arrival grade, the owner app.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the estimator is 0739's (prosrc md5 bc718022) and the recorder 0741's (a5cd09d4); the dial,
--   the ledger and the update grade are absent; both promise cells exist and neither has an arm. P2: not already applied.
--   Pre-image to ottoq_schema_snapshots as '0742_pre'. Each anchor matches once. V1: each patched body less its patches is
--   its pre-image. V2: nothing for a run that does not exist (the estimator, the recorder, both grades). V3: the grants,
--   the ledger's included: service_role may read and insert it and not update it (refused by V3 on the first apply, which
--   rolled back whole, because the project's default privileges had given service_role every right on the new table).
--   V4: the dial is catalogued 0..240 default 0 and not agent-writable; both cells carry it and otherwise the parameters
--   they had; the ledger is registered as evidence; the arrival ledger's situation check admits the seven situations.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. The estimator's only caller is the recorder, which runs only under
--   0736's dial ready_promise_record (default 0); no certification arm, canon cell or dial experiment sets it; the grades
--   are read-only.
--
-- ROLLBACK (before tonight's arms run): EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0742_pre' (both
--   functions); DROP FUNCTION public.ottoq_ready_promise_update_grade(uuid); remove ready_promise_refresh_min from the two
--   cells' fixed_params and DELETE its catalog row; restore the five-situation check. Once an arm has written to
--   ottoq_ready_promise_updates the ledger is evidence and stays.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0742_a_promise_stays_honest_while_the_car_waits'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0742 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, nothing of this file, tonight's two cells unrun ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'))
     IS DISTINCT FROM 'bc718022c00bd26ae3072f463dcd6ead' THEN
    RAISE EXCEPTION '0742 P1: public.ottoq_ready_promise is not 0739''s body (md5 bc718022)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'a5cd09d49ae31a6adebc875b7a329cfd' THEN
    RAISE EXCEPTION '0742 P1: twin.ottoq_sim_record_ready_promises is not 0741''s body (md5 a5cd09d4)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'ready_promise_refresh_min')
     OR to_regclass('public.ottoq_ready_promise_updates') IS NOT NULL
     OR to_regprocedure('public.ottoq_ready_promise_update_grade(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0742 P1: the dial, the ledger or the update grade already exists';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE (s.sweep_code, c.cell_code) IN (('promise_normal_2026_10_17', 'dcfc10.otto_q.answer_in_tick.promise'),
                                             ('promise_busy_2026_10_17', 'dcfc10.otto_q.promise'))
         AND c.fixed_params ->> 'ready_promise_record' = '1') <> 2 THEN
    RAISE EXCEPTION '0742 P1: tonight''s two promise cells are not as read';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code IN ('promise_normal_2026_10_17', 'promise_busy_2026_10_17')) THEN
    RAISE EXCEPTION '0742 P1: a promise arm has already run; its cell is evidence and is not changed';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0742_a_promise_stays_honest_while_the_car_waits') THEN
    RAISE EXCEPTION '0742 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0742_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
                 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure);

-- ── (e) the arrival ledger admits the two situations a car can be in after arrival ──
ALTER TABLE public.ottoq_ready_promises DROP CONSTRAINT ottoq_ready_promises_situation_check;
ALTER TABLE public.ottoq_ready_promises ADD CONSTRAINT ottoq_ready_promises_situation_check
  CHECK (situation IN ('in_line', 'charging', 'holds_charger', 'unplanned', 'no_charge', 'after_charge', 'ready'));

-- ── (c) the ledger of re-estimates ──
CREATE TABLE public.ottoq_ready_promise_updates (
  update_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sim_run_id         uuid        NOT NULL,
  depot_id           uuid        NOT NULL,
  visit_id           uuid        NOT NULL,
  vehicle_id         uuid        NOT NULL,
  estimated_at       timestamptz NOT NULL,          -- the run's clock when the car was estimated again
  arrived_at         timestamptz,
  situation          text        NOT NULL CHECK (situation IN ('in_line', 'charging', 'holds_charger', 'unplanned',
                                                               'no_charge', 'after_charge', 'ready')),
  bundle             text        NOT NULL CHECK (bundle IN ('bay', 'no_bay')),
  elapsed_min        numeric,                       -- minutes since arrival
  ready_p50_min      numeric,                       -- NULL: the car has waited past its history, no estimate
  ready_p90_min      numeric,
  ready_p50_at       timestamptz,
  ready_p90_at       timestamptz,
  owner_read         boolean     NOT NULL DEFAULT false,
  owner_ready_by_sim timestamptz,                   -- what the owner app said at that moment (0741, G454)
  detail             jsonb       NOT NULL DEFAULT '{}'::jsonb,
  recorded_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_ready_promise_updates_once UNIQUE (sim_run_id, visit_id, estimated_at),
  CONSTRAINT ottoq_ready_promise_updates_ordered
    CHECK (ready_p50_min IS NULL OR (ready_p90_min >= ready_p50_min AND ready_p50_min >= 0))
);
COMMENT ON TABLE public.ottoq_ready_promise_updates IS
  '0742 (G455): OTTO-Q''s ready-by estimate for a promised visit, made again every ready_promise_refresh_min sim-minutes '
  'while it is open (what an owner who looked again would be told), with what the owner app said at that moment. '
  'Written by twin.ottoq_sim_record_ready_promises, graded by public.ottoq_ready_promise_update_grade. Evidence: '
  'append-only, and deliberately no foreign key to ottoq_sim_runs.';
CREATE INDEX ottoq_ready_promise_updates_run_idx ON public.ottoq_ready_promise_updates (sim_run_id, visit_id, estimated_at);

CREATE OR REPLACE FUNCTION public.ottoq_ready_promise_updates_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.ready_promise_updates_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_ready_promise_updates is append-only: % refused. Set ottoq.ready_promise_updates_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END
$fn$;

CREATE TRIGGER ottoq_ready_promise_updates_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_ready_promise_updates
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_ready_promise_updates_append_only();

ALTER TABLE public.ottoq_ready_promise_updates ENABLE ROW LEVEL SECURITY;
-- service_role too: the project's default privileges give it every right on a new table, TRUNCATE among them, and a
-- TRUNCATE fires no row trigger, so an append-only ledger keeps only what it is given back
REVOKE ALL ON TABLE public.ottoq_ready_promise_updates FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON TABLE public.ottoq_ready_promise_updates TO service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_ready_promise_updates', 'sim_run_id', 'evidence',
        '0742 (G455): each promised visit estimated again while it waited, graded against when it was ready. Evidence, '
        'not engine, as ottoq_ready_promises (0736) is: it is worth grading only if it survives the next demo run''s purge. '
        'Carries NO foreign key to ottoq_sim_runs, deliberately.');

-- ── the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('ready_promise_refresh_min',
        '0742 (G455): under ready_promise_record, the twin estimates each promised car''s open visit again every this '
        'many sim-minutes while it waits, as an owner who looked again would be told, and records it beside what the owner '
        'app said then (ottoq_ready_promise_updates). 0 = never (the twin before 0742). Decides nothing: research days only.',
        0, 0, 240, 'twin.ottoq_sim_record_ready_promises', false);

-- ── (a) and (b): the estimator and the recorder ──
CREATE TEMP TABLE _0742_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0742_patch VALUES
-- (1) the estimator holds what the car has already waited
(1, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$  v_dr    int; v_gi int; v_lb int; v_pq float8; v_gq float8[];
$old$,
$new$  v_dr    int; v_gi int; v_lb int; v_pq float8; v_gq float8[];
  v_fe    float8; v_u2 float8; v_qq float8[]; v_chg_end timestamptz;   -- 0742 (G455): drawn given what it has waited
$new$),
-- (2) and reads what the car has already done
(2, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$           EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE a ->> 'concurrency' = 'bay' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')) AS bay,
$old$,
$new$           EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE a ->> 'concurrency' = 'bay' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')) AS bay,
           -- 0742 (G455): what the car has already done, so a visit part-way through is estimated from where it is
           (SELECT max(COALESCE((a ->> 'closed_at')::timestamptz, (a ->> 'done_at')::timestamptz))
              FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
             WHERE a ->> 'svc' = 'charge' AND a ->> 'status' = 'done') AS chg_at,
           (SELECT max((a ->> 'done_at')::timestamptz) FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
             WHERE a ->> 'concurrency' = 'bay' AND a ->> 'status' = 'done') AS bay_done_at,
           (SELECT min((a ->> 'done_at')::timestamptz) FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
             WHERE a ->> 'svc' = 'readiness_check' AND a ->> 'status' = 'done') AS ready_at,
$new$),
-- (3) a car already ready, and one whose charge is done, are where they are
(3, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$    v_r := NULL; v_r0 := NULL; v_sit := NULL; v_key := NULL; v_beyond := 0; v_st_id := NULL;
    IF NOT c.chg THEN
      v_sit := 'no_charge';
$old$,
$new$    v_r := NULL; v_r0 := NULL; v_sit := NULL; v_key := NULL; v_beyond := 0; v_st_id := NULL;
    v_fe := 0; v_chg_end := NULL;
    -- 0742 (G455): a car whose readiness check has passed is ready, and a car whose charge is done is waiting for what
    -- follows it. Before 0742 both were 'no_charge', measured from arrival with the allowance of visits that never charged.
    IF c.ready_at IS NOT NULL AND c.ready_at <= p_clock THEN
      v_sit := 'ready';
    ELSIF NOT c.chg AND c.chg_at IS NOT NULL THEN
      v_sit := 'after_charge';
      v_chg_end := CASE WHEN NOT c.bay AND c.bay_done_at > c.chg_at THEN c.bay_done_at ELSE c.chg_at END;
    ELSIF NOT c.chg THEN
      v_sit := 'no_charge';
$new$),
-- (4) a car waiting after its charge is timed from it
(4, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$    v_akey := CASE WHEN v_sit IN ('in_line', 'charging', 'holds_charger') THEN 'after_'
                   WHEN c.chg THEN 'door_chg_' ELSE 'door_nochg_' END
              || CASE WHEN c.bay THEN 'bay' ELSE 'no_bay' END;
    v_el := CASE WHEN v_akey LIKE 'door_%' AND c.arrived_at IS NOT NULL
                 THEN GREATEST(extract(epoch FROM (p_clock - c.arrived_at)) / 60.0, 0) ELSE 0 END;
$old$,
$new$    v_akey := CASE WHEN v_sit IN ('in_line', 'charging', 'holds_charger', 'after_charge', 'ready') THEN 'after_'
                   WHEN c.chg THEN 'door_chg_' ELSE 'door_nochg_' END
              || CASE WHEN c.bay THEN 'bay' ELSE 'no_bay' END;
    v_el := CASE WHEN v_sit = 'after_charge' THEN GREATEST(extract(epoch FROM (p_clock - v_chg_end)) / 60.0, 0)
                 WHEN v_akey LIKE 'door_%' AND c.arrived_at IS NOT NULL
                 THEN GREATEST(extract(epoch FROM (p_clock - c.arrived_at)) / 60.0, 0) ELSE 0 END;
$new$),
-- (5) where on its allowance the car's wait so far falls
(5, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$    v_q := CASE WHEN v_al IS NOT NULL
                THEN ARRAY(SELECT (x.v #>> '{}')::float8 FROM jsonb_array_elements(v_al -> 'q') WITH ORDINALITY AS x(v, o) ORDER BY x.o) END;
$old$,
$new$    v_q := CASE WHEN v_al IS NOT NULL
                THEN ARRAY(SELECT (x.v #>> '{}')::float8 FROM jsonb_array_elements(v_al -> 'q') WITH ORDINALITY AS x(v, o) ORDER BY x.o) END;
    -- 0742 (G455): a car that has already waited v_el minutes is drawn from what follows given that it has waited that
    -- long (its allowance above v_el, from the share v_fe of it already passed), not from all of it less v_el, which put
    -- most of a long wait's draws at zero. A wait at least as long as any its allowance holds (v_fe 1) has no estimate
    -- from it, and the promise says so. A wait no longer than the allowance's shortest (v_fe 0) draws as before.
    IF v_el > 0 THEN
      v_qq := COALESCE(v_q, ARRAY(SELECT (c_prior -> v_akey ->> 0)::float8
                                         * exp(ln((c_prior -> v_akey ->> 1)::float8 / (c_prior -> v_akey ->> 0)::float8) / 1.2816
                                               * c_z[i])
                                    FROM generate_series(1, 21) i ORDER BY i));
      IF v_el >= v_qq[21] THEN
        v_fe := 1;
      ELSIF v_el > v_qq[1] THEN
        FOR v_gi IN REVERSE 20 .. 1 LOOP
          IF v_qq[v_gi] <= v_el AND v_el < v_qq[v_gi + 1] THEN
            v_fe := (v_gi - 1) / 20.0 + (v_el - v_qq[v_gi]) / (v_qq[v_gi + 1] - v_qq[v_gi]) / 20.0;
            EXIT;
          END IF;
        END LOOP;
      END IF;
    END IF;
$new$),
-- (6) and draws from above it
(6, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$      FOR v_dr IN 1 .. c_draws LOOP                      -- 0739 (G452): each charge future carries 8 draws of the rest
        IF v_q IS NOT NULL THEN
$old$,
$new$      FOR v_dr IN 1 .. c_draws LOOP                      -- 0739 (G452): each charge future carries 8 draws of the rest
        CONTINUE WHEN v_sit = 'ready' OR v_fe >= 1;       -- 0742: nothing to draw for a car ready, or past its history
        IF v_fe > 0 THEN                                   -- 0742 (G455): drawn from above what it has already waited
          v_u := public.ottoq_hash_uniform(v_seed || ':' || s || ':' || v_dr || ':' || c.vehicle_id::text || ':after');
          v_u2 := v_fe + v_u * (1 - v_fe);
          v_i := LEAST(floor(v_u2 * 20)::int, 19);
          v_f := v_u2 * 20 - v_i;
          v_a := v_qq[v_i + 1] + (v_qq[v_i + 2] - v_qq[v_i + 1]) * v_f;
        ELSIF v_q IS NOT NULL THEN
$new$),
-- (7) a car already ready is ready now
(7, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x), percentile_cont(0.9) WITHIN GROUP (ORDER BY x)
      INTO v_p50, v_p90 FROM unnest(v_rd) x;
$old$,
$new$    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x), percentile_cont(0.9) WITHIN GROUP (ORDER BY x)
      INTO v_p50, v_p90 FROM unnest(v_rd) x;
    IF v_sit = 'ready' THEN                                -- 0742: ready now
      v_p50 := 0; v_p90 := 0;
    END IF;
$new$),
-- (8) and the detail says where the car was on its allowance
(8, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$                         'elapsed_min', round(v_el::numeric, 2), 'beyond_horizon', NULLIF(v_beyond, 0),
$old$,
$new$                         'elapsed_min', round(v_el::numeric, 2), 'beyond_horizon', NULLIF(v_beyond, 0),
                         'waited_share', CASE WHEN v_fe > 0 THEN round(v_fe::numeric, 3) END,
                         'beyond_history', CASE WHEN v_fe >= 1 THEN true END, 'ready_at', c.ready_at,
$new$),
-- (9) the recorder holds the re-estimates
(9, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$DECLARE v_depot uuid; v_ids uuid[]; v_n int := 0; v_owner jsonb;
$old$,
$new$DECLARE v_depot uuid; v_ids uuid[]; v_n int := 0; v_owner jsonb;
  v_refresh numeric; v_upd uuid[]; v_owner2 jsonb;   -- 0742 (G455): the re-estimates
$new$),
-- (10) re-estimates each promised car while it waits, before any new car is promised
(10, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$  -- 0739 (G452): each car's newest open visit, in the estimator's own order, so a car with an older open visit beside a
$old$,
$new$  -- 0742 (G455): under the dial ready_promise_refresh_min, each car promised here is estimated again every that many
  -- minutes while its visit is open, as an owner who looks again would be told, and recorded with what the owner app says
  -- then. Its own block: a failure is a WARNING, and the promises below are still made.
  v_refresh := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'ready_promise_refresh_min', 0), 0);
  IF v_refresh > 0 THEN
    BEGIN
      SELECT array_agg(z.vehicle_id ORDER BY z.vehicle_id) INTO v_upd
        FROM (SELECT DISTINCT ON (vn.vehicle_id) vn.vehicle_id, vn.visit_id
                FROM public.ottoq_visit_needs vn
               WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = v_depot AND vn.status IN ('open', 'in_progress')
               ORDER BY vn.vehicle_id, vn.arrived_at DESC NULLS LAST, vn.created_at DESC, vn.visit_id DESC) z
        JOIN public.ottoq_ready_promises p ON p.sim_run_id = p_sim_run_id AND p.visit_id = z.visit_id
       WHERE GREATEST(p.promised_at, COALESCE((SELECT max(u.estimated_at) FROM public.ottoq_ready_promise_updates u
                                                WHERE u.sim_run_id = p_sim_run_id AND u.visit_id = z.visit_id), p.promised_at))
             <= p_sim_clock_now - make_interval(secs => (v_refresh * 60)::double precision);
      IF v_upd IS NOT NULL THEN
        BEGIN
          SELECT jsonb_object_agg(v.id::text, public.ottoq_owner_car(v, p_sim_run_id, 100) -> 'ready_by_sim')
            INTO v_owner2
            FROM public.vehicles v WHERE v.id = ANY (v_upd);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING '0742 owner ready-by: % %', SQLSTATE, SQLERRM;
          v_owner2 := NULL;
        END;
        INSERT INTO public.ottoq_ready_promise_updates
               (sim_run_id, depot_id, visit_id, vehicle_id, estimated_at, arrived_at, situation, bundle, elapsed_min,
                ready_p50_min, ready_p90_min, ready_p50_at, ready_p90_at, owner_read, owner_ready_by_sim, detail)
        SELECT p_sim_run_id, v_depot, rp.visit_id, rp.vehicle_id, p_sim_clock_now, vn.arrived_at, rp.situation, rp.bundle,
               round((extract(epoch FROM (p_sim_clock_now - vn.arrived_at)) / 60.0)::numeric, 2),
               rp.ready_p50_min, rp.ready_p90_min,
               p_sim_clock_now + make_interval(secs => rp.ready_p50_min * 60),
               p_sim_clock_now + make_interval(secs => rp.ready_p90_min * 60),
               v_owner2 IS NOT NULL, (v_owner2 ->> rp.vehicle_id::text)::timestamptz, rp.detail
          FROM public.ottoq_ready_promise(p_sim_run_id, v_depot, p_sim_clock_now, v_upd, 16) rp
          JOIN public.ottoq_visit_needs vn ON vn.visit_id = rp.visit_id
          JOIN public.ottoq_ready_promises p ON p.sim_run_id = p_sim_run_id AND p.visit_id = rp.visit_id
        ON CONFLICT (sim_run_id, visit_id, estimated_at) DO NOTHING;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0742 ready promise refresh: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  -- 0739 (G452): each car's newest open visit, in the estimator's own order, so a car with an older open visit beside a
$new$),
-- (11) and makes a promise only with a time
(11, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$    ON CONFLICT (sim_run_id, visit_id) DO NOTHING;
$old$,
$new$       AND rp.ready_p50_min IS NOT NULL                  -- 0742: a car past its history has no time to promise yet
    ON CONFLICT (sim_run_id, visit_id) DO NOTHING;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0742_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0742: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0742: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its patches is its pre-image ──
DO $v1$
DECLARE f record; v_body text; p record;
BEGIN
  FOR f IN SELECT DISTINCT fn, CASE WHEN fn = 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure
                                    THEN 'bc718022c00bd26ae3072f463dcd6ead' ELSE 'a5cd09d49ae31a6adebc875b7a329cfd' END AS md5_pre
             FROM _0742_patch LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = f.fn;
    FOR p IN SELECT * FROM _0742_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM f.md5_pre THEN
      RAISE EXCEPTION '0742 V1: % less its patches is not its pre-image (md5 %)', f.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── (d) the grade of the re-estimates ──
CREATE OR REPLACE FUNCTION public.ottoq_ready_promise_update_grade(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public, ottoq, extensions
AS $fn$
-- 0742 (G455): each re-estimate against the visit's readiness check, as 0736's grade reads a promise: a car not ready when
-- the run ended is a miss if the estimate had passed by then, and is otherwise left out (censored). The owner app's time
-- at the same moment is graded beside it. A car already ready is counted (ready_now) and not graded. Read-only.
WITH g0 AS (
  SELECT u.situation, u.elapsed_min, u.ready_p50_min, u.ready_p90_min, u.ready_p50_at, u.ready_p90_at, u.estimated_at,
         u.owner_ready_by_sim AS owner_at, COALESCE((u.detail ->> 'beyond_history')::boolean, false) AS beyond,
         (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
           WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' ORDER BY x ->> 'done_at' LIMIT 1) AS ready_at,
         r.sim_clock_current AS run_end
    FROM public.ottoq_ready_promise_updates u
    LEFT JOIN public.ottoq_visit_needs vn ON vn.visit_id = u.visit_id
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = u.sim_run_id
   WHERE u.sim_run_id = p_sim_run_id AND u.situation <> 'ready'
), g AS (
  SELECT g0.*,
         extract(epoch FROM (g0.ready_at - g0.estimated_at)) / 60.0 AS actual_min,
         extract(epoch FROM (g0.owner_at - g0.estimated_at)) / 60.0 AS owner_min,
         CASE WHEN g0.ready_p50_at IS NULL THEN NULL
              WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.ready_p50_at
              WHEN g0.ready_p50_at < g0.run_end THEN false END AS by_p50,
         CASE WHEN g0.ready_p90_at IS NULL THEN NULL
              WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.ready_p90_at
              WHEN g0.ready_p90_at < g0.run_end THEN false END AS by_p90,
         CASE WHEN g0.owner_at IS NULL THEN NULL
              WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.owner_at
              WHEN g0.owner_at < g0.run_end THEN false END AS by_owner,
         CASE WHEN g0.elapsed_min < 30 THEN 'a_under_30' WHEN g0.elapsed_min < 60 THEN 'b_30_to_60'
              WHEN g0.elapsed_min < 120 THEN 'c_60_to_120' WHEN g0.elapsed_min < 240 THEN 'd_120_to_240'
              ELSE 'e_240_plus' END AS since_arrival
    FROM g0
), parts AS (
  SELECT 'all'::text AS part, 'all'::text AS v, g.* FROM g
  UNION ALL SELECT 'situation', g.situation, g.* FROM g
  UNION ALL SELECT 'since_arrival', g.since_arrival, g.* FROM g
), s AS (
  SELECT part, v,
         jsonb_build_object(
           'updates', count(*), 'ready', count(ready_at), 'censored', count(*) - count(ready_at),
           'no_estimate', count(*) FILTER (WHERE ready_p50_min IS NULL), 'beyond_history', count(*) FILTER (WHERE beyond),
           'graded_p50', count(by_p50), 'by_p50', round(avg(by_p50::int)::numeric, 3),
           'graded_p90', count(by_p90), 'by_p90', round(avg(by_p90::int)::numeric, 3),
           'mae_p50_min', round(avg(abs(actual_min - ready_p50_min))::numeric, 1),
           'bias_min', round(avg(actual_min - ready_p50_min)::numeric, 1),
           'p50_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ready_p50_min)::numeric, 1),
           'actual_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_min)::numeric, 1),
           'with_owner', count(owner_at), 'graded_owner', count(by_owner),
           'by_owner', round(avg(by_owner::int)::numeric, 3),
           'owner_mae_min', round(avg(abs(actual_min - owner_min))::numeric, 1),
           'owner_bias_min', round(avg(actual_min - owner_min)::numeric, 1),
           'owner_in_past', count(*) FILTER (WHERE owner_at < estimated_at)) AS j
    FROM parts GROUP BY part, v
)
SELECT jsonb_build_object('run', p_sim_run_id,
         'ready_now', (SELECT count(*) FROM public.ottoq_ready_promise_updates u
                        WHERE u.sim_run_id = p_sim_run_id AND u.situation = 'ready'))
       || COALESCE((SELECT j FROM s WHERE part = 'all'), jsonb_build_object('updates', 0))
       || jsonb_build_object(
            'by_situation',     COALESCE((SELECT jsonb_object_agg(v, j) FROM s WHERE part = 'situation'), '{}'::jsonb),
            'by_since_arrival', COALESCE((SELECT jsonb_object_agg(v, j) FROM s WHERE part = 'since_arrival'), '{}'::jsonb));
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_ready_promise_update_grade(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_ready_promise_update_grade(uuid) TO service_role;

-- ── (f) tonight's two promise cells re-estimate every 30 sim-minutes ──
UPDATE public.ottoq_throughput_sweep_cells c
   SET fixed_params = c.fixed_params || '{"ready_promise_refresh_min": 30}'::jsonb
  FROM public.ottoq_throughput_sweeps s
 WHERE s.sweep_id = c.sweep_id
   AND (s.sweep_code, c.cell_code) IN (('promise_normal_2026_10_17', 'dcfc10.otto_q.answer_in_tick.promise'),
                                       ('promise_busy_2026_10_17', 'dcfc10.otto_q.promise'));

-- ── V2: nothing for a run that does not exist ──
DO $v2$
DECLARE v_run uuid := gen_random_uuid(); v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_ready_promise(v_run, '11111111-1111-1111-1111-111111111111', now());
  IF v_n <> 0 OR twin.ottoq_sim_record_ready_promises(v_run, now()) <> 0 THEN
    RAISE EXCEPTION '0742 V2: the estimator (% rows) or the recorder acted on a run that does not exist', v_n;
  END IF;
  IF public.ottoq_ready_promise_update_grade(v_run) IS DISTINCT FROM
       jsonb_build_object('run', v_run, 'ready_now', 0, 'updates', 0, 'by_situation', '{}'::jsonb, 'by_since_arrival', '{}'::jsonb)
     OR (public.ottoq_ready_promise_grade(v_run) ->> 'promises') <> '0' THEN
    RAISE EXCEPTION '0742 V2: a grade of a run with nothing recorded is not empty';
  END IF;
END $v2$;

-- ── V3: the grants ──
DO $v3$
BEGIN
  IF has_function_privilege('anon', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0742 V3: a browser role can call the estimator, or the server cannot';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION '0742 V3: the recorder''s grants changed';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_ready_promise_update_grade(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ready_promise_update_grade(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_ready_promise_update_grade(uuid)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_ready_promise_updates', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_ready_promise_updates', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.ottoq_ready_promise_updates', 'INSERT')
     OR has_table_privilege('service_role', 'public.ottoq_ready_promise_updates', 'UPDATE') THEN
    RAISE EXCEPTION '0742 V3: the update grade or the ledger is reachable by a browser role, or not by the server';
  END IF;
END $v3$;

-- ── V4: the dial, the cells, the registry, the check ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'ready_promise_refresh_min'
                    AND default_value = 0 AND min_value = 0 AND max_value = 240 AND agent_writable IS FALSE) THEN
    RAISE EXCEPTION '0742 V4: the dial is not catalogued 0..240 default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE (s.sweep_code, c.cell_code, c.fixed_params) IN
             (('promise_normal_2026_10_17', 'dcfc10.otto_q.answer_in_tick.promise',
               '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.90, "ready_promise_record": 1, "ready_promise_refresh_min": 30}'::jsonb),
              ('promise_busy_2026_10_17', 'dcfc10.otto_q.promise',
               '{"deploy_peak_fraction": 0.90, "ready_promise_record": 1, "ready_promise_refresh_min": 30}'::jsonb))) <> 2 THEN
    RAISE EXCEPTION '0742 V4: tonight''s two promise cells do not carry exactly their parameters plus the refresh';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_schema = 'public'
                    AND table_name = 'ottoq_ready_promise_updates' AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0742 V4: the ledger is not registered as evidence';
  END IF;
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.ottoq_ready_promises'::regclass
         AND conname = 'ottoq_ready_promises_situation_check') NOT LIKE '%after_charge%ready%' THEN
    RAISE EXCEPTION '0742 V4: the arrival ledger''s situation check does not admit the two new situations';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0742_a_promise_stays_honest_while_the_car_waits', false, false,
  'public.ottoq_ready_promise estimates a visit from where it is: ready, or waiting after its charge, drawn given the '
  'minutes it has already waited, and NULL past its history. twin.ottoq_sim_record_ready_promises re-estimates each '
  'promised visit every ready_promise_refresh_min sim-minutes (new dial, default 0) into the evidence ledger '
  'ottoq_ready_promise_updates, graded by public.ottoq_ready_promise_update_grade. V1: each body less its patches is its '
  'pre-image. Only under 0736''s dial ready_promise_record (default 0), which no certification arm, canon cell or dial '
  'experiment sets. Tonight''s two promise cells carry the refresh at 30.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 18:55:12 UTC (1:55 PM CT), ledger version 20261017185512 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed and nothing in flight (P0 read 0, no run running, at 18:50:48
--   UTC). Executable part 31,791 characters, md5 b2b78237a5210c80fadc0b92a7781908, equal to the ledger's statements[1]
--   read back. public.ottoq_ready_promise is now md5 2bf2e3edbd31ba34ca9695cc31923fd6 (prosrc),
--   twin.ottoq_sim_record_ready_promises 7bda931b8aad8d069e75138e0c2214e0 and public.ottoq_ready_promise_update_grade
--   8494a98a7f77877d6a7fda5afae1b0b9, each the body tests/test_ready_promise_sql.py pins on the scratch PostgreSQL; the
--   arrival grade (9058f3a5) and the owner app are untouched. The ledger's grants read postgres=arwdDxtm,
--   service_role=ar. Both promise cells carry ready_promise_refresh_min 30.
--
--   The first apply, at 18:51 UTC, was refused by V3 and rolled back whole: the project's default privileges had given
--   service_role every right on the new table, UPDATE and TRUNCATE among them, which the scratch server does not do. The
--   file now revokes them from service_role as well; that is the only change between the two applies (G456 records that
--   93 of the 100 evidence tables carry those defaults).
--
--   End to end on live after the apply, rolled back by a closing exception: on arm 83's run (normal day) at its hour 4
--   (2026-09-01 15:00 UTC) three cars were put part-way through a visit. Car 1's charge had closed 40 minutes earlier and
--   it had a wash to do: after_charge on the run's after_bay allowance (n 15), 0.600 of it already waited, a median 35.00
--   minutes. Car 2's readiness check had passed: ready, 0 minutes. Car 3's charge had closed 15 hours earlier, longer than
--   any car of the run: no estimate (beyond_history), and no promise. The recorder promised 2 in 29 ms; under the dial, 30
--   minutes on it estimated both again in 39 ms, with the owner app read, and the update grade counted 1 graded and 1
--   ready now. Rolled back in full: no visit, promise, re-estimate or dial row left.
--
--   Executed beside it on the scratch PostgreSQL by tests/test_ready_promise_sql.py (8 more tests, 25 in all, about 45
--   seconds), with 0740 executed there as it ran on live (tests/fixtures/ready_promise_refresh_stub.sql).
