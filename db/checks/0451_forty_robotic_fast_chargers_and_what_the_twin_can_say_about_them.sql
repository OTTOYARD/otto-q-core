-- 0451  **Forty robotic fast chargers: what the twin can say about them, and what it costs to ask.** Chase's question of
--        2026-10-17 12:49 AM CT (convert every L2 space to a robotic fast charger?), measured on the twin depot by
--        0724's and 0725's overnight sweeps, beside five things found on the way: the twin's power model (§2), busy_day's
--        wall (§5), why every overnight arm gets ten times slower as its day goes on (§6), cars with no charge facts
--        (§7), and two latent rule-9 regressions in dormant certification arms (§8).
--        -> G443-G447.
--        Read-only throughout, against gxdrcyphqjzjsuhxuqtg, 2026-10-17 from 05:51:42 UTC (the first query's now()).
--        Arms' own rows are cited by arm_id and sim_run_id; every number below names the query that reproduces it.
--
-- ══ §1 THE QUESTION, AND WHAT WAS ALREADY MEASURED (reproduce: (1)) ═══════════════════════════════════════════════════
--
--   The twin depot as built (read 05:51 UTC): 10 dcfc stalls on ABB Terra HP 350 kW, 30 L2 stalls on ChargePoint CT4000
--   19.2 kW, 113 staging, 3 wash bays, 2 service bays; service_max_kw 2,500, dcfc_max_concurrent_kw 1,800, 480 V.
--   120 cars: 44 I-PACE (104 kW inlet), 34 Zoox (100 kW), 36 Tesla (30 at 250 kW, 6 with no inlet figure), 2 Zeekr RT
--   and 4 others with no inlet figure either (§7).
--
--   0567 already built the conversion as data (build-outs dcfc10, dcfc15, dcfc20, dcfc20_grid_today), and
--   value_2026_09_30 has measured 10 against 20 on 24-hour busy days. Since the dial floor (2026-10-14 14:43:27 UTC),
--   per cell, means over the arms on record. CAUTION: two seeds per cell at most, and arms of the same seed are
--   repetitions, not replications (G153), so these are directions:
--
--                                            dcfc10.otto_q   dcfc20.otto_q   dcfc10.fifo.energy_off  dcfc20.fifo.energy_off
--     visits served per day                  326.8           351.7           277.6                   316.9
--     door p50 (gate to leaving), min        271             167             337                     249
--     charge wait p95 (floor), min           497             279             451                     245
--     fast chargers busy                     61.1%           51.3%           66.9%                   53.0%
--     fast-charger mean kW while busy        38.2            38.6            43.0                    39.4
--     full-day site peak kW (max over arms)  1,013           1,806           1,868                   2,384
--
--   The mean kW is the first fact behind the power question: a 350 kW charger delivers about 40 kW averaged over the time
--   it is busy, because the cars cannot take 350 kW (the I-PACE and the Zoox take about 100) and rule 9 charges every
--   car to 100%, where the last 20% runs at a fraction of the peak (0573 §3: 80-100% takes 27.3 min on a Model Y,
--   49.4 on an I-PACE, 21.3 on a Zoox, at 350 kW).
--
-- ══ §2 HOW THE TWIN ENFORCES POWER, AND WHAT A POWER-LIMITED CELL CAN SAY (reproduce: (2)) ═════════════════════════════
--
--   (a) NO POWER SHARING. twin.ottoq_sim_advance_charge_sessions charges every session at the lowest of the charger's,
--       the car's and the battery's limit, with the comment "VEHICLE-FIRST DOCTRINE: charging is NEVER held back. Every
--       active session charges at its full physical rate; peak shaving is the BESS's job". A shared power cabinet (the
--       ABB pair 0567 sources: "two vehicles simultaneously at up to 175kW"; Kempower's power unit, 200-600 kW shared
--       dynamically across up to 12 satellites, https://kempower.com/solution/kempower-power-unit/, read 2026-10-17)
--       divides its power between the cars on it. The twin never does.
--   (b) THE SITE LIMIT BINDS AT ADMISSION ONLY. ottoq_decide_tick (0132) defers a charge with outcome
--       `deferred_site_power_cap` when an ESTIMATE of committed EV kW plus the request passes
--       ottoq_ev_charge_allowance_kw, which is the SERVICE limit (or a demand-response cap), never the DC limit.
--   (c) dcfc_max_concurrent_kw IS ENFORCED, AT CHARGE START, BY THE SHIELD. CORRECTED 07:41 UTC: this paragraph's first
--       draft said "reported, never enforced", which was true before 0428 promoted charge_session_start to an enforcing
--       checkpoint and missed the shield. twin.ottoq_sim_start_charge_session probes EN.001.grid_capacity_ceiling
--       (safety_critical, block) and honours it (ottoq_shield_probe_posture: charge_session_start `enforced`, one caller,
--       honouring). EN.001 refuses a start when the site meter (twin.ottoq_sim_compute_charger_load_kw: every charge,
--       L2 included) plus the request, LEAST(charger kW, inlet kW), passes dcfc_max_concurrent_kw x (1 - margin), margin
--       10% by default, or service_max_kw. Read from the baseline arms' own evaluations: normal_day arm 83 refused 3 starts
--       (largest after_kw 1,836.13 against 1,620), busy_day arm 82 refused 9 (1,953.42 against 1,620); these are the arms'
--       `safety_critical_refused` 3 and 9. twin.ottoq_sim_advance_site_energy's twin.dcfc_cap_exceeded / _approached
--       events (0 rows of 'twin.%cap%' in ottoq_events, read between 06:35 and 06:38 UTC) never fire because the shield
--       keeps admitted load near 1,620. So a power-limited cell is gated twice: by 0132's estimate against the service
--       allowance in the decide path, and by EN.001's meter against 90% of the cabinets at the charge start. Two
--       consequences. On a site that DIVIDES power (0726), a new car adds nothing to the aggregate, yet EN.001 counts
--       its whole request; at 2,400 kW of cabinets it refuses a start whenever the meter plus about 100-350 kW passes
--       2,160, so 0728's `shared` cell measures sharing behind a shield admission at 90%, not a free-connecting site.
--       And for a car with no inlet figure (§7) the request is the charger's whole rating: a fourth answer for those 12.
--   (d) THE ESTIMATE IN (b) OVER-COUNTS. It is LEAST(connector kW, inlet kW or 250) times a SoC band (0.85 under 55%,
--       0.55 under 75%, else 0.30), summed over cars in a charging state; it does not read a meter. Reconstructed per
--       tick from the run's own OCPP 2.0.1 TransactionEvent Updated frames (Power.Active.Import and SoC), run 8954bcf7
--       (dcfc10.otto_q.energy_off, 24 h, seed ...009433), 283 ticks: the estimate is a median 1.50x the metered power
--       (p90 1.96x, mean 672 kW against 446 kW); the busiest tick metered 1,587 kW where the estimate read 1,900. So on
--       a power-limited site the gate starts deferring charges when the real draw is about two thirds of the limit.
--   What follows for 0724's and 0725's power-limited cells: dcfc40_grid_today measures 40 chargers whose cars wait to
--   START for power, judged twice, by an estimator that over-counts against the 2,500 kW service and by the shield's
--   meter against 1,620 kW of the 1,800 kW cabinets (CORRECTED 07:41 UTC: the first draft said the cabinets "may run
--   past their 1,800 kW"; EN.001 keeps them from it). Read it as "40 chargers on today's grid with today's two
--   admission gates", a lower bound on a site whose cabinets divide their power. dcfc40 (the grid grown to 8,089 kW,
--   cabinets 7,200) is the clean cell: neither gate can bind, so its peak is what 40 chargers draw when nothing stops
--   them.
--
-- ══ §3 TONIGHT'S ARMS (reproduce: (3)) ════════════════════════════════════════════════════════════════════════════════
--
--   PENDING: filled in as the arms land.
--
-- ══ §4 THE BILL: DEMAND CHARGES, AND THE TARIFF A FAST-CHARGING SITE SHOULD BE ON (reproduce: (4)) ════════════════════
--
--   The twin prices power at NES GSA Part 3 / TGSA Part 3 (ottoq_depot_tariffs, source the NES PDF
--   https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf, retrieved
--   2026-07-09; 0574): demand $21.40/kW (first 1,000 kW) and $21.78/kW (excess), summer, on the month's highest
--   30-consecutive-minute kW (non-coincident peak); energy 4.785 c/kWh base plus TVA's fuel cost adjustment
--   (2.515 c in September, 0574 §2); $2,091.71 a month fixed; contract demand above 1,000 and up to 5,000 kW.
--   Above 5,000 kW the site leaves GSA-3 for another schedule; this file does not price that.
--
--   Measured on arm 77 (dcfc20.otto_q, 24 h): grid import 12,497 kWh, 30-minute peak 1,697.6 kW, so a demand charge of
--   $36,592.64 a month ($1,219.75 a day) against $880.73 a day of energy: the peak costs more than the energy. That is
--   the whole case for OTTO-Q owning the power at an all-fast-charger site: every kW of the month's peak it avoids is
--   $21.78, and the energy a car needs is the same however fast it is delivered.
--
--   NES's EV schedule, EVC, has no demand charge. READ 2026-10-17 by 07:54 UTC from the schedule itself, both pages
--   (https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/evc.pdf, the source
--   ottoq_energy_rates already cites, retrieved by it 2026-09-30): "ELECTRIC VEHICLE CHARGING POWER RATE - SCHEDULE EVC
--   (Effective October 2024)"; "This rate shall exclusively apply to separately metered charging stations for electric
--   vehicles where the charging station's demand is greater than 50 kW but not more than 5,000 kW"; "Customer Charge:
--   $100.00 per delivery point per month"; energy 21.773 c/kWh onpeak and offpeak, all seasons; "The base energy charges
--   shall be increased or decreased in accordance with the current Adjustment Addendum published by TVA". No demand
--   charge on either page. Two terms that matter for a planner: a contract of "at least 1 year", and a move back to
--   GSA only "after having received service for at least 1 year ... subject to 90 days prior written notice", at a
--   contract demand no lower than EVC's. So the tariff is a yearly decision, not a monthly switch.
--   CORRECTED (the first draft of this paragraph): the January 2025 "retail rate schedule" reads 24.216 c, which the
--   first draft took for a different base. INFERRED, NOT VERIFIED (its PDF still answers HTTP 500): it is this base
--   plus that month's TVA adjustment, 24.216 - 21.773 = 2.443 c, beside the 2.515 c September adjustment 0574 records.
--   The first draft's 20.4% and 15% crossovers each subtracted an adjustment on one side only; its 17.5% was like for
--   like and agrees with the figure below. Like for like, base against base (the adjustment applies to
--   both and cancels): EVC's premium over GSA-3's energy is 21.773 - 4.785 = 16.988 c/kWh, and GSA-3's demand charge
--   is about $21.6 per kW-month, so the crossover monthly load factor is 21.6 / (0.16988 x 730 h) = 17.4%. Below it,
--   EVC is cheaper for the charging meter; above it, GSA-3. (The comparison leaves out the $2,091.71 GSA-3 and $100
--   EVC customer charges: under EVC the building keeps its own GSA service, so the fixed charge does not go away.)
--   Arm 77's load factor is 12,497 / 24 / 1,697.6 = 30.7%: GSA-3 is cheaper there. A site whose peak doubles on the
--   same energy (load factor about 15%) is past the crossover. So the tariff is itself an OTTO-Q output, and a yearly
--   one: a managed peak keeps GSA-3; an unmanaged 40-charger peak would want EVC (if the chargers are metered apart
--   from the building).
--
-- ══ §5 busy_day IS A SERVICE STRESS TEST, NOT A CHARGING ONE (reproduce: (5)) ═════════════════════════════════════════
--
--   ottoq_sim_scenarios.busy_day: pm_interval_km_scale 0.010, compressed calibration, dtc_rate_multiplier 7.0, an 85%
--   soiled wear phase. Since 0715 no car leaves with that work open (rule 9), and 0450 measured the two service bays
--   becoming the wall. Arm 77 (dcfc20.otto_q, 24 h) met 129.3 of the 1,551 car-hours the work side asked for: unmet
--   demand 91.7%, with its fast chargers busy 51% of the time and 84.6% of must-do atoms done. A charger comparison on
--   busy_day measures chargers behind a closed door, which is why 0725 asks the same question on normal_day (dispatch
--   1.0, deployed target 0.90, no compression, no fault multiplier).
--
-- ══ §6 EVERY OVERNIGHT ARM GETS TEN TIMES SLOWER AS ITS DAY GOES ON, AND PRODUCTION DOES NOT (reproduce: (6)) ═════════
--
--   ottoq_tick_clock_log, per 48-tick bucket of a 288-tick arm (arm 78, dcfc20.fifo.energy_off): the world step's
--   compute 1,616 / 2,507 / 3,542 / 4,716 / 5,497 / 5,935 ms a tick, and the gap between ticks (release reservations
--   and the decide path) 3,338 / 9,780 / 16,124 / 23,730 / 29,933 / 31,094 ms. Over fourteen 288-tick arms the first
--   30 ticks average 1.2-4.1 s of world compute and the last 30 6.4-12.9 s; the gap goes from 2-5 s to 33-56 s. The
--   decisions say the same thing from inside: per decision the shield takes 10 -> 40 ms and a stall assignment's
--   enactment 12 -> 118 ms across the day (run 97661eef), while the decisions per tick FALL from 88 to 69.
--   Live runs do not grow. The longest operator runs, a tick per pg_cron transaction: ab534960 (2,668 ticks) 686 ms of
--   world compute over its first 20 ticks and 440 over its last 20; ae8a4908 (2,599) 686 -> 944; 816bd28c (2,564)
--   806 -> 893; and ab534960's per-decision shield latency stays at 8.4-10.8 ms and enactment at 0.5-2.8 ms in every
--   500-tick bucket.
--   The mechanism: an arm (ottoq_throughput_sweep_arm) and a determinism pair run a whole test day inside ONE
--   transaction, by design (a build-out exists only inside its arm's transaction; a deferred trigger refuses to commit
--   one). A row version the transaction itself superseded cannot be pruned until it commits, and the hot rows are
--   updated every tick: vehicles holds 226 rows against 38,061,430 lifetime updates, 20% of them HOT; stalls 10,191,857
--   updates and 15.8 heap fetches per index scan; ocpp_sessions 60.3; ottoq_stall_bookings 17.8 (pg_stat_user_tables,
--   lifetime). So every lookup walks a longer chain each tick. Measured directly, the zero-uuid run idiom
--   COALESCE(sim_run_id, nil) = COALESCE($run, nil) on ottoq_stall_bookings took 72.6 ms against 0.68 ms for
--   sim_run_id = $run (4,057 heap fetches against 0) while an arm was in flight: the idiom cannot use the index on
--   sim_run_id, so it walked every entry of the held/active partial index, and with no held/active booking committed
--   at the time, every entry it walked was the in-flight arm's own uncommitted row or a dead version vacuum could not
--   remove. That last part is database-wide: while an arm's transaction is open it holds back the xmin horizon, so
--   vacuum removes no dead row anywhere, live tables included, for its 1.7-2.4 hours.
--   What it costs: a 288-tick arm takes 1.7-2.4 hours; the first 48 ticks of the same arm take 4-5 s each. A sweep
--   window (7 hours) fits about three 24-hour arms. And for as long as an arm runs, pg_cron starts no other job (G141),
--   which is what made a production start wait behind research (G437). Production is unaffected.
--   The fix's shape, not built here: an arm that commits each tick (a procedure), with the build-out committed for the
--   arm's life and a crash-safe restore (a startup check that restores any build-out whose arm is not running), and
--   the world lock taken at session level. Estimated from the live runs' flat 0.4-1.5 s, a 288-tick arm would take
--   minutes rather than hours. The certification pair keeps its one transaction (both arms must see one world).
--
-- ══ §7 TWELVE CARS WITH NO INLET POWER, AND THREE ANSWERS FOR HOW FAST THEY CHARGE (reproduce: (7)) ═══════════════════
--
--   At the twin depot, inlet_max_kw is NULL on 12 cars: Tesla Cybercab 4, Tesla Model Y (82 kWh) 2, Zeekr RT AV 2, and
--   Chevrolet Bolt EUV, Ford Mustang Mach-E, Rivian R1S, Hyundai Ioniq 5 one each (8 autonomous). Three readers fill the
--   gap three ways: the admission gate counts such a car at 250 kW (COALESCE(vv.inlet_max_kw, 250)); the booking
--   window and the charge-duration ledger use 150 (COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150)); and the charge
--   physics passes NULL to ottoq_sim_compute_charge_rate, where LEAST ignores it, so the car takes up to the charger's
--   350 kW on the median acceptance curve. The same car is a 250 kW load to the gate, a 150 kW charge to the calendar,
--   and whatever its battery's curve allows on the charger. Separately, max_charge_rate_kw still says 200 on the 30 Zoox
--   Robotaxis that 0573 moved to a 100 kW inlet (and 100 on the I-PACEs at 104); every reader prefers inlet_max_kw, so
--   it changes nothing today and misleads anyone who reads the column.
--
-- ══ §8 THE DORMANT CERTIFICATION ARMS STILL CHARGE TO 90% (reproduce: (8)) ═════════════════════════════════════════════
--
--   public.ottoq_cert_arm and public.ottoq_cert_arm_wave set target_soc = 90 on every autonomous car; their only caller
--   is public.ottoq_cert_battery_step, whose cron job (13, ottoq-cert-battery) is inactive. public.ottoq_fr1_cert_arm
--   does the same and has no caller. ottoq_cert_arm_start, beside them, was moved to 100 by 0539. Rule 9 says 100% across
--   the board; re-enabling job 13 would certify a fleet charged to 90. Latent, not live.
--
-- ══ §9 A PROCEDURAL NOTE: apply_migration WAITS BEHIND A SWEEP ARM ════════════════════════════════════════════════════
--
--   The MCP's apply_migration opens with DDL on supabase_migrations.schema_migrations that takes an ACCESS EXCLUSIVE
--   lock; a running arm holds ACCESS SHARE on that table for its whole transaction. 0724's first apply sat in
--   Lock:relation behind the runner (pid 3951184) at 06:07 UTC and was cancelled before its queued lock could block the
--   ledger's other readers. 0724 and 0725 were applied through execute_sql with the ledger row in the same transaction
--   (their APPLIED notes carry the digest proof).
--
-- ══ §10 THE RECOMMENDATION ════════════════════════════════════════════════════════════════════════════════════════════
--
--   PENDING: written when §3 is.
--
-- ══ QUERIES ══

