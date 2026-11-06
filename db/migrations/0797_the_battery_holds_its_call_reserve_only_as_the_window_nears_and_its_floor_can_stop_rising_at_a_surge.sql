-- migration-version: 20261106025354
-- migration-name:    the_battery_holds_its_call_reserve_only_as_the_window_nears_and_its_floor_can_stop_rising_at_a_surge
--
-- 0797  **The battery holds its demand-response reserve only as the call window nears, and its floor can stop rising at
--        every surge.** (G517)
--
-- ══ §0 WHAT THE LAB FOUND (FINDINGS G517; lab/research/p2_perfect_day/README.md) ═════════════════════════════════════
--
--   Two reserves stand between the twin depot's battery and a discharge before 2 PM on a summer day. (1) The day plan
--   (0435, ottoq_bess_day_plan) holds bess_plan_dr_reserve_kwh (600 kWh deliverable) for a possible demand-response call
--   between 2 and 8 PM at every step from the first minute of the day, and while the battery holds less than that above
--   its floor plus 3 points it is reserve_protected and does not discharge at all. (2) The floor the plan, the dispatch
--   gate (ottoq_energy_orchestrate) and the reserve target (ottoq_bess_reserve_target) all hold is the battery's own plus
--   20 points times ottoq_forecast_uncertainty, the spread of the last 40 minutes of EV charging, which reads 1.0 from
--   the first tick after a surge begins. Together a battery needs about 33% to discharge at all before 2 PM and about
--   53% during a surge, and the 6 AM start-up surge sets the day's billed half hour.
--
--   Measured with the engine as it runs (the same lab day re-run with both reserves off, every car-facing scorecard line
--   identical, each bill at the base day's end state): $1,543 to $1,301 on the day the battery started 25% full (peak
--   1,475 to 1,132 kW), $1,382 to $1,295 on the day it started 71% full (peak 1,160 to 1,032 kW). No call came on either
--   day; needed only from 2 PM, the reserve costs nothing in hindsight on either (lab/research/p2_perfect_day/
--   bound_energy.py --dr-reserve-kwh 600).
--
-- ══ §1 THE CHANGE: TWO DIALS, AT THEIR DEFAULTS EXACTLY TODAY'S BEHAVIOUR ════════════════════════════════════════════
--
--   (a) bess_plan_dr_reserve_lead_h (hours, 0..24, default 24). The day plan holds the demand-response reserve only once
--       the clock is within this many hours of the call window's start; before then it plans the whole day with no
--       reserve, so the battery may spend into a morning surge, and from then on it holds the reserve exactly as before:
--       reserve_protected while short of it, refilling in the lowest-load half hours before the window (0600's
--       restore_dr_reserve). At 24 the lead covers every hour of the day: today's plan, step for step. A live call
--       overrides everything as before (the orchestrator's DR branch is untouched).
--   (b) bess_reserve_uncertainty_weight (points, 0..40, default 20): the weight on ottoq_forecast_uncertainty in the
--       floor, in all three places that compute it (the day plan's deliverable energy, the dispatch gate, the reserve
--       target), so they stay one rule. At 20, today's floor. At 0 the floor is the battery's own (10%) plus the 3-point
--       margin, which every discharge already keeps.
--
--   Both are a person's dials (agent_writable false; rule 10). Nothing reads either at another scope than the policy
--   tiers. The cars' charging is not touched: it is gated by the installed service limit and demand-response calls,
--   never by the battery's plan (ottoq_effective_charge_cap_kw, 0136); and during a call the cars may still charge on
--   what the battery holds (ottoq_ev_charge_allowance_kw), which (a) refills before the window as today.
--
-- ══ §2 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the three bodies are the ones read on 2026-11-06 (production and the lab
--   agree: day plan 2b8332f9, orchestrator fa4e06d4, reserve target 2c176b11); neither dial is catalogued. Each anchor
--   matches once. V1: each body less its insertions is its pre-image. V2: at the defaults, on the twin depot's latest
--   runs that kept their energy snapshots, the patched day plan (less its solve time) and reserve target return exactly
--   what their pre-images return, at each run's first and last snapshot clocks and one between. Executed in the research
--   lab: a whole lab day with this file applied and the dials at their defaults reproduces the day without it (every
--   energy command, every bill); with the lead at 3 and the weight at 0 the two days above come to the both-off bills;
--   and on a day with a demand-response call the cars' days are identical with the dials on and off and the reserve is
--   held through the window (lab/research/p2_capacity/, tag g517).
--
-- ══ §3 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: at their defaults the three functions return what they returned
--   (V2), and no certification arm sets either dial. Rule 12: built behind its dials, switched on at the twin depot by
--   a separate, named write. Rule 9: no vehicle's need, charge or service is touched; rule 13: no ceiling is added.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0797_pre';
--   DELETE FROM public.ottoq_policy_params WHERE param_key IN ('bess_plan_dr_reserve_lead_h', 'bess_reserve_uncertainty_weight');
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key IN ('bess_plan_dr_reserve_lead_h', 'bess_reserve_uncertainty_weight');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0797_the_battery_holds_its_call_reserve_only_as_the_window_nears_and_its_floor_can_stop_rising_at_a_surge'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0797 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0797_the_battery_holds_its_call_reserve_only_as_the_window_nears_and_its_floor_can_stop_rising_at_a_surge') THEN
    RAISE EXCEPTION '0797 P1: already applied';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)',                  '2b8332f9d612a3e604fb2fdc226c9a20'),
      ('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)',              'fa4e06d41188b6c38e799d69c72d9e73'),
      ('public.ottoq_bess_reserve_target(uuid,uuid,timestamp with time zone,integer,numeric)',    '2c176b1142ffc2577e44eaafbca09df8')
    ) AS t(fn, m)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.m THEN
      RAISE EXCEPTION '0797 P1: % is not the body read (md5 %)', r.fn, left(r.m, 8);
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('bess_plan_dr_reserve_lead_h', 'bess_reserve_uncertainty_weight')) THEN
    RAISE EXCEPTION '0797 P1: a dial of this file is already catalogued';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0797_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
                 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure,
                 'public.ottoq_bess_reserve_target(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure);

