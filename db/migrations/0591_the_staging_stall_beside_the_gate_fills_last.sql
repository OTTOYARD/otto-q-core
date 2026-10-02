-- migration-version: 20261001232134
-- migration-name:    the_staging_stall_beside_the_gate_fills_last
--
-- 0591  **The staging stall beside the gate fills last.** One data row at the twin depot: NASH-STG-S024 (the renderer's
--       S3-1) is ranked behind every other staging stall. No function changes.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-01, on cars that drove past their stall and came back ("It needs to immediately turn into that
--   spot"): fixed on the renderer by ottoyarddepot-sim PR #130 (staging arrivals overshooting their stall: 102/299 -> 0/299
--   on five replays). One double-back is left, and it is geometry, not routing: S024 stands right beside the entry gate,
--   nose south, so a car coming in northbound has to loop on the collector to reach it from the north. Asked whether to
--   turn the stall or fill it last, Chase answered: "Fill the spot last."
--
--   Every staging picker in the engine ranks by distance_from_entrance (ottoq_decide_tick's gate intake,
--   ottoq_book_appointment, ottoq_sim_prearrival_contracts, ottoq_stage_after_tow_retrieval, ottoq_stall_free_between,
--   ottoq_reconcile_displace_stale_claim, ottoq_yield_bay_holds), and S024 holds the lowest value, 21 (tied with S023).
--   So it is the FIRST stall a car is given: the one stall that needs a loop is filled before any other.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   S024's distance_from_entrance at the twin depot goes from 21 to one more than the depot's largest staging value
--   (368 today, so 369). It is a ranking, not a survey: the column is operational state that the layout seed never
--   writes (0010 leaves it alone on purpose), and every reader of it is an ORDER BY or, for chargers only, a score.
--   One row is cheaper and safer than seven function bodies, and every picker moves together.
--   The CRN benchmark depot (2222...) is NOT changed, as 0561 did not move it either: it is the A/B harness's own copy.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: no pair, dial, sweep or recert runner in flight, and no run live at the twin depot (0561's P0).
--   P1: S024 exists at the twin depot as a staging stall, and nothing else has already moved it.
--   V1: S024 is now strictly last of the depot's 113 staging stalls by (distance_from_entrance, stall_code).
--   V2: no other stall's row changed.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: it changes which stall a car is given at the twin depot, as 0561
--   did by moving stalls.
--
-- ROLLBACK: UPDATE public.stalls SET distance_from_entrance = 21, updated_at = now()
--             WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_code = 'NASH-STG-S024';
--           DELETE FROM public.ottoq_cert_lineage WHERE name = '0591_the_staging_stall_beside_the_gate_fills_last';

BEGIN;

-- ── P0: nothing in flight, no live run at the twin depot ──
DO $inflight$
DECLARE v_runs text;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0591 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  SELECT string_agg(sim_run_id::text || ' (' || status || ', ' || scenario_code || ')', ', ') INTO v_runs
    FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused');
  IF v_runs IS NOT NULL THEN
    RAISE EXCEPTION '0591 P0: a run is live at the twin depot (%); apply when it has ended.', v_runs;
  END IF;
END $inflight$;

-- ── P1: the row is where this file expects it ──
DO $premises$
DECLARE v_type text; v_dist int;
BEGIN
  SELECT stall_type::text, distance_from_entrance INTO v_type, v_dist
    FROM public.stalls
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_code = 'NASH-STG-S024';
  IF v_type IS DISTINCT FROM 'staging' THEN
    RAISE EXCEPTION '0591 P1: NASH-STG-S024 is not a staging stall at the twin depot (%)', v_type;
  END IF;
  IF v_dist IS DISTINCT FROM 21 THEN
    RAISE EXCEPTION '0591 P1: NASH-STG-S024 distance_from_entrance is %, not 21; something else moved it', v_dist;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0591_the_staging_stall_beside_the_gate_fills_last') THEN
    RAISE EXCEPTION '0591 P1: already applied';
  END IF;
END $premises$;

CREATE TEMP TABLE _0591_before ON COMMIT DROP AS
SELECT id, md5(to_jsonb(s)::text) AS row_md5
  FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';

UPDATE public.stalls s
   SET distance_from_entrance = m.mx + 1, updated_at = now()
  FROM (SELECT max(distance_from_entrance) AS mx FROM public.stalls
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type = 'staging') m
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_code = 'NASH-STG-S024';

-- ── V1: S024 is last; V2: nothing else moved ──
DO $verify$
DECLARE v_last text; v_n int; v_changed int;
BEGIN
  SELECT stall_code, count(*) OVER () INTO v_last, v_n
    FROM public.stalls
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type = 'staging'
   ORDER BY distance_from_entrance DESC NULLS FIRST, stall_code DESC
   LIMIT 1;
  IF v_last IS DISTINCT FROM 'NASH-STG-S024' THEN
    RAISE EXCEPTION '0591 V1: the last staging stall is %, not NASH-STG-S024', v_last;
  END IF;
  IF EXISTS (SELECT 1 FROM public.stalls
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type = 'staging'
                AND stall_code <> 'NASH-STG-S024'
                AND distance_from_entrance >= (SELECT distance_from_entrance FROM public.stalls
                                                WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                                  AND stall_code = 'NASH-STG-S024')) THEN
    RAISE EXCEPTION '0591 V1: another staging stall ties or outranks S024 at the back';
  END IF;
  SELECT count(*) INTO v_changed
    FROM _0591_before b JOIN public.stalls s ON s.id = b.id
   WHERE md5(to_jsonb(s)::text) <> b.row_md5;
  IF v_changed <> 1 THEN
    RAISE EXCEPTION '0591 V2: % rows changed, expected 1', v_changed;
  END IF;
  RAISE NOTICE '0591: NASH-STG-S024 is last of % staging stalls', v_n;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0591_the_staging_stall_beside_the_gate_fills_last', true, true,
  'Twin depot only. NASH-STG-S024 (renderer S3-1) beside the entry gate, nose south, needs a loop on the collector to '
  'reach; Chase 2026-10-01: "Fill the spot last." Its distance_from_entrance goes from 21 (the lowest, tied) to one past '
  'the largest staging value, so every staging picker (all rank by it) gives it out last. Changes which stall a car gets.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
