-- ---------------------------------------------------------------------------
-- 0120 — what migration 0209 was applied against, and how to re-read it.
--
-- Findings L-41 and L-42 (docs/MAGENTA_AUDIT.md) both reduce to the same
-- sentence: the production bridge's declared input did not carry the fields
-- its declared join and its safety check needed. Five queries, each answering
-- one half of that.
--
-- Run them AFTER 0209 to see the closed state; the recorded results below are
-- the readings taken on 2026-09-08, before and after the apply.
-- ---------------------------------------------------------------------------

-- Q1. THE JOIN KEY WAS ABSENT (L-41).
--     Before 0209 the frame emitted make / model / platform and no class code;
--     ottoq_vehicle_classes has no platform column to join platform TO.
--
--     BEFORE:  has_class_code = false
--     AFTER :  has_class_code = true
SELECT pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure)
         LIKE '%vehicle_class_code%'  AS has_class_code,
       pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure)
         LIKE '%supported_inlet_types%' AS has_inlet_list,
       md5(pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure))
                                       AS frame_md5;
--     frame_md5  68bb7da7319e6e5f2fb01b0cefc16f55 -> 218c55825d4fbea1d9892a8811a4c876

-- Q2. THE KEY IS IN THE DATA, so carrying it is worth doing.
--     220 of 221 autonomous vehicles carry a vehicle_class_code. The 221st is
--     the `not_applicable` platform row; the bridge abstains on it by name.
SELECT count(*) AS autonomous,
       count(*) FILTER (WHERE vehicle_class_code IS NOT NULL) AS classed,
       count(DISTINCT vehicle_class_code) AS distinct_classes
  FROM public.vehicles WHERE category='autonomous';
--     autonomous 221 | classed 220 | distinct_classes 3

-- Q3. THE COLUMN NAMES NEVER MATCHED THE KERNEL'S (L-41).
--     The bridge reads battery_kwh / max_charge_kw; the table has neither.
--     This is what proposer/class_table.py exists to translate, and what made
--     "pass ottoq_vehicle_classes rows verbatim" a KeyError rather than a join.
SELECT column_name
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='ottoq_vehicle_classes'
   AND column_name IN ('battery_kwh','max_charge_kw','battery_capacity_kwh',
                       'max_charge_rate_kw','platform','charge_kinds')
 ORDER BY column_name;
--     BEFORE: battery_capacity_kwh, max_charge_rate_kw          (2 rows)
--     AFTER : battery_capacity_kwh, charge_kinds, max_charge_rate_kw
--     Never present, before or after: battery_kwh, max_charge_kw, platform.

-- Q4. THE PLUG RULE THE ENGINE ALREADY RUNS, AND THE HALF THE FRAME COULD NOT
--     REACH (L-42). Every charging stall at the flagship depot is 'Multi',
--     whose compatibility is decided ENTIRELY by supported_inlet_types — the
--     column the frame did not emit. Comparing connector_type to inlet_type
--     literally matches nothing here: no stall is named CCS1 or NACS.
SELECT s.stall_type,
       COALESCE(s.connector_type,'<NULL>') AS connector_type,
       s.supported_inlet_types::text       AS supported,
       count(*)                            AS stalls,
       count(*) FILTER (WHERE s.connector_max_kw > 0) AS charging
  FROM public.stalls s
 GROUP BY 1,2,3 ORDER BY 1,2,3;
--     dcfc        Multi        {CCS1,CCS1,NACS}   22 stalls, 22 charging
--     l2          Multi        {CCS1,CCS1,NACS}   62 stalls, 62 charging
--     l2          Other        {Other}             1 stall,   1 charging (0.024 kW)
--     l2          <NULL>       {}                  1 stall,   0 charging
--     wash_bay    NonCharging  {}                  7 stalls,  0 charging
--     service_bay NonCharging  {}                  5 stalls,  0 charging
--     staging     NonCharging  {}                202 stalls,  0 charging
--     staging     <NULL>       {}                 30 stalls,  0 charging
--
--     84 charging stalls, all Multi. Against them:
--       CCS1 158 vehicles, NACS 62, NULL 1.
--     So the bridge's exact-match-only reading would have abstained on 220 of
--     221 vehicles, and its ignore-both reading proposed a PAD-inlet asset onto
--     a 350 kW DC connector. The L1 shield's rule is neither.

-- Q5. THE INLET IS A PER-UNIT FACT, NOT A PER-CLASS ONE — which is why the
--     bridge reads vehicles.inlet_type and never the class's.
--     tesla_model_y_robotaxi_2024 declares NACS; 7 of its 69 vehicles carry CCS1.
SELECT v.vehicle_class_code, c.inlet_type AS class_inlet,
       COALESCE(v.inlet_type,'<NULL>') AS vehicle_inlet, count(*) AS n
  FROM public.vehicles v
  LEFT JOIN public.ottoq_vehicle_classes c USING (vehicle_class_code)
 WHERE v.category='autonomous'
 GROUP BY 1,2,3 ORDER BY 1,3;
--     tesla_model_y_robotaxi_2024 | NACS | CCS1 |  7
--     tesla_model_y_robotaxi_2024 | NACS | NACS | 62
--     waymo_jaguar_ipace_2024     | CCS1 | CCS1 | 88
--     zoox_robotaxi_2024          | CCS1 | CCS1 | 63
--     <NULL>                      |      | NULL |  1

-- ---------------------------------------------------------------------------
-- WHAT 0209 DID NOT DO, recorded so a later reader does not go looking.
--
-- No verdict hash moves: the frame's only consumers are
-- ottoq_capture_decision_snapshot (records it), ottoq_api_twin_get_state
-- (serves it) and ottoq_score_run (scores it). The decide path reads the
-- tables directly, so two additive jsonb keys cannot move a plan.
-- ottoq_cert_recert_floor() stayed at 0208's 2026-09-07 21:36:53.363037+00.
--
-- ottoq_decision_snapshots.content_hash DOES move, on NEW snapshots only,
-- because it is sha256(jsonb_pretty(frame)). It is self-consistent per row
-- (ottoq_assert_snapshot_integrity recomputes it from the stored frame), it is
-- not in the pair verdict (h_dec is over ottoq_decisions), and no committed
-- number cites it.
-- ---------------------------------------------------------------------------