-- ── the two dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bess_plan_dr_reserve_lead_h',
        '0797 (G517): hours before the demand-response window''s start from which the battery''s day plan holds the call '
        'reserve (bess_plan_dr_reserve_kwh). Before then the plan holds none, so the battery may spend into a morning '
        'surge; from then on it holds it as before, protecting it while short and refilling it in the lowest-load half '
        'hours before the window. 24 = from the start of the day (the plan before 0797). A person''s dial (rule 10).',
        24, 0, 24, 'public.ottoq_bess_day_plan', false),
       ('bess_reserve_uncertainty_weight',
        '0797 (G517): points of battery floor per unit of ottoq_forecast_uncertainty (the spread of the last 40 minutes '
        'of EV charging, 1.0 from the first tick of every surge), in the day plan, the dispatch gate and the reserve '
        'target alike. 20 = the floor before 0797 (30% through a surge''s first half hour); 0 = the battery''s own floor, '
        'with the 3-point margin every discharge keeps. A person''s dial (rule 10).',
        20, 0, 40, 'public.ottoq_bess_day_plan, public.ottoq_energy_orchestrate, public.ottoq_bess_reserve_target', false);

-- ── the anchored replacements ──
CREATE TEMP TABLE _0797_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0797_patch VALUES
  -- the day plan: the lead's variable
  (1, 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
   $o1$  v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_summer boolean;$o1$,
   $n1$  v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_summer boolean;
  v_dr_lead numeric;   /* 0797 */$n1$),
  -- the day plan: the floor's weight
  (2, 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
   $o2$  v_res_floor := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock), 0) * 20 + 3;$o2$,
   $n2$  -- 0797 (G517): the uncertainty's weight is a dial (20 = as before), one rule with the dispatch gate and the target
  v_res_floor := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock), 0)
                 * GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_reserve_uncertainty_weight', 20), 20)) + 3;$n2$),
  -- the day plan: the lead's read
  (3, 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
   $o3$  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);$o3$,
   $n3$  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);
  v_dr_lead := COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_lead_h', 24), 24);   /* 0797 */$n3$),
  -- the day plan: no call reserve while the clock is more than the lead before the window
  (4, 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure,
   $o4$    v_res[k] := CASE WHEN NOT v_summer OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                     WHEN v_hf < v_dr_s THEN v_dr_kwh$o4$,
   $n4$    v_res[k] := CASE WHEN NOT v_summer OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                     -- 0797 (G517): not yet within the lead of the window: the plan holds no call reserve this pass
                     WHEN EXTRACT(HOUR FROM v_local) + EXTRACT(MINUTE FROM v_local) / 60.0 < v_dr_s - v_dr_lead THEN 0
                     WHEN v_hf < v_dr_s THEN v_dr_kwh$n4$),
  -- the dispatch gate's floor
  (5, 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure,
   $o5$  v_reserve_floor := v_floor + v_uncertainty * 20;$o5$,
   $n5$  -- 0797 (G517): the uncertainty's weight is a dial (20 = as before), one rule with the day plan and the target
  v_reserve_floor := v_floor + v_uncertainty
                     * GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_reserve_uncertainty_weight', 20), 20));$n5$),
  -- the reserve target's floor
  (6, 'public.ottoq_bess_reserve_target(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure,
   $o6$  v_reserve_pct := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock),0) * 20;$o6$,
   $n6$  -- 0797 (G517): the uncertainty's weight is a dial (20 = as before), one rule with the day plan and the gate
  v_reserve_pct := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock),0)
                   * GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_reserve_uncertainty_weight', 20), 20));$n6$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0797_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0797_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0797: anchor % matches % times in %, not 1', p.seq, n, f;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0797: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its insertions is its pre-image ──