-- (1) the value sweep's cells since the dial floor
SELECT c.cell_code, count(*) AS arms, count(DISTINCT a.seed) AS seeds,
       round(avg((a.scorecard #>> '{throughput,served_per_day}')::numeric), 1)        AS served_per_day,
       round(avg((a.scorecard #>> '{timeliness,door_p50_min}')::numeric))              AS door_p50_min,
       round(avg((a.scorecard #>> '{charge_wait,p95_wait_floor_min}')::numeric))       AS charge_wait_p95_floor,
       round(avg((a.scorecard #>> '{fast_chargers,busy_pct}')::numeric), 1)            AS fc_busy_pct,
       round(avg((a.scorecard #>> '{fast_chargers,mean_kw}')::numeric), 1)             AS fc_mean_kw,
       max((a.scorecard #>> '{kpi,peak_site_kw}')::numeric)                            AS peak_site_kw
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c USING (cell_id)
 WHERE a.sweep_id = (SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30')
   AND a.complete
 GROUP BY 1 ORDER BY 1;

-- (2a) no DC-cabinet event has ever been recorded
SELECT event_type, count(*) FROM public.ottoq_events WHERE event_type LIKE 'twin.%cap%' GROUP BY 1;

-- (2b) the admission estimate against the meter, per tick, from the run's own OCPP 2.0.1 frames
WITH m AS (
  SELECT o.sim_clock_at AS t, COALESCE(st.connector_max_kw, 50) AS ckw, v.inlet_max_kw AS ikw,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(o.payload->'meterValue'->0->'sampledValue') x
           WHERE x->>'measurand' = 'Power.Active.Import') AS kw,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(o.payload->'meterValue'->0->'sampledValue') x
           WHERE x->>'measurand' = 'SoC') AS soc
    FROM public.ottoq_ocpp_messages o
    JOIN public.ocpp_sessions s ON s.id = o.ocpp_session_id
    JOIN public.stalls st ON st.id = s.stall_id
    JOIN public.vehicles v ON v.id = o.vehicle_id
   WHERE o.sim_run_id = '8954bcf7-f084-42a4-99f2-ba9e9c67795c' AND o.message_type = 'TransactionEvent'
     AND o.payload->>'eventType' = 'Updated'),
per_tick AS (
  SELECT t, sum(kw) AS actual_kw,
         sum(LEAST(ckw, COALESCE(ikw, 250))
             * CASE WHEN ckw <= 50 THEN 1.0 WHEN soc < 55 THEN 0.85 WHEN soc < 75 THEN 0.55 ELSE 0.30 END) AS est_kw
    FROM m GROUP BY t)
SELECT count(*) AS ticks, round(avg(actual_kw)) AS avg_metered_kw, round(avg(est_kw)) AS avg_estimated_kw,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY est_kw / NULLIF(actual_kw, 0))::numeric, 2) AS p50_ratio,
       round(percentile_cont(0.9) WITHIN GROUP (ORDER BY est_kw / NULLIF(actual_kw, 0))::numeric, 2) AS p90_ratio,
       round(max(actual_kw)) AS max_metered_kw, round(max(est_kw)) AS max_estimated_kw
  FROM per_tick;

-- (3) tonight's arms
SELECT s.sweep_code, c.cell_code, a.arm_id, a.sim_run_id, a.complete, a.wall_s, a.arm_error IS NOT NULL AS errored,
       a.scorecard -> 'throughput' AS throughput, a.scorecard -> 'timeliness' AS timeliness,
       a.scorecard -> 'charge_wait' AS charge_wait, a.scorecard -> 'fast_chargers' AS fast_chargers,
       a.scorecard -> 'rule9' AS rule9,
       a.arm_metrics -> 'peak_30min_kw' AS peak_30min_kw, a.arm_metrics -> 'grid_import_kwh' AS grid_import_kwh,
       a.arm_metrics -> 'demand_charge_usd_month' AS demand_usd_month, a.arm_metrics -> 'unmet_demand_pct' AS unmet_pct
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c USING (cell_id)
  JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
 WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17')
 ORDER BY a.ran_at;

-- (4) the depot's tariff rows
SELECT schedule_code, season, demand_first_block_usd_kw, demand_excess_usd_kw, block_kw, fixed_monthly_usd,
       energy_base_cents_kwh, demand_basis, provenance->>'source_url' AS source, provenance->'alternatives'->>'EVC' AS evc
  FROM public.ottoq_depot_tariffs WHERE depot_id = '11111111-1111-1111-1111-111111111111';

-- (5) arm 77's demand met, and busy_day's overrides
SELECT a.arm_metrics -> 'demand_car_hours' AS demanded, a.arm_metrics -> 'deployed_car_hours' AS deployed,
       a.arm_metrics -> 'unmet_demand_pct' AS unmet_pct, a.scorecard #> '{fast_chargers,busy_pct}' AS fc_busy_pct,
       a.scorecard -> 'service_completion' AS must_do
  FROM public.ottoq_throughput_sweep_arms a WHERE a.arm_id = 77;
SELECT scenario_code, fleet_overrides, fault_injection FROM public.ottoq_sim_scenarios
 WHERE scenario_code IN ('busy_day', 'normal_day');

-- (6a) an arm's tick cost by time of day
WITH t AS (
  SELECT l.tick_seq, l.tick_compute_ms,
         extract(epoch FROM (l.real_started_at - lag(l.real_ended_at) OVER (ORDER BY l.tick_seq))) * 1000 AS gap_ms
    FROM public.ottoq_tick_clock_log l
   WHERE l.sim_run_id = (SELECT sim_run_id FROM public.ottoq_throughput_sweep_arms WHERE arm_id = 78))
SELECT (tick_seq - 1) / 48 AS bucket, round(avg(tick_compute_ms)) AS world_ms, round(avg(gap_ms)) AS gap_ms
  FROM t GROUP BY 1 ORDER BY 1;

-- (6b) the long live runs, first and last 20 ticks
WITH runs AS (
  SELECT l.sim_run_id, count(*) AS n FROM public.ottoq_tick_clock_log l JOIN public.ottoq_sim_runs r USING (sim_run_id)
   WHERE r.run_by <> 'ab_harness' GROUP BY 1 HAVING count(*) >= 900)
SELECT r.sim_run_id, r.n,
       (SELECT round(avg(tick_compute_ms)) FROM public.ottoq_tick_clock_log x
         WHERE x.sim_run_id = r.sim_run_id AND x.tick_seq BETWEEN 2 AND 20) AS first20_ms,
       (SELECT round(avg(tick_compute_ms)) FROM public.ottoq_tick_clock_log x
         WHERE x.sim_run_id = r.sim_run_id AND x.tick_seq BETWEEN r.n - 19 AND r.n) AS last20_ms
  FROM runs r ORDER BY r.n DESC;

-- (6c) decision latency by time of day, an arm (48-tick buckets) against a live run (500-tick buckets)
SELECT left(sim_run_id::text, 8) AS run,
       (tick_seq - 1) / CASE WHEN sim_run_id = '97661eef-957f-4cb9-8a32-e5410034f757' THEN 48 ELSE 500 END AS bucket,
       count(*) AS decisions, round(avg(shield_latency_ms), 1) AS shield_ms, round(avg(enact_latency_ms), 1) AS enact_ms
  FROM public.ottoq_decisions
 WHERE sim_run_id = '97661eef-957f-4cb9-8a32-e5410034f757' OR sim_run_id::text LIKE 'ab534960%'
 GROUP BY 1, 2 ORDER BY 1, 2;

-- (6d) the hot rows
SELECT relname, n_live_tup, n_tup_upd, n_tup_hot_upd, idx_scan, idx_tup_fetch,
       round(idx_tup_fetch::numeric / GREATEST(idx_scan, 1), 2) AS fetch_per_scan
  FROM pg_stat_user_tables WHERE relname IN ('vehicles', 'stalls', 'ocpp_sessions', 'ottoq_stall_bookings', 'ottoq_sim_runs');

-- (6e) the zero-uuid idiom against a sargable predicate (run while an arm is in flight to see the walk)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM public.ottoq_stall_bookings b
 WHERE COALESCE(b.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
     = COALESCE('97661eef-957f-4cb9-8a32-e5410034f757'::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
   AND b.state IN ('held', 'active');

-- (7) cars at the twin depot whose charge facts are missing or disagree
SELECT make, model, count(*) AS cars, max(inlet_max_kw) AS inlet_kw, max(max_charge_rate_kw) AS max_rate_kw,
       max(battery_capacity_kwh) AS battery_kwh
  FROM public.vehicles WHERE home_depot_id = '11111111-1111-1111-1111-111111111111'
   AND (inlet_max_kw IS NULL OR max_charge_rate_kw IS DISTINCT FROM inlet_max_kw)
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (8) who still sets a 90% target, and whether anything calls it
SELECT p.proname, p.prosrc ~* 'target_soc\s*=\s*90' AS sets_90,
       (SELECT count(*) FROM pg_proc q WHERE q.oid <> p.oid
          AND regexp_replace(q.prosrc, '--[^\n]*', '', 'g') ~ ('\m' || p.proname || '\s*\(')) AS callers
  FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN ('ottoq_cert_arm', 'ottoq_cert_arm_wave', 'ottoq_fr1_cert_arm', 'ottoq_cert_arm_start');
SELECT jobid, jobname, active FROM cron.job WHERE command ILIKE '%ottoq_cert_battery_step%';
