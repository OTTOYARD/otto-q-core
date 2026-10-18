-- migration-version: 20261018111140
-- migration-name:    a_bay_hold_follows_a_charge_that_runs_past_its_plan
--
-- 0744  **A bay hold follows a charge that runs past its plan, instead of holding an empty bay.** (G458)
--       The forward planner books a car's wash at arrival, after its planned charge. Each tick the reconcile
--       (ottoq.ottoq_reconcile_bay_reservations) moves a due hold whose car cannot be there yet, and one of its tests is an
--       unfinished charge leg. It reads only the leg's planned end, so a charge that runs past its plan is invisible: the
--       hold sits on its empty bay through its window and the 15-minute no-show grace while cars that are ready wait.
--       Research wing, rule 10: under a dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 4:55-5:50 PM CT; db/checks/0451 queries (22), (23)) ═════════════════════
--
--   With more chargers the wash is the next line. From a car's charge end to its wash seat, the 90th percentile was 46.5
--   minutes at 10 posts (arm 83), 84.5 at 20 (arm 86) and 172.5 at 40 (arm 84), yet the three bays were not full when it
--   was long: on arm 84 at 8 and 9 AM CT 11 and 12 cars waited while one bay washed. Of the wash reservations that lapsed
--   as no-shows on arms 82, 83, 84 and 86, 24 of 34 had their car still charging at the slot, and every one of the 24 had
--   a charge leg planned to end before it: the charges ran a mean 42, 36, 17 and 22 minutes past their plan, and each
--   hold kept its empty bay a mean 13-15 minutes until the grace freed it. Read each five minutes, a bay sat empty behind
--   such a hold while cars waited for 18, 12, 26 and 15 bay-ticks on those arms (90-130 bay-minutes a run).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_hold_follows_charge (0..1, default 0; not agent-writable).
--   (b) ottoq.ottoq_reconcile_bay_reservations, three anchored insertions, acting only at 1. A due hold whose car is still
--       charging (charging_dcfc or charging_l2) with no charge leg planned to end later is blocked one service length
--       ahead (the hold's own length, at least the walk's 10 minutes), and from there the reconcile defers it exactly as it
--       defers any blocked hold: the same walk, the same move to another bay of its kind, the same defer cap and horizon.
--       The charge's end is not known here, so the hold steps forward while the charge runs; when the charge ends sooner,
--       the calendar's early activation seats the car then.
--   (c) Sweep bayhold_normal_2026_10_17: arm 84's cell (dcfc40.otto_q) with the dial, normal_day from 6 AM CT for 12 hours
--       at 5 sim-minutes a tick, value_2026_09_30's first seed, priority 16 after 0743's, arm budget 3,000 s. It pairs with
--       arm 84 alone, as 0743's cell does, so each change is read by itself; the two together are the next arm if both help.
--   Not changed: how long a car charges, what it needs or when it may leave (rule 9), the activation, the yield, the walk.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the reconcile is the body this file patches (prosrc md5 f6d8b538); the dial and the sweep are
--   absent; arm 84's cell is as read. P2 not already applied. Pre-image to ottoq_schema_snapshots as '0744_pre'. Each
--   anchor matches once. V1 the body less its insertions is its pre-image. V2 nothing for a run that does not exist. V3 the
--   dial is catalogued 0..1 default 0 and not agent-writable, and the sweep's cell is arm 84's plus the dial. Executed in
--   full by tests/test_bay_hold_follows_charge_sql.py on the live body (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the reconcile computes what it computed before
--   (V1), and no certification arm, canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0744_pre'; if no arm has run, DELETE the
--   sweep bayhold_normal_2026_10_17 and its cell and the dial's catalog row;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0744_a_bay_hold_follows_a_charge_that_runs_past_its_plan'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0744 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, arm 84's cell, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'f6d8b538c30d7fa1198c5165fe9dd152' THEN
    RAISE EXCEPTION '0744 P1: ottoq.ottoq_reconcile_bay_reservations is not the body this file patches (md5 f6d8b538)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_hold_follows_charge')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'bayhold_normal_2026_10_17') THEN
    RAISE EXCEPTION '0744 P1: the dial or the sweep already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q'
                    AND c.buildout_code = 'dcfc40' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0744 P1: arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0744_a_bay_hold_follows_a_charge_that_runs_past_its_plan') THEN
    RAISE EXCEPTION '0744 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0744_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_hold_follows_charge',
        '0744 (G458): 1 = a due bay hold whose car is still charging past its charge leg''s planned end is blocked one '
        'service length ahead and deferred as any blocked hold is, so it does not sit on its empty bay through its window '
        'and the no-show grace. 0 = such a charge is invisible to the reconcile, as before 0744. Research days only until '
        'certified.',
        0, 0, 1, 'ottoq.ottoq_reconcile_bay_reservations', false);