DO $v1$
DECLARE f regprocedure; p record; v_body text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0797_patch LOOP
    v_body := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0797_patch WHERE fn = f ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                       JOIN pg_proc pp ON pp.proname = s.object_name
                                      WHERE s.label = '0797_pre' AND pp.oid = f) THEN
      RAISE EXCEPTION '0797 V1: % less its insertions is not its pre-image', f;
    END IF;
  END LOOP;
END $v1$;

-- ── V2: at the defaults, the patched day plan (less its solve time) and reserve target return what their pre-images
--        return, on the twin depot's latest runs that kept their energy snapshots, at three clocks each ──
DO $v2$
DECLARE v_pre text; r record; v_clock timestamptz; v_n int := 0; a jsonb; b jsonb; x numeric; y numeric;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE param_key IN ('bess_plan_dr_reserve_lead_h', 'bess_reserve_uncertainty_weight')) THEN
    RAISE EXCEPTION '0797 V2: a dial of this file already has a value somewhere';
  END IF;
  FOR v_pre IN SELECT replace(replace(definition,
                 'CREATE OR REPLACE FUNCTION public.ottoq_bess_day_plan(', 'CREATE FUNCTION pg_temp.ottoq_bess_day_plan_0797_pre('),
                 'CREATE OR REPLACE FUNCTION public.ottoq_bess_reserve_target(', 'CREATE FUNCTION pg_temp.ottoq_bess_reserve_target_0797_pre(')
                 FROM public.ottoq_schema_snapshots
                WHERE label = '0797_pre' AND object_name IN ('ottoq_bess_day_plan', 'ottoq_bess_reserve_target') LOOP
    IF strpos(v_pre, 'pg_temp.') = 0 THEN
      RAISE EXCEPTION '0797 V2: could not name a pre-image';
    END IF;
    EXECUTE v_pre;
  END LOOP;
  FOR r IN SELECT s.sim_run_id, min(e.timestamp) AS t0, max(e.timestamp) AS t1
             FROM public.ottoq_sim_runs s JOIN public.site_energy_snapshots e
               ON e.sim_run_id = s.sim_run_id AND e.depot_id = s.depot_id
            WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
            GROUP BY s.sim_run_id, s.started_at ORDER BY s.started_at DESC LIMIT 5 LOOP
    FOREACH v_clock IN ARRAY ARRAY[r.t0, r.t0 + (r.t1 - r.t0) / 2, r.t1] LOOP
      a := public.ottoq_bess_day_plan(r.sim_run_id, '11111111-1111-1111-1111-111111111111', v_clock, NULL) - 'solve_ms';
      b := pg_temp.ottoq_bess_day_plan_0797_pre(r.sim_run_id, '11111111-1111-1111-1111-111111111111', v_clock, NULL) - 'solve_ms';
      IF a IS DISTINCT FROM b THEN
        RAISE EXCEPTION '0797 V2: the day plan moved at its defaults on run % at %', r.sim_run_id, v_clock;
      END IF;
      x := public.ottoq_bess_reserve_target(r.sim_run_id, '11111111-1111-1111-1111-111111111111', v_clock, 16, 30);
      y := pg_temp.ottoq_bess_reserve_target_0797_pre(r.sim_run_id, '11111111-1111-1111-1111-111111111111', v_clock, 16, 30);
      IF x IS DISTINCT FROM y THEN
        RAISE EXCEPTION '0797 V2: the reserve target moved at its defaults on run % at %', r.sim_run_id, v_clock;
      END IF;
      v_n := v_n + 1;
    END LOOP;
  END LOOP;
  RAISE NOTICE '0797 V2: % run clocks compared, all equal', v_n;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0797_the_battery_holds_its_call_reserve_only_as_the_window_nears_and_its_floor_can_stop_rising_at_a_surge',
        false, false,
        'G517. Dials bess_plan_dr_reserve_lead_h (default 24: the day plan holds the demand-response reserve all day, '
        'as before) and bess_reserve_uncertainty_weight (default 20: the floor as before), read in ottoq_bess_day_plan, '
        'ottoq_energy_orchestrate and ottoq_bess_reserve_target. At the defaults the three return what they returned '
        '(V2); no certification arm sets either dial, so FALSE/FALSE.',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 02:53:54 UTC (8:53 PM CT on 2026-11-05), ledger 20261106025354, through apply_migration, on
--   Chase's standing word ("continue building as needed. You're the expert, I'm just the CEO", read 2026-11-06 01:24
--   UTC). Nothing live or paused, 0797 not in the lineage, neither dial catalogued, and the three functions at the md5s P1
--   names (read 02:52:58 UTC). The text sent was this file before its version line and this footer were set: 17,975 bytes,
--   md5 47820aceeccb9ac89440a51fb7a48912, equal to the ledger's statements[1] read back. P0, P1, the anchors, V1 and V2
--   passed inside the apply. Read back at 02:56:08 UTC: md5(prosrc) of the day plan 7b7bc59a, the orchestrator 8f425cda,
--   the reserve target 22b198bc, equal to ottoq_lab_0797, the research lab's copy that ran the three gates
--   (lab/research/p2_capacity/g517_lab_2026-11-06.md); three '0797_pre' snapshots; both dials catalogued (24 in 0..24 and
--   20 in 0..40, not agent-writable); the lineage row FALSE/FALSE. The lab template ottoq_lab took the same text and
--   ledger row at 03:01:10 UTC and holds the same three bodies.
-- SWITCHED ON at the twin depot at 02:57:21 UTC (8:57 PM CT): bess_plan_dr_reserve_lead_h 3 and
--   bess_reserve_uncertainty_weight 0, both receipts ok and unclamped, written in one statement that first read no run
--   live at the twin. The writer is "Chase (delegated to Claude Code: 0797)": the decision was made under Chase's
--   delegation, not by him, and the name says so. ottoq_policy_get on the latest twin run reads 3 and 0 (02:57:45 UTC).
--   Not yet seen in a demo run (rule 12): none has started since. The twin's demo days fall in October and November,
--   outside the tariff's summer months (June to September), where the call reserve is not held at all, so on those days
--   only the floor's dial acts.