-- ── (b) the reconcile ──
CREATE TEMP TABLE _0744_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0744_patch VALUES
  -- 1: the dial's variable
  (1, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$  v_alt    RECORD; v_newstall uuid;
BEGIN
$o1$,
   $n1$  v_alt    RECORD; v_newstall uuid;
  v_follow boolean;   -- 0744 (G458)
BEGIN
$n1$),
  -- 2: the dial, read once per call
  (2, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o2$  v_horizon   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_horizon_min',480),480),30);
$o2$,
   $n2$  v_horizon   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_horizon_min',480),480),30);
  -- 0744 (G458): with bay_hold_follows_charge on, a charge still under way past its leg's planned end blocks its car's bay
  -- hold, as an unfinished leg does. Off, such a charge is invisible here (BLOCKER 1 reads only the planned end).
  v_follow := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_hold_follows_charge', 0), 0) >= 1;
$n2$),
  -- 3: a charge past its plan blocks the hold a service length ahead
  (3, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o3$    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;
$o3$,
   $n3$    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;
    -- 0744 (G458): and a charge still under way past that plan, which the planned end cannot see. Its end is not known
    -- here, so the hold is blocked one service length ahead (at least the walk's own step): the bay is free for that long
    -- for a car that is ready, and if the charge ends sooner the calendar's early activation seats the car then. Each move
    -- is a defer, so the defer cap still releases a hold whose charge never ends.
    IF v_follow AND v_block_at IS NULL AND v_b.vstate IN ('charging_dcfc', 'charging_l2') THEN
      v_block_at := p_clock + GREATEST(v_dur, make_interval(mins => v_step));
      v_blk := 'charging_past_plan';
    END IF;
$n3$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0744_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0744: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0744: the reconcile is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0744_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'f6d8b538c30d7fa1198c5165fe9dd152' THEN
    RAISE EXCEPTION '0744 V1: the reconcile less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: nothing for a run that does not exist ──
DO $v2$
BEGIN
  IF ottoq.ottoq_reconcile_bay_reservations('00000000-0000-0000-0000-00000000744a'::uuid,
                                            '11111111-1111-1111-1111-111111111111'::uuid, now()) <> 0 THEN
    RAISE EXCEPTION '0744 V2: the reconcile moved something for a run that does not exist';
  END IF;
END $v2$;

-- ── (c) the pair: arm 84's cell with the dial ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('bayhold_normal_2026_10_17',
        'A bay hold follows a charge past its plan: arm 84''s 40 robotic fast chargers with bay_hold_follows_charge',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 3000, 'active',
        '0744 (G458). Pairs with arm 84 (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) on value_2026_09_30''s first '
        'seed; it differs only by the dial.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q.bay_hold_follows_charge', 1, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "bay_hold_follows_charge": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'bayhold_normal_2026_10_17';

-- ── V3: the dial and the cell ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_hold_follows_charge' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0744 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'bayhold_normal_2026_10_17') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     JOIN public.ottoq_throughput_sweep_cells c84 ON c84.cell_code = 'dcfc40.otto_q'
                     JOIN public.ottoq_throughput_sweeps s84 ON s84.sweep_id = c84.sweep_id
                                                            AND s84.sweep_code = 'dcfc40_power_normal_2026_10_17'
                     WHERE s.sweep_code = 'bayhold_normal_2026_10_17'
                       AND c.buildout_code = c84.buildout_code AND c.seat = c84.seat
                       AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
                         = (s84.scenario, s84.sim_start, s84.ticks, s84.sim_min_per_tick, s84.seeds[1])
                       AND c.fixed_params - 'bay_hold_follows_charge' = c84.fixed_params
                       AND c.fixed_params ->> 'bay_hold_follows_charge' = '1') THEN
    RAISE EXCEPTION '0744 V3: the sweep''s cell is not arm 84''s plus the dial';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0744_a_bay_hold_follows_a_charge_that_runs_past_its_plan', false, false,
        'Dial bay_hold_follows_charge (default 0); three anchored insertions in ottoq.ottoq_reconcile_bay_reservations that '
        'act only at 1: a due hold whose car is still charging past its leg''s planned end is blocked one service length '
        'ahead and deferred as any blocked hold (V1: body less insertions is its pre-image). Sweep bayhold_normal_2026_10_17 '
        '(arm 84''s cell plus the dial, one seed, priority 16). No certification arm, canon cell or dial experiment sets '
        'the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:11:40 UTC (6:11 AM CT), ledger version 20261018111140 ══════════════════════════════════════
--
--   Through apply_migration with nothing in flight (P0 read 0, no run live, at 11:08:50 UTC, and the file's own P0 at
--   the apply). The text sent, BEGIN through COMMIT and one newline, is 10,473 characters, md5
--   5946a93a223aabe253a01fce58765917, equal to the ledger's statements[1] read back; its executable part is 10,457
--   characters, md5 d3e19fb5dd71e36c1790e5b343df8781, equal to this file's. ottoq.ottoq_reconcile_bay_reservations is
--   now md5 75485e67a20dbb022fe23f817743d213 (prosrc), the body tests/test_bay_hold_follows_charge_sql.py pins on the
--   scratch PostgreSQL. Sweep bayhold_normal_2026_10_17 is queued (one cell, priority 16).
--
--   End to end on live, rolled back by its own raise at 11:42:25 UTC (6:42 AM CT): a probe run at the twin depot; a car
--   charging_dcfc on NASH-DCFC-STALL-01 whose charge leg was planned to end ten minutes before the clock, with a wash
--   hold on NASH-WSH-01 due now. At the dial's default the reconcile moved nothing (the hold -1..17 minutes, held,
--   nothing logged); with bay_hold_follows_charge 1 it moved the hold to 21..39 minutes, one 18-minute service length
--   and the 3-minute taxi ahead, logged deferred / vehicle_not_yet_releasable / charging_past_plan, defer_seq 1.
