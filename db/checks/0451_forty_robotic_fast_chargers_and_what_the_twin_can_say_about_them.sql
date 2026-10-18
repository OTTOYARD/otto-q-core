-- 0451  **Forty robotic fast chargers: what the twin can say about them, and what it costs to ask.** Chase's question of
--        2026-10-17 12:49 AM CT (convert every L2 space to a robotic fast charger?), measured on the twin depot by
--        0724's and 0725's overnight sweeps, beside five things found on the way: the twin's power model (§2), busy_day's
--        wall (§5), why every overnight arm gets ten times slower as its day goes on (§6), cars with no charge facts
--        (§7), and two latent rule-9 regressions in dormant certification arms (§8).
--        -> G443-G447; later sections G448-G459, and G468-G469 (§16, §17).
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
--   Every arm: the twin depot, 6 AM CT for 12 hours at 5 sim-minutes a tick (144 ticks), value_2026_09_30's first
--   seed, OTTO-Q, deploy_peak_fraction 0.90, past the dial floor. ONE SEED PER CELL: each figure is a single reading,
--   not a range (G153), and the two arms of one cell that the overlapping sweeps will produce (0728's note) are the
--   first measure of how far one reading can move. "after 3 h" is the 30-minute peak from 180 minutes into the day,
--   past the opening plug-in, which is what ottoq_value_summary bills (0577); "whole day" includes the opening. Every
--   battery planned against the whole day (G447, §11), so the demand charges are its conceding the afternoon.
--   Arms read 08:18 UTC (82-84), 09:01 UTC (85), 09:33 UTC (86), 10:07 UTC (87) and 10:41 UTC (88, below the table).
--
--   normal_day                           dcfc10        dcfc20        dcfc40        dcfc40_cab2400 on today's 2,500 kW
--                                        as built      20 fast,      power to      .managed      .shared
--                                                      20 L2, grown  spare         (0729, held   (0726 alone,
--                                                                                  at 2,160)     2,400 cabinets)
--     arm / sim run                      83 e7d5824c   86 0b0d45c2   84 b54f6de5   85 fe6d540e   87 dc4fd199
--     visits / served / in depot at end  202/148/54    222/175/47    252/215/37    248/207/41    252/214/38
--     door p50 / p95, min                130 / 428     105 / 305     95 / 248      90 / 270      90 / 249
--     due cars on time (G383)            6 of 54       5 of 59       8 of 72       4 of 66       8 of 70
--     charge wait p50 / p95 floor / max  10/125/190    10/105/140    10/82.5/110   10/90/110     10/100/110
--     fast-charge sessions / L2          97 / 126      168 / 87      278 / 0       264 / 0       267 / 0
--     fast chargers busy, mean kW        69.4%, 39.4   51.8%, 42.3   40.9%, 39.5   41.0%, 38.9   40.7%, 38.6
--     car-hours met of 1,114 asked       821.4         879.8         942.7         941.8         948.3
--     30-min peak kW, whole day          973.8         1,693.1       2,369.5       1,643.7       1,558.6
--     30-min peak kW, after 3 h          713.6         932.5         1,006.8       1,050.6       1,062.1
--     instantaneous EV kW / grid kW max  1,586/1,210   2,779/2,190   3,874/3,287   2,201/1,777   2,136/1,685
--     grid import kWh                    6,723         7,912         9,193         9,050         9,002
--     demand $/month, whole day          20,839        36,496        51,228        35,419        33,567
--     demand $/month, after 3 h          15,271        19,956        21,547        22,501        22,752
--     EN.001 refused starts              3             0             0             85 (84 6 AM)  84 (all 6 AM)
--     DC pool bound (twin.dc_pool_shared)  -           -             -             1 tick        0 ticks
--     must-do service done               83.7%         88.6%         90.9%         90.0%         91.1%
--     rule 9: left below target / open   0 / 0         0 / 0         0 / 0         0 / 0         0 / 0
--
--   busy_day, dcfc10 as built (arm 82, 43301561): 212 visits, 103 served, 109 in the depot at the end; door p50/p95
--   305/584; 0 of 36 due cars on time; charge wait p50/p95/max 80/355/435; car-hours met 96.0 of 1,114; 30-min peak
--   975.9 whole day, 861.0 after 3 h; EN.001 refused 9; rule 9 0/0. The two service bays are this day's wall (§5).
--
--   Read on the normal day, 40 posts with power to spare against the depot as built: 67 more cars served in 12 hours
--   (+45%), the median car out 35 minutes sooner and the slow tail cut from 428 to 248 minutes, and 121 more car-hours
--   of ride demand met (unmet 26.3% -> 15.4%). Every car still leaves at its full target with nothing open.
--
--   The sizing curve, from 0730's dcfc20 (arm 86, 20 fast posts and 20 L2): car-hours met 821.4 -> 879.8 -> 942.7 at
--   10, 20 and 40 fast posts; cars served 148 -> 175 -> 215; the slow tail 428 -> 305 -> 248 minutes. Posts 11-20 bought
--   58.4 car-hours, 5.8 each in a 12-hour day; posts 21-40 bought 62.9, 3.1 each. So the returns fall by about half past
--   twenty and do not stop: there is no sharp knee on this day, and the post count is a price question (§10).
--
--   The power question, answered on this day: the megawatts are the OPENING. With nothing holding it, the fleet's 6 AM
--   plug-in drew 3,874 kW at the chargers (3,287 kW from the grid after the battery) and set a 2,369.5 kW 30-minute
--   peak; from 9 AM on, the 30-minute peak was 1,006.8 kW, 293 kW above the depot as built.
--
--   And holding it costs almost nothing. Behind a site controller at 2,160 kW on TODAY'S 2,500 kW service (arm 85),
--   the forty met 941.8 car-hours against 942.7 with power to spare, served 207 cars against 215, and kept the slow
--   tail at 270 minutes against 248, while the whole-day 30-minute peak fell from 2,369.5 to 1,643.7 kW ($51,228 to
--   $35,419 a month billed on the whole day). Most of what a 6 AM plug-in wants is power for cars that are not yet due,
--   so spreading it over the morning cost 8 served cars and 0.9 car-hours. It is not free: due cars on time went from
--   8 of 72 to 4 of 66, a single reading on one seed, and the cars an owner needs back first are exactly the ones a
--   held site should give its power to first (§10). Past 9 AM the two arms draw alike (1,006.8 and 1,050.6 kW). So the
--   conversion does not need a bigger grid connection; it needs the site held at a limit, and OTTO-Q to own it.
--
--   And the two readings of a shared site came out alike. Arm 87 (0726's sharing alone, the shield counting each new
--   car's whole rating, 2,400 kW of cabinets) met 948.3 car-hours, served 214 and refused 84 starts, all before 7 AM;
--   arm 85 (0729's managed reading) met 941.8, served 207 and refused 85. Single readings, inside one reading's noise
--   of each other and of arm 84 (942.7 with an 8 MW grid). So on this day forty robotic posts behind 2.4 MW of shared
--   cabinets on TODAY'S service did what forty did on a grown grid.
--
--   The two arms' refusals are of different kinds, and the difference is 0729 doing what it was built for. CORRECTED:
--   this paragraph's first draft, and G448 as first written, said both arms' refusals came with the meter over the
--   cap; query (3b) shows that is true of arm 85 only. On arm 87 every one of the 84 came with the meter UNDER the
--   2,160 kW cap (1,841-2,142 kW) and the car's full rating on top (a mean 221 kW). On arm 85 none did: every one of
--   its 85 came with the meter itself over the cap (2,182-2,285 kW, mean 2,224), 84 of them before 7 AM. That is G448.
--   A session the twin starts is metered at its full unshared rate, and each tick judges its charge starts before its
--   charge step meters the running sessions, so a car started in one tick is still on the meter at full rate when the
--   next tick's starts are judged. On arm 85 the 24 sessions started in the opening tick (06:10) put the meter at
--   2,200.8 kW and the 16 starts judged after them were refused; at 06:15, 16 more were refused against the same
--   2,200.8 kW, and only then did the charge step meter those 24 at their pool shares, which sum to exactly 2,160.0 kW
--   (their OCPP TransactionEvent frames, query (3c)). So 0729 removed every refusal of arm 87's kind and G448 put the
--   same number back. A real managed site assigns the share at connection. The refused cars waited a tick or two; the
--   throughput above already carries that wait.
--
--   0728's third normal-day cell, arm 88 (7fe98840): arm 87's cell with 0132's site gate left on (its default) and
--   counting committed load as metered (0727). 215 served of 255, door p50/p95 90/267, due cars on time 8 of 71,
--   charge wait p50/p95 floor/max 10/85/110, 271 fast sessions at 40.7% busy and a mean 38.3 kW, 951.2 car-hours met,
--   30-min peak 1,585.3 kW whole day and 1,139.2 after 3 h ($34,149 and $24,432 a month), instantaneous EV/grid max
--   2,066/1,679 kW, must-do done 89.7%, rule 9 0/0. EN.001 refused 52 starts (39 before 7 AM, every one with the meter
--   under the cap and a mean 127 kW on top) and 16 charge-stall assignments in the decide path (all before 7 AM, each
--   taking the safe default); the pool never bound. Against arm 87, the same cell with the gate off, it came out alike
--   (951.2 car-hours against 948.3, 215 served against 214), with fewer refusals (68 against 84) and a higher
--   afternoon peak (1,139.2 against 1,062.1 kW). So a site held at its limit met the grown grid's car-hours all three
--   ways tried: 941.8 (0729's managed reading), 948.3 (0726's sharing alone) and 951.2 (with the metered gate), against
--   942.7 with 8 MW to spare. Single readings on one seed.
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
--   ADDED 07:58 UTC, the facts those cars should carry, from narrow searches (rule 3: claim, date, URL; all THIRD-PARTY,
--   none from the maker, and each varies by variant, so the twin car's own pack picks the row). Chevrolet Bolt EUV
--   (65 kWh here): 55 kW peak DC (https://evkx.net/models/chevrolet/bolt/bolt_euv/charging/, read 2026-10-17, "estimated,
--   derived from manufacturer data"). Ford Mustang Mach-E (91 kWh, the extended-range pack): 150 kW
--   (https://www.evspecs.org/tech-specs/ford/mustang-mach-e/extended-range-rwd, read 2026-10-17; three other listings
--   agree). Rivian R1S (135 kWh, the large pack): 220 kW (https://www.evspecs.org/tech-specs/rivian/r1s/dual-motor-awd-large-pack,
--   read 2026-10-17), against 207-210 kW per variant at https://evkx.net/de/models/rivian/r1/r1s_quad-motor_awd/charging/.
--   Hyundai Ioniq 5 (77.4 kWh): no listing for this pack was found; the 84 kWh packs read 263 kW and the 63 kWh 195 kW
--   (https://www.fleetnews.co.uk/electric-fleet/electric-car-and-van-data/hyundai/ioniq-5-2237, read 2026-10-17), and
--   one guide gives 220 kW for the line (https://zecar.com/reviews/hyundai-ioniq-5-charging-guide). Tesla Cybercab and
--   Zeekr RT: no published DC rating was found, so they need one explicit default that every reader shares, not three.
--   The defect is the disagreement more than the gaps: one function answering "how much can this car take" for the
--   gate, the calendar, the physics and the shield is the fix, and filling a car's facts changes the world the charge
--   clock learns from, so it is recorded in ottoq_evidence_regimes in the same file (0625's standing rule).
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
--   To Chase, from the research wing (rule 10: a recommendation, shipped only as certified changes). Written on arms
--   82-88, the night of 2026-10-17; 0731's bill-window pairs run in the next window.
--
--   1. LEAN IN. Robotic fast charging is the edge, and the evidence is the slow tail and the car-hours, not the median.
--      On the normal day forty robotic posts served 45% more cars in 12 hours than the depot as built, cut the slowest
--      5% from 428 to 248-270 minutes, and met 121 more car-hours of ride demand (15% unmet against 26%), every car at
--      100% with nothing open. A robot on every post is what makes that possible: no car waits for a person to plug it
--      in, so the depot's limit stops being connectors and labour and becomes power and time.
--      CORRECTED 2026-10-18 (§15): with the twin's command lag removed (0735), forty posts served 29% more cars than the
--      depot as built, not 45%: 205 against 159, the slowest 5% at 274 minutes against 378, and 108.4 more car-hours
--      (15.6% unmet against 25.3%), every car still at 100% with nothing open. The lag had cut every wash seat a tick
--      short, and forty posts are wash-bound, so it flattered them most.
--
--   2. SIZE THE POSTS BY THEIR PRICE, NOT BY THE STALLS. Forty posts were busy 41% of the day against the ten's 69%,
--      and the curve bends: posts 11-20 met 5.8 car-hours each in the 12-hour day (an upper bound until 0734 measures
--      what the 5-minute tick costs the depot as built and 0735's arms read the curve with the twin's command lag
--      removed, G449, G450, §12), posts 21-40 met 3.1 each (§3). At the
--      value sweep's own prices (ottoq_margin_prices: $20 a deployed car-hour, range $16-24, its Waymo-review source;
--      about $206,000 installed per 350 kW charger, its INL source, before the robot itself), a month of such days is
--      worth about $3,500 per post for posts 11-20 and $1,900 per post for posts 21-40, against about $1,700 a month
--      for a post's installed price spread straight over ten years with no financing, robot or upkeep. ASSUMPTIONS, all
--      of them: one seed, a 12-hour day and nothing for the night. On that reading twenty posts clearly pay, and the
--      second twenty pay only if the night, the robot's price and more seeds come out in their favour. A staged build,
--      twenty now and the rest as measured demand fills them, buys the same answer with half the capital at risk.
--      CORRECTED 2026-10-18 (§15): 5.8 was not an upper bound. With the lag removed, posts 11-20 bought 7.7 car-hours
--      each and posts 21-40 bought 1.6: about $4,600 a month per post against $950, at the same prices and on the same
--      assumptions. The lag had added a tick to every handover in the queue at twenty posts and given forty posts
--      short wash seats, so it bent the curve the wrong way at both ends. On this reading twenty posts pay clearly and
--      the second twenty do not, because past twenty the wash is the wall (§13, G458): the second twenty wait on the wash
--      line's fixes (0743-0747) and their arms. One seed; seeds 2 and 3 have not run.
--
--   3. DO NOT SIZE THE GRID TO THE NAMEPLATE. Forty posts with nothing holding them drew 3.9 MW for the 6 AM plug-in.
--      On the existing 2.5 MW service, behind 2.4 MW of shared cabinets, they met 941.8 car-hours (held at 2.16 MW,
--      0729), 948.3 (0726's sharing alone) and 951.2 (with the site gate reading the meter, 0727) against 942.7 on a
--      grid grown to 8 MW. The megawatt worry is a control
--      question, and its answer is a site controller holding a limit that OTTO-Q sets: shared cabinets (the Kempower and
--      ABB units 0567 and 0728 cite) with OTTO-Q deciding the split. No utility upgrade is needed for this day's load.
--      CORRECTED 2026-10-18 (§16): the opening draw is 3.7 MW on the chargers' own readings (3,731 kW on arm 84, 3,749
--      in tick on arm 95); the site meter's 3,874 counted some new charges' first intervals twice.
--
--   4. THE BILL TO MANAGE IS THE DEMAND CHARGE, AND THE TARIFF IS A YEARLY DECISION. At GSA-3's $21.40-21.78 per kW
--      of the month's highest half hour, the unmanaged forty cost $51,228 a month in demand on the whole day against
--      $35,419 held; past the opening both sit near $22,000 against $15,271 as built. NES's EVC schedule has no demand
--      charge at 21.773 c/kWh, and beats GSA-3 for the charging meter below a 17.4% monthly load factor; it carries a
--      one-year term and 90 days' notice back (§4). A held site keeps its load factor up and stays on GSA-3.
--      CORRECTED 2026-10-18 (§16, §17): every figure in this point was read on arms with the twin's command lag, whose
--      site meter counts each new charge's first interval twice (the energy 12-20% high), and arm 84's $21,547 past the
--      opening is two samples at the day's end billed as a half hour. In tick, over full half hours, past the opening:
--      $17,125 a month as built (arm 93), $19,780 at twenty posts (arm 94), $20,129 at forty (arm 95, nothing holding
--      them); on the whole day $18,927, $31,247 and $42,204. The held site has not run in tick.
--
--   5. WHAT THE ENGINE NEEDS BEFORE A REAL CONVERSION, as certified changes, each already measured in the twin:
--      (a) the shield judges a site that divides its power by the limit it holds (0729 models it; production needs the
--          site controller's limit in the charge start's context, and the controller itself). On the managed arm it
--          removed every refusal of the shared arm's kind (the meter under the cap and each car's full rating on top:
--          all 84 there);
--      (b) the battery plans for the bill that is charged, and is ready for the surges OTTO-Q itself schedules: it
--          charged at 425 kW in the tick the fleet plugged in, shaved one tick late, and idled all afternoon (G447);
--      (c) one answer for how much power a car can take (G443: twelve cars, four answers);
--      (d) the site gate reads the meter, not a band estimate 1.50x high (0727; on arm 88 it cost nothing measurable).
--      And one fix to the twin itself, which production does not need (G448). A car that had just started was metered
--      at its full rate, so all 85 of the managed arm's refusals came with the meter itself over the held cap.
--      CORRECTED: this point first listed that as a certified engine change. In this database only the twin's start
--      function writes a session's first reading; a real charger reports its own. 0733 fixes it in the twin under a
--      dial (dc_power_first_reading), and its paired arm runs first in the next window.
--
--   6. THE FRONTIER: POWER BY NEED. Once every car is connected on arrival, the decision that matters is how a held
--      limit is divided, tick by tick, among the cars on it. 0726 divides it max-min fairly, as a cabinet left to itself
--      does. OTTO-Q knows what the cabinet does not: which car is due back to its owner first, how much each still
--      needs, and what each contract allows. Giving a held site's power to the cars due first is ordering, never a
--      shorter charge (rule 9), and it is a cumulative-resource scheduling problem, the construct CP-SAT handles and
--      cuOpt cannot express (CLAUDE.md 2.5). In production it publishes as per-connector charging profiles (OCPP
--      SetChargingProfile: OCPP 2.0.1 Part 2's Smart Charging chapter, K, per
--      https://josev.ecog.io/docs/how-tos/how-to-control-charge-limit-imposed-by-smart-charging-service; its fields,
--      chargingProfile and evseId, at https://ocpp.hexdocs.pm/ocpp/v2_1/message/set_charging_profile.html, a 2.1
--      reference, both read 2026-10-17, to be confirmed against the OCA's 2.0.1 document), schedule-shaped, inside the
--      power boundary 2.5 draws. That is the next build to measure
--      against max-min fair on the same seeds. Its target is the immediate dispatches whose charge fits their 45-minute
--      due (35 of 66 with power to spare, §12), not all due cars: 8 of 72 were on time free and 4 of 66 held (§3).
--      BUILT IN ITS SIMPLEST FORM, 2026-10-17 11:49 AM CT (0737, dial dc_power_by_need): a bound pool gives every car
--      with a due its full demand, earliest due first, and shares the rest evenly. That is broader than the target above,
--      on purpose: earliest due first is the textbook rule for the latest a car can be on one shared resource, and its
--      arm (arm 85's cell plus the dial) shows what it buys the due cars and costs the rest. Only if it costs the rest
--      more than it buys is the narrower rule worth its own arm. The arm runs after 0732's seeds.
--
--   7. WHAT IS NOT KNOWN YET. One seed per cell, so every gap above is a single reading. The repeats of arms 84 and 86
--      that 0725's sweep holds run the same seed again: they test whether a reading repeats from one night to the next,
--      which it does byte for byte only if nothing the engine reads has changed in between (the charge clock is refit
--      nightly, G387), and they say nothing about how far a reading moves from seed to seed. That needs other seeds, and
--      0732 queues them: the four cells this rests on (arms 83, 86, 84, 85) on value_2026_09_30's seeds 2 and 3, next
--      in the window after 0731's pairs.
--      A 12-hour day from 6 AM: no night, where L2's slow charge costs least. busy_day's wall is the two service bays
--      (§5), which more chargers cannot move. The battery's worth on the billed window is 0731's three paired arms.
--
-- ══ §11 THE BATTERY PLANS FOR A BILL THE VALUE VIEW DOES NOT CHARGE (G447; reproduce: (9)) ══════════════════════════
--
--   ottoq_bess_day_plan (0435, 0600) shaves to a level no lower than the month's billed peak so far, which it counts from
--   completed 30-minute windows starting bess_plan_bill_from_min minutes into the run. The dial defaults to 0, and no
--   sweep cell sets it: not tonight's, and not value_2026_09_30's eight. The value view bills demand from 180 minutes in
--   (ottoq_value_summary's c_open_min; 0576/0577: the opening plug-in is not the depot's peak). So the opening sets the
--   plan's billed peak, and the plan then concedes the window the value view bills.
--
--   Arm 84 (dcfc40.otto_q, normal_day, sim run b54f6de5), from its own ottoq_energy_commands, read by 08:27 UTC:
--     06:05  mode charge, cheapest_window, setpoint -425 kW, level 949 kW, billed peak 0. The chargers drew 3,874 kW
--            that tick: the boot seats cars on chargers before the first plan sees them.
--     06:10  shave, 1,499 kW (the unit's limit), level 2,418.
--     06:30  hold.
--     06:50  billed peak 2,370 kW (the opening's first completed half hour), level 2,370, charge (cheapest_window).
--     13:30  to the end of the day: hold, level 2,370, the battery at 90-91% (bess_snapshots), while the grid peaked at
--            1,180 kW at 3 PM and the half hours the value view bills peaked at 1,006.8 kW.
--   Arm 83 (dcfc10, the same seed and day) has the same shape: the battery at 0 kW all afternoon, the grid up to 838 kW,
--   under a billed peak of 973.8.
--
--   What it means here. Every arm in §3 and every arm of the value sweep ran at 0, so the comparisons between cells
--   stand. The absolute demand charges in §3 and §4 are the battery standing aside after the opening, and they overstate
--   what a depot with this battery would pay on the window the value view bills. The fix is one dial per cell:
--   bess_plan_bill_from_min 180, so the plan and the bill read the same window. 0731 queues the paired cells on the same
--   seed and day. A real depot's month has no test-day opening, and its battery would face each day's real peaks.

-- ══ §12 WHAT THE 5-MINUTE TICK COSTS, AND WHAT A 45-MINUTE PROMISE CANNOT BUY (G449, G383; reproduce: (10), (11)) ═══
--
--   Every sweep on record runs at 5 sim-minutes a tick (15 sweeps, 87 arms), and at that tick a fast-charger handover
--   takes two ticks. On arm 83 (the depot as built), 67 of 87 fast-charger handovers had a car waiting for a fast
--   charger: 58 took exactly 10 minutes, none took fewer, and 13.5 charger-hours sat idle with a car waiting, against
--   89.0 hours of fast charging (13%). Traced on stall 91ebbf41: the charge ends at 8:00 CT, the arm's demate (due 8:02) is cleared at 8:05, the
--   stall is freed and reserved then, and the next car's charge starts at 8:10. The readiness check has the same shape:
--   on arms 83 and 84, 190 cars whose charge was their last open work were ready exactly 10 minutes after it closed,
--   median and p90 alike, for a 3-minute check.
--
--   What it means here. A robotic handover is a few minutes of physical work, and production ticks every 120 seconds,
--   so this is the twin's resolution, not the engine's. It costs a depot with a queue and not one without, so the
--   sizing curve of §3 (posts 11-20 bought 5.8 car-hours each) may be partly the tick. 0734 runs the depot as built over
--   the same morning on the same seed at 5 and at 2.5 sim-minutes a tick; until it lands, read §10 point 2's first step
--   as an upper bound.
--
--   And the promise. Every immediate dispatch is due exactly 45 minutes after it arrives (G383). With forty fast
--   chargers and power to spare (arm 84), 31 of the 66 that charged spent longer than that on the charger alone, at a
--   median 45-minute charge from a median 63.5%. No order, power or post count makes those on time while each charges
--   to 100% (rule 9). So "due cars on time" measures the promise as much as the depot, and power by need (§10 point 6)
--   can reach only the immediate dispatches whose charge fits their due: 35 of the 66.
--
--   One cause under the handover, and a second cost it hides (G450, 2026-10-17 afternoon). The twin carries out every
--   command a tick after the decide gives it: on arm 83 all 507 executed commands were confirmed exactly 5.00
--   sim-minutes after issue. That lag is the handover's second tick. It also cuts every bay seat short. The decide books
--   a bay from its own clock for the leg's planned length, and the car, seated a tick later, still leaves at the
--   booking's end. On arms 82-88, 470 of 472 bay seats began exactly one tick after their booking: washes sat a mean
--   11.9-13.1 of 16.9-18.1 booked minutes, services 35.0-44.6 of 40.4-49.6. So the twin's bays turn faster than their
--   own plan. That flatters busy_day, whose wall is the two service bays (§5), while the handover penalizes a charger
--   queue: two biases from one lag, in opposite directions. 0735 (dial twin_answer_in_tick, applied 16:16 UTC) carries a
--   command out in the tick it is given. Its arms run in the next window after 0734's: the same morning, then the
--   normal day at 10, 20 and 40 posts, paired with arms 83, 86 and 84. Query (12) reads both costs on any run.
--   The handover's first tick remains (the twin stamps a charge's end at the tick boundary). Its candidate fix, stamping
--   the moment the pack filled, is in G449; it waits on 0734's pair, because if half the tick changes little it buys little.
--   MEASURED 2026-10-18 (§15): halving the tick bought about half what answering in the tick did, and the first-tick
--   candidate is not built.
--
--   The promise itself (G383, 0736, applied 16:38 UTC). When a car arrives, OTTO-Q now estimates when it will be ready.
--   The estimate is its own plan of the charge line, simulated in 16 sampled futures, with every charge to 100% on the
--   charge clock. It adds what the run's earlier cars needed after their charge. It gives a median and a 90th
--   percentile, which the twin records once per visit and grades against the readiness check. In the dry run a 62%
--   immediate dispatch due in 45 minutes was promised a median 61 minutes and a 90th percentile 69. The grade decides
--   whether the 90th percentile holds 90% of cars. Its arm (0735's dcfc10 cell plus the recorder) runs in the next window,
--   and must agree with its partner on every outcome, because the recorder decides nothing. Query (13) grades it.
--
--   Tested before it ran, and corrected (G452, 0739, applied 17:33 UTC). The part after the charge learned only from the
--   cars that had finished, so on a day the bays back up it kept saying what the lucky cars took: on arm 81 at hour 8 it
--   said 33 minutes after the charge while the next hour's cars took 395, and on arm 82 at hour 6, 35 against 110.
--   Normal days were fine. 0739 counts the cars still waiting (Kaplan-Meier), draws the promise from the world rather
--   than the run's id, and reads it from 128 draws. Query (14) is the rehearsal, rerunnable on any arm. On a busy day
--   the honest promise is long: arm 81's three test cars went from a median 140-188 minutes to 470-560.
--   0740 (applied 17:42 UTC) queues the same promise on arm 82's busy day, right after the normal day's promise arm,
--   so the grade covers both; it must agree with arm 82 on every outcome. Query (13) reads either arm's grade.
--   What the owner is told today is a different time (G454, 0741, applied 18:22 UTC). The owner app, and a personal
--   agent through OTTO-Command, says "Planned to be ready around ..." from the end of the car's last planned itinerary
--   leg, not from the promise, and that time has never been graded: the itinerary is amended in place, so what an owner
--   was told at arrival cannot be read back. 0741 records the app's time beside each promise on both promise arms and
--   grades both on the same cars. Query (18) puts them side by side.
--   And the promise was only right at arrival (G455, 0742, applied 18:55 UTC). Asked again about a car whose charge was
--   done and that was still waiting, 0739's estimator said "ready now" for nearly every one: 239 of 247 waiting car-hours
--   on arm 82, 1,692 of 1,710 on arm 81, 50 of 56 on arm 83 (query (19)). 0742 draws such a car given how long it has
--   waited, which brings the normal days close to honest and leaves the busy days poor, and says it does not know when a
--   car has waited longer than any its history holds. Both promise arms now re-estimate every promised car every 30
--   sim-minutes, with the owner app's time beside it; query (20) grades that second look.

-- ══ §13 THE WASH IS THE NEXT LINE, AND THE BAY CALENDAR SEATS ALL OR NONE (G457, G458, G453; reproduce: (21)-(25)) ════
--
--   Read 2026-10-17 4:55-5:50 PM CT from last night's normal-day arms (seed 1, 12 hours) and arm 82.
--
--   With more chargers the next line is the wash (query (21)). From each car's charge end to its wash-bay seat:
--     10 posts, arm 83   p50 12.5, p90 46.5, longest 100 minutes   (48 washes after a charge)
--     20 posts, arm 86   p50 15.0, p90 84.5, longest 170           (52)
--     40 posts, arm 84   p50 22.5, p90 172.5, longest 421          (66)
--     40 managed, arm 85 p50 20.0, p90 177.5, longest 421          (66)
--   Booked washes run 17.1-18.2 minutes. The line is a morning one, and the bays are not full when it is long: on arm 84
--   at 8 and 9 AM CT 11 and 12 cars waited while one of the three bays washed; on arm 86 at 7-8 AM 4-5 waited and none
--   washed.
--
--   Read every five minutes (query (22)), a wash bay sat empty while cars waited, with no booking on it at all, for 130,
--   159 and 130 bay-ticks on arms 83, 86 and 84 (131 on arm 82), flat from 10 to 40 posts. That is not traced here; part
--   is the walk from charger to bay, a tick a step (G449, G450), which tonight's 0735 arms shorten. And for 12, 15 and 26
--   bay-ticks (18 on arm 82) a bay sat empty behind a reservation for a car that did not come. Two causes are measured.
--
--   (a) A reservation for a car still charging holds its empty bay (query (23), G458). Of the 34 wash no-shows on arms 82,
--       83, 84 and 86, 24 had their car still charging at the slot, and every one had a charge leg planned to end before
--       it: the charges ran a mean 42, 36, 17 and 22 minutes past their plan, and each hold kept its empty bay a mean 13-15
--       minutes until the no-show grace freed it. The reconcile (ottoq_reconcile_bay_reservations) defers a hold only while
--       the car's charge leg is planned to end later, so a charge past its plan is invisible to it. 0744 (PENDING) blocks
--       such a hold one service length ahead under dial bay_hold_follows_charge.
--   (b) The calendar seats all or none (query (24), G457). ottoq_activate_due_bay_reservations seats the due reservations
--       in one block whose handler returns 0 on any error. A car just off its charger is ready for its bay while the arm
--       still holds it, and moving it trips the arm interlock. Reproduced on live at 5:07 PM CT in a transaction rolled
--       back: car A held by the arm and car B staged and ready, each with a wash reservation in its window and its bay
--       empty; the call seated 0; with A's arm released it seated both (tests/test_bay_activation_per_seat_sql.py repeats it
--       on the live bodies). A car whose charge ended at a tick held a live bay booking in 36, 38, 50 and 45 of 144 ticks
--       on arms 83, 86, 84 and 85, and on arms 84 and 85 no calendar seat fell in any of them. 9 of the 34 no-shows had
--       their car idle in the depot at its slot, but most of their ticks had no held car, so other errors also end the
--       call, and the server log is all they leave. 0743 (PENDING) seats each car on its own under dial
--       bay_activation_per_seat and records each refusal, so its arm will say what they are.
--   The calendar seats few cars at all (3-10 a run; the staged path seats most), so expect (b) to matter less than (a).
--
--   What it means for the conversion (§10 point 2). Posts 21-40 earned about half what posts 11-20 did, and the wash line
--   is part of why. Both measured causes are engine fixes, not capacity. A fourth wash bay is a build-out the twin cannot
--   yet express: ottoq_site_buildout_apply converts L2 spaces to fast chargers and nothing else.
--
--   And the bay line's order, corrected (query (25), G453). On arm 82 (busy day) the staged needs-card path, decide
--   section (4b), made 10 service-bay seats, and each passed over a car that had waited longer: a mean 18.8 such cars,
--   the longest a mean 292 minutes. It ranks by urgency, then time to deploy, then shortest open work, with no term for
--   time waited, and on busy_day's compressed intervals the critical and overdue cars alone fill the two bays. The
--   first-come path, section (5), seated 13, 5 of them over a longer wait. Normal days: 0-1 such seats in 6-8. busy_day
--   without its compression is not a busy day: 88 of arm 82's 164 recalls were service_interval_due, and the other 76
--   are a lighter day than normal_day's 148. So a realistic busy day needs an assumption about demand, which is Chase's.

-- ══ §14 THE PLAN CHARGES ON A CHARGER THE DEPOT MAY NOT HAVE (G459; G458 traced further; reproduce: (26)-(28)) ═══════
--
--   Read 2026-10-17 between 5:42 and 6:07 PM CT from last night's normal-day arms (seed 1, 12 hours) and arm 82.
--
--   G458's "empty bay, no booking, cars waiting" ticks are mostly refused walk-ins (query (26)). The waiting cars there
--   were chiefly waiting for an interior deep clean, which this depot does on its wash bays (it has no detail bay). On arm
--   84 the needs-card path, decide section (4b), asked for a wash bay 146 times for 25 cars and was told there was no
--   free space: it needs the bay free for the whole job, [now, now + 25 minutes) for a deep clean. In 96 of the 146 a bay
--   was held only by reservations whose car never came; in 9 only by the asking car's own reservation, which the walk-in
--   path cannot use (it honours a hold only through a planned leg with no stall, and a reserved leg has one); in 41 the
--   final booking rows show no blocker, and in the one traced (7:15 AM CT, NASH-WSH-03) the blockers were two holds the
--   reconcile moved five minutes later (its log, bay_reservation_reconcile_2026_08_02, keeps the old windows). On arms
--   86, 83 and 82: 52, 11 and 17 refusals. The lane's staff cap also binds (query (29)): section (4b) admits to the wash
--   lane only up to LEAST(the bays, the depot's wash supervisors) and passes over every candidate silently once that is
--   reached, and this depot has two supervisors for three bays (ottoq_depot_staffing). On arm 84, in 51 five-minute
--   ticks (about 4 h 15 min of the 12-hour day, 7:30 AM to 5:40 PM CT) two bays were washing, a mean 3.5 cars stood
--   staged waiting for a wash or deep clean, and no walk-in was tried; as built (arm 83) 26 ticks and 1.6 cars. What a
--   third supervisor buys is a staffing question for Chase, and the twin can answer it with a run-scoped override of the
--   lane's headcount (proposed, not built: the decide reads the depot's staffing table, which no run can change).
--
--   Most of those reservations were booked behind a charge the depot cannot give (query (27), G459). The itinerary
--   planner (public.ottoq_plan_visit_itinerary) chooses a fast charge at 100 kW below 45% and an L2 at 11 kW above it,
--   whatever the depot has. On arm 84 (no L2) it planned 127 L2 legs for 93 cars, a mean 232 minutes long; 124 were skipped, and
--   each ended a mean 219 minutes after the car's real charge (median 232; arms 85, 86 and 83: 224, 237 and 218). The
--   forward calendar books bay holds from those legs. The reconcile reads an unstarted charge leg as a charge under way
--   (BLOCKER 1) and deferred the holds of cars standing in staging while such a leg was planned: 3, 5, 6 and 4 holds on
--   arms 83, 84, 85 and 86, a mean 88, 88, 84 and 95 minutes, and 16 on arm 82 (163 minutes). For 23 of the 34 the leg
--   was one the depot never served; for the other 11 a real charge came after.
--
--   Rehearsed out of sample on every charge to full (query (28); the clock's fit 11 is of 2026-10-14, and the rehearsal
--   leaves out the run's own charges, which the plan adds). Planning the kind the car can use at the depot, timed on the
--   learned clock, gets the kind right on all 234 of arm 84's charges (the rule 39.7%) and misses the length by a mean
--   7.9 minutes (the rule 63.0; p90 19.6 against 172.8); arm 85, 8.1 against 61.2. As built (arm 83, 172 charges) the
--   kind is the rule's, right 64.5%, and the clock still cuts the miss 69.5 → 52.0 (arm 86: 67.4 → 43.1). The faster
--   kind on the clock would be right only 48.8% as built, though 69.0% at 20 posts against the rule's 57.5%: which kind
--   a car gets at a mixed depot depends on the mix and the queue, which a plan made at arrival cannot see. With the kind
--   known the clock misses by 14.7 minutes as built and 9.8 at 20 posts. 0745 (PENDING) makes the change that holds on
--   every mix measured, under dial itinerary_charge_on_clock, with arms paired to 84 and 83.

-- ══ §15 THE NIGHT'S ARMS: THE FIRST READING, THE TICK AND THE COMMAND LAG (G448-G450; reproduce: (3b), (12), (30)) ══
--
--   Read 2026-10-18 between 1:38 and 2:18 AM CT from the seven arms the runner finished from 11:38 PM to 1:55 AM CT
--   (arms 89-95, all complete, none errored). Seed 1 throughout, so each pair is one reading.
--
--   0733, the first reading (arm 89 against arm 85: the normal day, forty posts behind 2.4 MW of shared cabinets held at
--   2.16 MW, 0729's managed reading). EN.001's refused starts fell from 85 to 0 (query (3b) on the sweeps
--   dcfc40_managed_normal and firstreading_normal). All 85 had come with the meter itself over the held cap, 2,182-2,285
--   kW against 2,160, and 84 of them before 7 AM CT. The pool bound in 4 ticks against 1. The day barely moved: 211 cars
--   served against 207, 946.8 deployed car-hours against 941.8, the charge wait's p50 and p95 10 and 90 minutes on both,
--   7 of 74 due cars on time against 4 of 66, and every car left at 100% with nothing open on both. So every refusal of
--   G448's kind was the twin's first reading, and a held site loses nothing to the shield once its meter reads what a
--   site controller gives a car it has just connected.
--
--   0734 and 0735 over the same 6-hour morning at ten posts:
--                                          arm 91          arm 90          arm 92
--                                          5 min, lag      2.5 min, lag    5 min, in tick
--     command lag, all executed (min)      5.00            2.50            0.00
--     wash seat of its booking (min)       12.00 of 17.00  15.39 of 17.89  17.22 of 17.22
--     service seat of its booking (min)    38.00 of 43.00  31.90 of 34.40  43.00 of 43.00
--     handovers with a car waiting         28              32              29
--       taking exactly the lag's gap       27 at 10.0      31 at 5.0       27 at 5.0
--       charger-hours idle in them         4.8             2.8             2.7
--     cars served (visits)                 58 (90)         61 (91)         60 (89)
--     deployed car-hours (of 514)          392.3           403.0           412.9
--     charge wait p50, p95 floor (min)     30.0, 144.0     17.5, 144.1     5.0, 125.0
--     wall time (s)                        406.6           1,498.5         404.8
--   A handover here is a gap of 15 minutes or less between two sessions on one fast charger while a car waits for one
--   (query (30)). A longer gap is a fault or a car not yet ready, one or two an arm (a connector-cable fault left a
--   charger idle 3.2 hours on arm 90, an aborted session 3.4 hours on arm 92), and is left out. Halving the tick bought
--   10.7 car-hours over the morning (+2.7%) for 3.7 times the wall time; answering in the tick bought 20.6 (+5.3%) for
--   none. Most of the charge wait's median was the lag itself: a car seated on a charger plugged in a tick later.
--
--   0735 on the normal day (12 hours), against last night's arms on the same seed:
--                                          10 posts          20 posts          40 posts
--                                          83 -> 93          86 -> 94          84 -> 95
--     command lag (min)                    5.00 -> 0.00      5.00 -> 0.00      5.00 -> 0.00
--     wash seat of its booking (min)       12.64 -> 16.90    12.67 -> 17.32    13.05 -> 18.14
--       (booked)                           (17.64 -> 16.90)  (17.67 -> 17.32)  (18.05 -> 18.14)
--     handovers with a car waiting         63 -> 69          not readable: query (10) reads a converted post as L2
--       charger-hours idle in them         10.9 -> 6.6
--     cars served                          148 -> 159        175 -> 177        215 -> 205
--     deployed car-hours (of 1,114)        821.4 -> 832.1    879.8 -> 909.0    942.7 -> 940.5
--     unmet ride demand                    26.3% -> 25.3%    21.0% -> 18.4%    15.4% -> 15.6%
--     door p95 (min)                       428 -> 378        305 -> 325        248 -> 274
--     charge wait p50 (min)                10 -> 5           10 -> 5           10 -> 5
--     charge wait p95 floor (min)          125 -> 110.5      105 -> 95         82.5 -> 72.5
--     due cars on time                     6 of 54 -> 3/42   5 of 59 -> 2/53   8 of 72 -> 4/65
--   Every car left at 100% with nothing open on all six. On-time is a handful either way (§12), and a bay seat now runs
--   its booked length, so a due car with bay work leaves later than it did. At ten posts the due cars are the OTA wave's
--   recalls (J_ota_wave, 65 and 53 of the due visits); about half began on an L2 in both arms (35 of 63 and 26 of 54
--   on a fast charger, against 41.5% and 42.7% of the others: G277's ordering question, under 0548's test), and in tick
--   their charge ran a mean 116 minutes against 107 as the fast chargers ran busier (76% against 69%).
--
--   What it changes. The lag had two costs in opposite directions (G450), and they fell on different post counts. Ten
--   and twenty posts queue for chargers and lost each handover's second tick: removing it bought them 10.7 and 29.2
--   car-hours. Forty posts do not queue (41% busy) and are wash-bound (§13), and the lag gave them wash seats a tick
--   short: removing it cost them 2.2. So in tick the curve bends harder: posts 11-20 bought 7.7 car-hours each in the
--   12-hour day, and posts 21-40 bought 1.6 (§10 point 2 had 5.8 and 3.1, and called 5.8 an upper bound; it was not).
--   Forty posts served 29% more cars than as built, not 45%. One seed, and the seeds that would give these a spread
--   (0732's) have not run.
--
--   And G449's first-tick candidate is not built. With 0735 a handover takes one tick, and at ten posts the normal day
--   left 6.6 charger-hours idle with a car waiting, against 94.4 hours of fast charging. Stamping the moment a pack
--   filled would save about 3 of a handover's remaining 7.5 minutes (G449's arithmetic), about 3.5 charger-hours a day
--   here. Halving the tick saved 2.0 of the morning's such hours, among its other effects, and bought 10.7 car-hours.
--   It stays the candidate if the seeds show the curve needs it.

-- ══ §16 UNDER THE LAG, THE TWIN'S SITE METER COUNTS EACH NEW CHARGE'S FIRST INTERVAL TWICE (G468; reproduce: (31), (32)) ══
--
--   Found reading §15's energy: in tick the depot imported 6.5-17.5% less while its cars took more. The sessions
--   delivered 7,429 kWh against 7,002 at ten posts, 8,009 against 7,772 at twenty and 8,629 against 8,425 at forty; the
--   battery's charge and the fleet's end charge moved under 1%; and the grid read 6,284 kWh against 6,723, 6,888 against
--   7,912 and 7,579 against 9,193. That is the meter, not the cars (query (31)). Integrated as ottoq_dial_arm_metrics
--   integrates it (each snapshot held until the next), the twin's EV load, site_energy_snapshots.total_ev_charging_kw,
--   against what the sessions delivered:
--     5 minutes, lag:     +11.7% (arm 83, ten posts), +12.0% (91, the morning), +15.6% (86, twenty), +20.2% (84, forty),
--                         +20.1% (85, forty held), +18.0% (89, held, with 0733)
--     2.5 minutes, lag:   +6.0% (90)
--     in tick (0735):     -0.6% (92), -0.7% (93), -0.8% (94), -1.5% (95)
--   The chargers' own readings (OCPP TransactionEvent Updated, Power.Active.Import, one a tick) agree with the sessions to
--   within 1% on all eleven arms, lagged or not: 7,024 against 7,002 kWh on arm 83, 8,503 against 8,425 on arm 84,
--   7,457 against 7,429 on arm 93, 8,708 against 8,629 on arm 95. On a tick when no session starts or ends the meter
--   equals the sum of that tick's readings exactly, on all eleven; all of arm 83's excess, 10,124 kW-ticks or a mean
--   45.4 kW for each of its 223 starts, falls on ticks when one does.
--
--   The order of a tick says why (function sources). ottoq_sim_advance_tick_world carries out the last tick's commands
--   (ottoq_sim_confirm_commands), starts the sessions of the cars now plugged in (ottoq_sim_reconcile_charge_sessions),
--   meters each running session's last interval (ottoq_sim_advance_charge_sessions, which skips a session in the tick it
--   starts) and then snapshots the site (ottoq_sim_advance_all_energy, then twin.ottoq_sim_advance_site_energy), summing
--   every session's last reading with started_at <= now (twin.ottoq_sim_compute_charger_load_kw). So a session started in
--   the world is in the snapshot at its first reading, the rate it is about to charge at, and a tick later at its reading
--   for that same interval: N + 1 snapshots for N intervals. With 0735 the session starts after the decide
--   (twin.ottoq_sim_answer_in_tick), after the snapshot, so it is in N of them, and the load curve sits a tick late,
--   which moves no total.
--
--   What it changes. Every arm before tonight ran with the lag, so every energy, grid, cost and peak figure in §2-§4, §10
--   and §11 is read from an over-metered snapshot. Recomputed on the chargers' readings (query (32)), full half hours:
--                              grid kWh            whole-day half hour (kW)   half hour from 180 min (kW)
--     ten posts, arm 83        6,669 -> 5,887      973.8 -> 935.8             713.6 -> 658.0
--     twenty, arm 86           7,840 -> 6,740      1,693.1 -> 1,660.8         932.5 -> 821.3
--     forty, arm 84            9,111 -> 7,589      2,369.5 -> 2,188.8         941.8 -> 797.1
--     in tick, arms 93-95      the meter and the readings within 1.8% on every column
--   The lagged arms' battery planned on the over-metered meter, which no recomputation undoes, so quote the in-tick arms.
--   On them the depot is busier than the lagged arms' readings: with each handover a tick shorter more cars charge at
--   once, and the half hour billed from 180 minutes reads 800.2 kW at ten posts, 924.3 at twenty and 940.6 at forty
--   (§10 point 4's dollars, corrected there). The opening draw at forty is 3.7 MW on the chargers' readings (3,731 kW on
--   arm 84, 3,749 in tick on arm 95), not §10 point 3's 3.9; the meter's 3,874 counted some first intervals twice.
--
--   A twin fidelity defect, not a production one: a real site meter reads the power that flows. Anything in the twin that
--   reads the snapshot while it decides read the phantom on a lagged arm; which readers those are is not traced here.
--   Not built: 0735 removes it, so a cell that measures energy, a peak or a bill runs with twin_answer_in_tick on. The
--   cells queued behind tonight's (billwindow_normal, byneed_normal, seeds23_normal and the older dcfc40 sweeps) run with
--   the lag: their pairs compare like with like, and their energy and bills carry this.

-- ══ §17 A HALF HOUR AT THE DAY'S END CAN BE ONE TICK (G469; reproduce: (33)) ═══════════════════════════════════════════
--
--   ottoq_dial_arm_metrics takes the demand peak as the highest mean over [t, t + 30 minutes) for every snapshot t
--   (0439: "the NES NCP_30min basis (highest 30-consecutive-minute mean of grid import)"), and at the end of a run that
--   window holds what is left of it: one, two or three samples. Of the 69 arms that carry peak_after_open, 8 have their
--   half hour billed from 180 minutes start in the run's last half hour (query (33)): arms 35, 42, 58 and 62
--   (value_2026_09_30's 24-hour days, starting at minute 1,430-1,435 of 1,440) and arms 84, 89, 94 and 95 (minute 715-720
--   of 720). Over full half hours the first four read 695.2, 695.2, 688.9 and 694.6 kW against 710.9, 710.9, 694.4 and
--   699.4 (0.7-2.2% lower), and the last four 941.8, 1,150.8, 924.3 and 940.6 against 1,006.8, 1,241.9, 980.7 and 976.5
--   (3.7-7.3% lower). The whole-day half hour is never partial: the opening sets it on all 69. So arm 84's $21,547 past
--   the opening in §10 point 4 is two samples, and $20,155 over full half hours before §16's correction.
--   A five-minute window is not a 30-consecutive-minute mean. Built as 0754 (PENDING): a half hour counts only when its
--   window holds 30 minutes of samples, for every arm scored after it lands; stored arms keep their numbers, and query (33)
--   recomputes any arm whose run is still on record.

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
 WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17', 'dcfc40_power_normal_2026_10_17',
                        'dcfc40_power_busy_2026_10_17', 'dcfc40_managed_normal_2026_10_17', 'dcfc20_normal_2026_10_17',
                        'billwindow_normal_2026_10_17')
 ORDER BY a.ran_at;

-- (3b) EN.001's refused starts per arm, the meter and request they were judged on, and the ticks the DC pool bound
WITH arms AS (
  SELECT a.arm_id, a.sim_run_id, c.cell_code
    FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c USING (cell_id)
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE s.sweep_code IN ('dcfc40_2026_10_17', 'dcfc40_normal_2026_10_17', 'dcfc40_power_normal_2026_10_17',
                          'dcfc40_power_busy_2026_10_17', 'dcfc40_managed_normal_2026_10_17', 'dcfc20_normal_2026_10_17',
                          'billwindow_normal_2026_10_17')),
refused AS (
  SELECT a.arm_id, count(*) AS refused_starts,
         count(*) FILTER (WHERE extract(hour FROM (e.context ->> 'now_ts')::timestamptz AT TIME ZONE 'America/Chicago') < 7)
           AS before_7am_ct,
         count(*) FILTER (WHERE (e.result_payload ->> 'current_kw')::numeric
                                 <= (e.result_payload ->> 'engineering_cap_kw')::numeric) AS meter_under_cap,
         round(min((e.result_payload ->> 'current_kw')::numeric), 1) AS meter_min_kw,
         round(max((e.result_payload ->> 'current_kw')::numeric), 1) AS meter_max_kw,
         round(avg((e.result_payload ->> 'requested_kw')::numeric)) AS mean_request_kw,
         max((e.result_payload ->> 'engineering_cap_kw')::numeric) AS cap_kw
    FROM arms a JOIN public.ottoq_rule_evaluations e ON e.sim_run_id = a.sim_run_id
   WHERE e.rule_code = 'EN.001.grid_capacity_ceiling' AND e.action_context = 'charge_session_start' AND NOT e.passed
   GROUP BY 1),
pool AS (
  SELECT a.arm_id, count(DISTINCT v.sim_clock_at) AS pool_bound_ticks
    FROM arms a JOIN public.ottoq_events v ON v.sim_run_id = a.sim_run_id AND v.event_type = 'twin.dc_pool_shared'
   GROUP BY 1)
SELECT a.arm_id, a.cell_code, COALESCE(r.refused_starts, 0) AS en001_refused_starts, r.before_7am_ct, r.meter_under_cap,
       r.meter_min_kw, r.meter_max_kw, r.mean_request_kw, r.cap_kw, COALESCE(p.pool_bound_ticks, 0) AS pool_bound_ticks
  FROM arms a LEFT JOIN refused r USING (arm_id) LEFT JOIN pool p USING (arm_id)
 ORDER BY a.arm_id;

-- (3c) a shared arm's opening, tick by tick: sessions started, and the metered power of the running ones (G448). Read
--      the stall type from the frames or the scorecard, not by joining stalls: the build-out is restored when the arm
--      ends, so a converted post joined afterwards reads as the 19.2 kW L2 it was (18 of these 24 do).
SELECT to_char(o.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS sim_ct,
       count(*) FILTER (WHERE o.payload ->> 'eventType' = 'Started') AS started,
       count(*) FILTER (WHERE o.payload ->> 'eventType' = 'Updated') AS metered,
       round(sum((SELECT (x ->> 'value')::numeric FROM jsonb_array_elements(o.payload -> 'meterValue' -> 0 -> 'sampledValue') x
                   WHERE x ->> 'measurand' = 'Power.Active.Import'))
             FILTER (WHERE o.payload ->> 'eventType' = 'Updated'), 1) AS metered_kw
  FROM public.ottoq_ocpp_messages o
 WHERE o.sim_run_id = 'fe6d540e-860f-4057-8edf-7d6257b94bff' AND o.message_type = 'TransactionEvent'
   AND (o.sim_clock_at AT TIME ZONE 'America/Chicago')::time < time '07:00'
 GROUP BY o.sim_clock_at ORDER BY o.sim_clock_at;

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

-- (9) the battery plan, per tick, on a run (G447)
SELECT c.tick_seq, to_char(c.issued_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS sim_ct, round(c.setpoint_kw) AS setpoint_kw,
       c.reason -> 'day_plan' ->> 'mode' AS mode, round((c.reason -> 'day_plan' ->> 'ratchet_kw')::numeric) AS billed_peak_kw,
       round((c.reason -> 'day_plan' ->> 'level_kw')::numeric) AS level_kw, c.reason -> 'day_plan' ->> 'charge_reason' AS charge_reason
  FROM public.ottoq_energy_commands c
 WHERE c.sim_run_id = 'b54f6de5-7cf3-4d91-a0d1-0010a21fec64' AND c.command_type = 'bess_setpoint_kw'
 ORDER BY c.tick_seq;

-- (10) fast-charger handovers on a run with a car waiting for a fast charger, and the charger time they left idle (G449)
WITH s AS (
  SELECT x.stall_id, x.started_at, x.ended_at,
         lead(x.started_at) OVER (PARTITION BY x.stall_id ORDER BY x.started_at) AS next_start
    FROM public.ocpp_sessions x JOIN public.stalls st ON st.id = x.stall_id
   WHERE x.sim_run_id = 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd' AND st.stall_type::text = 'dcfc'
     AND x.started_at IS NOT NULL AND x.ended_at IS NOT NULL),
fc_first AS (
  SELECT vn.arrived_at, f.started_at AS first_start
    FROM public.ottoq_visit_needs vn
    JOIN LATERAL (SELECT y.started_at, sty.stall_type::text AS t FROM public.ocpp_sessions y JOIN public.stalls sty ON sty.id = y.stall_id
                   WHERE y.sim_run_id = vn.sim_run_id AND y.vehicle_id = vn.vehicle_id AND y.started_at >= vn.arrived_at
                   ORDER BY y.started_at LIMIT 1) f ON f.t = 'dcfc'
   WHERE vn.sim_run_id = 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'),
g AS (SELECT s.*, extract(epoch FROM (s.next_start - s.ended_at)) / 60.0 AS gap_min,
             (SELECT count(*) FROM fc_first f WHERE f.arrived_at <= s.ended_at AND f.first_start > s.ended_at) AS fc_waiting
        FROM s WHERE s.next_start IS NOT NULL)
SELECT count(*) AS handovers, count(*) FILTER (WHERE fc_waiting > 0) AS with_a_car_waiting,
       count(*) FILTER (WHERE fc_waiting > 0 AND gap_min = 10) AS exactly_10_min,
       min(gap_min) FILTER (WHERE fc_waiting > 0) AS shortest_min,
       round(sum(gap_min) FILTER (WHERE fc_waiting > 0)::numeric / 60, 1) AS idle_charger_hours,
       (SELECT round(sum(extract(epoch FROM (s.ended_at - s.started_at)) / 3600)::numeric, 1) FROM s) AS charging_hours_all
  FROM g;
-- Stall types are read from stalls, so run this on an arm whose build-out converts nothing (dcfc10): a converted post
-- reads as the L2 it is restored to (query (3c)'s note).

-- (11) immediate dispatches on a run: the due, the wait, the charge alone, and how many the charge alone made late (G383)
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes('b54f6de5-7cf3-4d91-a0d1-0010a21fec64')),
d AS (
  SELECT o.on_time, vn.urgency, extract(epoch FROM (vn.dispatch_due_at - vn.arrived_at)) / 60.0 AS due_min,
         cs.soc_start, extract(epoch FROM (cs.started_at - vn.arrived_at)) / 60.0 AS wait_min,
         extract(epoch FROM (cs.ended_at - cs.started_at)) / 60.0 AS charge_min
    FROM o JOIN public.ottoq_visit_needs vn USING (visit_id)
    LEFT JOIN LATERAL (SELECT x.* FROM public.ocpp_sessions x
                        WHERE x.sim_run_id = vn.sim_run_id AND x.vehicle_id = vn.vehicle_id AND x.started_at >= vn.arrived_at
                          AND x.started_at < COALESCE(o.departed_at, vn.arrived_at + interval '1 day')
                        ORDER BY x.started_at LIMIT 1) cs ON true
   WHERE vn.dispatch_due_at IS NOT NULL AND o.departed_at IS NOT NULL)
SELECT urgency, count(*) AS served, count(*) FILTER (WHERE on_time) AS on_time, min(due_min) AS due_min_lo, max(due_min) AS due_min_hi,
       count(*) FILTER (WHERE charge_min IS NOT NULL) AS charged,
       count(*) FILTER (WHERE charge_min > due_min) AS charge_alone_over_the_due,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY charge_min)::numeric, 1) AS charge_p50_min,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_start)::numeric, 1) AS soc_at_plug_p50,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY wait_min)::numeric, 1) AS wait_p50_min
  FROM d GROUP BY urgency;

-- (12) the twin's command lag on a run, and what it does to bay seats (G449, G450). On arm 83: every command 5.00
--      minutes late; washes seated 12.64 of 17.64 booked minutes, services 37.86 of 42.86. Under 0735's dial both
--      lags should read 0.00 and a seat its booking.
WITH c AS (
  SELECT c.command_type, c.issued_at, c.confirmed_at, c.payload
    FROM public.ottoq_vehicle_commands c
   WHERE c.sim_run_id = 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd' AND c.status = 'executed')
SELECT 'command lag' AS what, c.command_type AS k, count(*) AS n,
       round(avg(extract(epoch FROM c.confirmed_at - c.issued_at) / 60.0), 2) AS mean_late_min,
       NULL::numeric AS booked_min, NULL::numeric AS seated_min
  FROM c GROUP BY c.command_type
UNION ALL
SELECT 'bay seat', c.command_type, count(*),
       round(avg(extract(epoch FROM c.confirmed_at - lower(b.during)) / 60.0), 2),
       round(avg(extract(epoch FROM upper(b.during) - lower(b.during)) / 60.0), 2),
       round(avg(extract(epoch FROM upper(b.during) - c.confirmed_at) / 60.0), 2)
  FROM c JOIN public.ottoq_stall_bookings b ON b.booking_id = NULLIF(c.payload ->> 'booking_id', '')::uuid
 WHERE c.command_type IN ('enter_wash', 'enter_service')
 GROUP BY c.command_type
 ORDER BY 1, 2;

-- (13) the promises on a run, graded (G383, 0736): the share ready by the median and by the 90th percentile, overall, by
--      situation, by bay work and by whether the after-charge part came from the run's own cars or the prior; and for
--      visits with an owner's due, the share ready by the due against the share ready by the promise. Run it on the
--      promise arm (sweep promise_normal_2026_10_17) once it has run.
SELECT public.ottoq_ready_promise_grade(a.sim_run_id) AS grade
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
 WHERE s.sweep_code = 'promise_normal_2026_10_17'
 ORDER BY a.ran_at DESC LIMIT 1;

-- (14) the promise's after-charge part rehearsed on a run's own visits (G452): at each even hour, what 0736 learned
--      (finished cars only), what 0739 learns (Kaplan-Meier, the cars still waiting counted), and what the cars whose
--      charge closed in the next hour took (of those ready before the run ended; never_ready says how many were not).
--      Bay work only, where the difference lives. On arm 81 at hour 8: 33, 255 and 395. Substitute the run.
WITH r AS (SELECT sim_run_id, sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = '96616822-7d95-4b09-9320-48988d60616b'),
v AS (
  SELECT vn.sim_run_id, r.sim_clock_start AS t0,
         (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) x
           WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' LIMIT 1) AS ready_at,
         (SELECT max(COALESCE((x ->> 'closed_at')::timestamptz, (x ->> 'done_at')::timestamptz))
            FROM jsonb_array_elements(vn.atoms) x WHERE x ->> 'svc' = 'charge' AND x ->> 'status' = 'done') AS chg_at
    FROM public.ottoq_visit_needs vn JOIN r USING (sim_run_id)
   WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x ->> 'concurrency' = 'bay')),
t AS (SELECT DISTINCT sim_run_id, t0, t0 + make_interval(hours => h) AS t FROM v CROSS JOIN generate_series(2, 10, 2) h),
g AS (
  SELECT t.t0, t.t,
         array_agg(extract(epoch FROM (LEAST(COALESCE(v.ready_at, 'infinity'), t.t) - v.chg_at)) / 60 ORDER BY v.chg_at)
           FILTER (WHERE v.chg_at <= t.t) AS xs,
         array_agg(COALESCE(v.ready_at <= t.t, false) ORDER BY v.chg_at) FILTER (WHERE v.chg_at <= t.t) AS evs,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (v.ready_at - v.chg_at)) / 60)
           FILTER (WHERE v.chg_at <= t.t AND v.ready_at <= t.t) AS finished_only,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (v.ready_at - v.chg_at)) / 60)
           FILTER (WHERE v.chg_at > t.t AND v.chg_at <= t.t + interval '1 hour' AND v.ready_at IS NOT NULL) AS next_hour,
         count(*) FILTER (WHERE v.chg_at > t.t AND v.chg_at <= t.t + interval '1 hour' AND v.ready_at IS NULL) AS never_ready
    FROM t JOIN v ON v.sim_run_id = t.sim_run_id GROUP BY 1, 2)
SELECT extract(epoch FROM t - t0) / 3600 AS hour, cardinality(xs) AS cars, (SELECT count(*) FROM unnest(evs) e WHERE NOT e) AS waiting,
       round(finished_only::numeric, 0) AS said_0736,
       round((public.ottoq_km_quantiles(xs, evs, ARRAY[0.5]::float8[]))[1]::numeric, 0) AS kaplan_meier_0739,
       round(next_hour::numeric, 0) AS next_hour_took, never_ready
  FROM g ORDER BY 1;

-- (15) a busy day's service bays (G453): bookings by state and release reason, with each booking's lead from booked to
--      slot, and how many slots fell after the run's end. On arm 82: 25 served (lead 42 minutes on average), 18 released
--      when the run stopped (lead 488, 16 of them slotted after its end), 12 released replanned_no_window; arm 83 (normal
--      day) had none of the last kind.
SELECT left(b.sim_run_id::text, 8) AS run, b.state, b.release_reason, count(*) AS n,
       round(avg(extract(epoch FROM lower(b.during) - b.booked_at_sim) / 60)::numeric, 0) AS lead_avg_min,
       round(max(extract(epoch FROM lower(b.during) - b.booked_at_sim) / 60)::numeric, 0) AS lead_max_min,
       count(*) FILTER (WHERE lower(b.during) > r.sim_clock_current) AS slot_after_run_end
  FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id JOIN ottoq_sim_runs r ON r.sim_run_id = b.sim_run_id
 WHERE b.sim_run_id IN ('43301561-bce5-46c5-84c3-4235db4e4dd4', '96616822-7d95-4b09-9320-48988d60616b', 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd')
   AND s.stall_type::text = 'service_bay'
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;

-- (16) the calendar's own floor for the promise (G452, G453): for each visit with bay work, the end of the car's last bay
--      booking made in its arrival tick (its original slot, read through the reconcile log where a deferral rewrote it),
--      against when the car was ready. On the busy arms 28 of 31 and 44 of 49 booked cars that got ready were ready after
--      it, and none of the 19 booked past the run's end was ready that day; on the normal day 26 of 38.
WITH bk AS (
  SELECT b.sim_run_id, b.vehicle_id, b.booked_at_sim,
         COALESCE((SELECT r.old_to FROM public.bay_reservation_reconcile_2026_08_02 r WHERE r.booking_id = b.booking_id
                    ORDER BY r.sim_clock, r.defer_seq LIMIT 1), upper(b.during)) AS orig_end
    FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id IN ('43301561-bce5-46c5-84c3-4235db4e4dd4', '96616822-7d95-4b09-9320-48988d60616b', 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd')
     AND s.stall_type::text IN ('wash_bay', 'service_bay')),
v AS (
  SELECT vn.sim_run_id, vn.vehicle_id, vn.arrived_at,
         (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) x
           WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' LIMIT 1) AS ready_at,
         (SELECT r.sim_clock_current FROM ottoq_sim_runs r WHERE r.sim_run_id = vn.sim_run_id) AS run_end
    FROM ottoq_visit_needs vn
   WHERE vn.sim_run_id IN ('43301561-bce5-46c5-84c3-4235db4e4dd4', '96616822-7d95-4b09-9320-48988d60616b', 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x ->> 'concurrency' = 'bay')),
j AS (
  SELECT v.*, (SELECT max(bk.orig_end) FROM bk WHERE bk.sim_run_id = v.sim_run_id AND bk.vehicle_id = v.vehicle_id
                AND bk.booked_at_sim <= v.arrived_at + interval '5 minutes'
                AND bk.booked_at_sim >= v.arrived_at - interval '1 minute') AS floor_at_arrival
    FROM v)
SELECT left(sim_run_id::text, 8) AS run, count(*) AS bay_visits, count(floor_at_arrival) AS booked_at_arrival,
       count(*) FILTER (WHERE floor_at_arrival IS NOT NULL AND ready_at IS NOT NULL) AS booked_and_ready,
       count(*) FILTER (WHERE floor_at_arrival IS NOT NULL AND ready_at IS NOT NULL
                          AND ready_at >= floor_at_arrival - interval '5 minutes') AS ready_after_floor,
       count(*) FILTER (WHERE floor_at_arrival > run_end) AS floor_past_run_end,
       count(*) FILTER (WHERE floor_at_arrival > run_end AND ready_at IS NOT NULL) AS past_end_but_ready
  FROM j GROUP BY 1 ORDER BY 1;

-- (17) G453's test of the promise, on a promise arm's run: for each promised car with a bay booking made in its arrival
--      tick, its promise's p90 against that booking's original end (the calendar's floor) and against when it was ready.
--      If many booked cars were ready after the floor while their p90 sat before it, the p90 under-covers them and a
--      floor on the p90 is the next build. Substitute the sweep code (promise_normal_2026_10_17 or promise_busy_2026_10_17).
WITH run AS (SELECT a.sim_run_id FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code = 'promise_busy_2026_10_17' ORDER BY a.ran_at DESC LIMIT 1),
p AS (SELECT pr.*, (SELECT (x ->> 'done_at')::timestamptz FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
                     WHERE vn.visit_id = pr.visit_id AND x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' LIMIT 1) AS ready_at,
             (SELECT max(COALESCE((SELECT r.old_to FROM public.bay_reservation_reconcile_2026_08_02 r WHERE r.booking_id = b.booking_id
                                    ORDER BY r.sim_clock, r.defer_seq LIMIT 1), upper(b.during)))
                FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
               WHERE b.sim_run_id = pr.sim_run_id AND b.vehicle_id = pr.vehicle_id AND s.stall_type::text IN ('wash_bay', 'service_bay')
                 AND b.booked_at_sim BETWEEN pr.arrived_at - interval '1 minute' AND pr.arrived_at + interval '5 minutes') AS floor_at
        FROM public.ottoq_ready_promises pr JOIN run USING (sim_run_id))
SELECT count(*) AS promises, count(floor_at) AS booked,
       count(*) FILTER (WHERE floor_at IS NOT NULL AND ready_at IS NOT NULL) AS booked_and_ready,
       count(*) FILTER (WHERE floor_at IS NOT NULL AND ready_at IS NOT NULL AND ready_at <= ready_p90_at) AS booked_ready_by_p90,
       count(*) FILTER (WHERE floor_at IS NOT NULL AND ready_at IS NOT NULL AND ready_at >= floor_at - interval '5 minutes'
                          AND ready_p90_at < floor_at) AS p90_before_floor_but_ready_after_it,
       count(*) FILTER (WHERE floor_at IS NULL AND ready_at IS NOT NULL AND ready_at <= ready_p90_at) AS unbooked_ready_by_p90,
       count(*) FILTER (WHERE floor_at IS NULL AND ready_at IS NOT NULL) AS unbooked_and_ready
  FROM p;

-- (18) G454: what the owner app says beside the promise, on a promise arm's run (0741). The grade scores both on the
--      same cars: by_owner (ready by the app's time) against the promise's by_p50 and by_p90 on those cars, the app's
--      mean absolute error against the promise median's, the app's bias (positive: cars took longer than it said), and
--      owner_in_past (the app named a time already gone when it was read). Substitute the sweep code
--      (promise_normal_2026_10_17 or promise_busy_2026_10_17). Before a promise arm has run it returns no row.
WITH run AS (SELECT a.sim_run_id FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code = 'promise_busy_2026_10_17' ORDER BY a.ran_at DESC LIMIT 1),
g AS (SELECT public.ottoq_ready_promise_grade(run.sim_run_id) AS j FROM run)
SELECT j ->> 'promises' AS promises, j ->> 'ready' AS ready, j ->> 'with_owner' AS app_named_a_time,
       j ->> 'owner_in_past' AS app_time_already_gone,
       j ->> 'by_owner' AS ready_by_app_time, j ->> 'by_p50_with_owner' AS ready_by_p50, j ->> 'by_p90_with_owner' AS ready_by_p90,
       j ->> 'owner_mae_min' AS app_mae_min, j ->> 'mae_p50_min_with_owner' AS promise_mae_min,
       j ->> 'owner_bias_min' AS app_bias_min, j ->> 'owner_min_median' AS app_said_median_min,
       j ->> 'p50_min_median' AS promise_p50_median_min, j ->> 'actual_min_median' AS took_median_min
  FROM g;

-- (19) G455: the promise asked again part-way through a visit, rehearsed on a run's own records. At every whole hour,
--      for each car whose charge had closed and that was not yet ready: what 0739's estimator said (a visit that never
--      charged, timed from arrival, its wait subtracted from each draw) and what drawing it given the minutes since its
--      charge closed says (0742), each graded against the car's readiness check as the grade does (a car never ready is a
--      miss once its time has passed before the run's end). The two helpers read the 21-point grid; run all three
--      statements in one session. On 2026-10-17: arm 82 239 of 247 car-hours "ready now", by p50 0.000 against 0.348
--      conditional; arm 81 1,692 of 1,710, 0.000 against 0.223; arm 83 50 of 56, 0.036 against 0.625.
CREATE FUNCTION pg_temp.qat(q float8[], u float8) RETURNS float8 LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE WHEN u <= 0 THEN q[1] WHEN u >= 1 THEN q[21]
              ELSE q[floor(u*20)::int + 1] + (q[LEAST(floor(u*20)::int + 2, 21)] - q[floor(u*20)::int + 1]) * (u*20 - floor(u*20)) END $f$;
CREATE FUNCTION pg_temp.fat(q float8[], x float8) RETURNS float8 LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE WHEN x <= q[1] THEN 0 WHEN x >= q[21] THEN 1 ELSE
    (SELECT (i - 1) / 20.0 + CASE WHEN q[i+1] > q[i] THEN (x - q[i]) / (q[i+1] - q[i]) / 20.0 ELSE 0 END
       FROM generate_series(1, 20) i WHERE q[i] <= x AND x < q[i+1] ORDER BY i DESC LIMIT 1) END $f$;
WITH runs AS (
  SELECT r.sim_run_id, r.sim_clock_current AS run_end,
         (SELECT min(vn.arrived_at) FROM ottoq_visit_needs vn WHERE vn.sim_run_id = r.sim_run_id) AS run_start
    FROM ottoq_sim_runs r WHERE r.sim_run_id IN ('43301561-bce5-46c5-84c3-4235db4e4dd4','96616822-7d95-4b09-9320-48988d60616b','e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd')),
v AS (
  SELECT vn.sim_run_id, vn.visit_id, vn.vehicle_id, vn.arrived_at, vn.atoms,
         (SELECT (x->>'done_at')::timestamptz FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc'='readiness_check' AND x->>'status'='done' ORDER BY x->>'done_at' LIMIT 1) AS ready_at,
         (SELECT max(COALESCE((x->>'closed_at')::timestamptz, (x->>'done_at')::timestamptz)) FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc'='charge' AND x->>'status'='done') AS chg_at,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc'='charge') AS chg,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'concurrency'='bay') AS bay
    FROM ottoq_visit_needs vn JOIN runs USING (sim_run_id)),
t AS (SELECT r.sim_run_id, r.run_end, g AS t FROM runs r, generate_series(r.run_start + interval '1 hour', r.run_end - interval '1 hour', interval '1 hour') g),
hist AS (
  SELECT t.sim_run_id, t.t, k.key, k.x, COALESCE(v.ready_at <= t.t, false) AS ended
    FROM t JOIN v ON v.sim_run_id = t.sim_run_id AND v.arrived_at <= t.t
    CROSS JOIN LATERAL (VALUES
      (CASE WHEN v.chg AND v.chg_at <= t.t THEN CASE WHEN v.bay THEN 'after_bay' ELSE 'after_no_bay' END END,
       GREATEST(extract(epoch FROM (LEAST(COALESCE(v.ready_at, t.t), t.t) - v.chg_at))/60.0, 0)::float8),
      (CASE WHEN NOT v.chg THEN 'door_nochg_' || CASE WHEN v.bay THEN 'bay' ELSE 'no_bay' END END,
       GREATEST(extract(epoch FROM (LEAST(COALESCE(v.ready_at, t.t), t.t) - v.arrived_at))/60.0, 0)::float8)) k(key, x)
   WHERE k.key IS NOT NULL),
al0 AS (
  SELECT sim_run_id, t, key, count(*) AS n, max(x) AS xmax,
         public.ottoq_km_quantiles(array_agg(x ORDER BY x, ended), array_agg(ended ORDER BY x, ended), ARRAY(SELECT g/20.0 FROM generate_series(0,20) g)) AS q
    FROM hist GROUP BY 1,2,3),
pr AS (SELECT * FROM (VALUES ('after_no_bay',10.0,20.0),('after_bay',45.0,130.0),('door_nochg_no_bay',40.0,55.0),('door_nochg_bay',75.0,95.0)) p(key,p50,p90)),
z AS (SELECT ARRAY[-2.326,-1.645,-1.282,-1.036,-0.842,-0.674,-0.524,-0.385,-0.253,-0.126,0,0.126,0.253,0.385,0.524,0.674,0.842,1.036,1.282,1.645,2.326]::float8[] AS c_z),
al2 AS (SELECT tt.sim_run_id, tt.t, p.key,
               COALESCE((SELECT CASE WHEN a.n >= 8 THEN ARRAY(SELECT COALESCE(a.q[i], GREATEST(a.xmax, p.p50 * exp(ln(p.p90/p.p50)/1.2816*z.c_z[i]))) FROM generate_series(1,21) i ORDER BY i) END
                           FROM al0 a WHERE a.sim_run_id = tt.sim_run_id AND a.t = tt.t AND a.key = p.key),
                        ARRAY(SELECT p.p50 * exp(ln(p.p90/p.p50)/1.2816*z.c_z[i]) FROM generate_series(1,21) i ORDER BY i)) AS q
          FROM (SELECT DISTINCT sim_run_id, t FROM t) tt CROSS JOIN pr p CROSS JOIN z),
w AS (
  SELECT t.sim_run_id, t.t, t.run_end, v.vehicle_id, v.ready_at,
         extract(epoch FROM (t.t - v.chg_at))/60.0 AS e, extract(epoch FROM (t.t - v.arrived_at))/60.0 AS el_door,
         CASE WHEN v.bay THEN 'after_bay' ELSE 'after_no_bay' END AS key_after,
         CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v.atoms) x WHERE x->>'concurrency'='bay'
                            AND (x->>'status' IS DISTINCT FROM 'done' OR (x->>'done_at')::timestamptz > t.t)) THEN 'door_nochg_bay' ELSE 'door_nochg_no_bay' END AS key_door
    FROM t JOIN v ON v.sim_run_id = t.sim_run_id
   WHERE v.chg AND v.chg_at <= t.t AND (v.ready_at IS NULL OR v.ready_at > t.t)),
est AS (
  SELECT w.*, extract(epoch FROM (w.ready_at - w.t))/60.0 AS actual,
         GREATEST(pg_temp.qat(d.q, 0.5) - w.el_door, 0) AS cur50, GREATEST(pg_temp.qat(d.q, 0.9) - w.el_door, 0) AS cur90,
         pg_temp.fat(a.q, w.e) AS fe, a.q AS qa
    FROM w JOIN al2 a ON a.sim_run_id = w.sim_run_id AND a.t = w.t AND a.key = w.key_after
           JOIN al2 d ON d.sim_run_id = w.sim_run_id AND d.t = w.t AND d.key = w.key_door),
est2 AS (
  SELECT est.*, GREATEST(pg_temp.qat(qa, fe + 0.5*(1-fe)) - e, 0) AS cond50, GREATEST(pg_temp.qat(qa, fe + 0.9*(1-fe)) - e, 0) AS cond90,
         extract(epoch FROM (run_end - t))/60.0 AS left_min
    FROM est)
SELECT left(sim_run_id::text, 8) AS run, count(*) AS car_hours_waiting, count(actual) AS later_ready,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual)::numeric) AS actual_rest_p50_min,
       count(*) FILTER (WHERE cur50 = 0) AS before_0742_ready_now,
       round(avg(CASE WHEN actual IS NOT NULL THEN (actual <= cur50)::int WHEN cur50 < left_min THEN 0 END)::numeric, 3) AS before_by_p50,
       round(avg(CASE WHEN actual IS NOT NULL THEN (actual <= cur90)::int WHEN cur90 < left_min THEN 0 END)::numeric, 3) AS before_by_p90,
       round(avg(CASE WHEN actual IS NOT NULL THEN (actual <= cond50)::int WHEN cond50 < left_min THEN 0 END)::numeric, 3) AS cond_by_p50,
       round(avg(CASE WHEN actual IS NOT NULL THEN (actual <= cond90)::int WHEN cond90 < left_min THEN 0 END)::numeric, 3) AS cond_by_p90,
       round(avg(abs(actual - cur50))::numeric, 1) AS before_mae, round(avg(abs(actual - cond50))::numeric, 1) AS cond_mae
  FROM est2 GROUP BY 1 ORDER BY 1;

-- (20) G455: the second look, on a promise arm's run (0742): each re-estimate made every 30 sim-minutes against the
--      readiness check, overall, by situation and by time since arrival, with the owner app's time at the same moment.
--      Substitute the sweep code (promise_normal_2026_10_17 or promise_busy_2026_10_17). Before a promise arm has run it
--      returns no row.
WITH run AS (SELECT a.sim_run_id FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
              WHERE s.sweep_code = 'promise_normal_2026_10_17' ORDER BY a.ran_at DESC LIMIT 1)
SELECT public.ottoq_ready_promise_update_grade(run.sim_run_id) FROM run;

-- (21) G458: the wash line at 10, 20 and 40 posts. For each wash seat after a charge, the minutes from the charge's end to
--      the seat; then, every hour CT, the cars waiting (charge ended, not yet seated) beside the cars washing.
WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid, 85)),
w AS (SELECT r.arm, r.run, b.vehicle_id, lower(b.during) AS seat_at, upper(b.during) AS seat_end
        FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run JOIN public.stalls s ON s.id = b.stall_id
       WHERE s.stall_type = 'wash_bay' AND b.state IN ('done', 'active', 'interrupted') AND b.booked_by LIKE 'otto_q%'),
x AS (SELECT w.*, (SELECT max(o.ended_at) FROM public.ocpp_sessions o
                    WHERE o.vehicle_id = w.vehicle_id AND o.sim_run_id = w.run AND o.ended_at <= w.seat_at) AS charge_end
        FROM w)
SELECT arm, count(*) AS wash_seats, count(charge_end) AS after_charge,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM seat_at - charge_end) / 60) AS p50_min,
       percentile_cont(0.9) WITHIN GROUP (ORDER BY extract(epoch FROM seat_at - charge_end) / 60) AS p90_min,
       round(max(extract(epoch FROM seat_at - charge_end) / 60)::numeric, 1) AS longest_min,
       round(avg(extract(epoch FROM seat_end - seat_at) / 60)::numeric, 1) AS booked_wash_min
  FROM x GROUP BY arm ORDER BY arm;

WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84)),
w AS (SELECT r.arm, r.run, b.vehicle_id, lower(b.during) AS seat_at, upper(b.during) AS seat_end
        FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run JOIN public.stalls s ON s.id = b.stall_id
       WHERE s.stall_type = 'wash_bay' AND b.state IN ('done', 'active', 'interrupted') AND b.booked_by LIKE 'otto_q%'),
x AS (SELECT w.*, (SELECT max(o.ended_at) FROM public.ocpp_sessions o
                    WHERE o.vehicle_id = w.vehicle_id AND o.sim_run_id = w.run AND o.ended_at <= w.seat_at) AS charge_end
        FROM w),
ticks AS (SELECT r.arm, g AS t FROM runs r, generate_series('2026-09-01 11:00+00'::timestamptz, '2026-09-01 23:00+00', interval '1 hour') g)
SELECT t.arm, to_char(t.t - interval '5 hours', 'HH24:MI') AS ct,
       (SELECT count(*) FROM x WHERE x.arm = t.arm AND x.charge_end <= t.t AND x.seat_at > t.t) AS waiting,
       (SELECT count(*) FROM x WHERE x.arm = t.arm AND x.seat_at <= t.t AND x.seat_end > t.t) AS washing
  FROM ticks t ORDER BY t.arm, t.t;

-- (22) G458: each wash bay every five minutes, idle while a car waited (charge ended, not yet seated), by what was on it:
--      a reservation that lapsed as a no-show, another reservation, or nothing at all.
WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('43301561-bce5-46c5-84c3-4235db4e4dd4'::uuid, 82)),
bays AS (SELECT s.id FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'wash_bay'),
bk AS (SELECT r.arm, b.* FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run WHERE b.stall_id IN (SELECT id FROM bays)),
w AS (SELECT r.arm, r.run, b.vehicle_id, lower(b.during) AS seat_at FROM runs r JOIN bk b ON b.arm = r.arm
       WHERE b.state IN ('done', 'active', 'interrupted') AND b.booked_by LIKE 'otto_q%'),
wq AS (SELECT w.arm, w.vehicle_id, w.seat_at,
              (SELECT max(o.ended_at) FROM public.ocpp_sessions o
                WHERE o.vehicle_id = w.vehicle_id AND o.sim_run_id = w.run AND o.ended_at <= w.seat_at) AS charge_end FROM w),
grid AS (SELECT r.arm, bays.id AS bay, g AS t FROM runs r CROSS JOIN bays
          CROSS JOIN generate_series('2026-09-01 11:00+00'::timestamptz, '2026-09-01 22:55+00', interval '5 min') g),
f AS (SELECT g.*,
             EXISTS (SELECT 1 FROM bk WHERE bk.arm = g.arm AND bk.stall_id = g.bay AND bk.state IN ('done', 'active', 'interrupted')
                        AND bk.during @> g.t) AS occ,
             EXISTS (SELECT 1 FROM bk WHERE bk.arm = g.arm AND bk.stall_id = g.bay AND bk.state = 'released'
                        AND bk.release_reason IN ('no_show_grace_elapsed', 'window_elapsed') AND bk.during @> g.t) AS noshow,
             EXISTS (SELECT 1 FROM bk WHERE bk.arm = g.arm AND bk.stall_id = g.bay AND bk.state IN ('released', 'superseded')
                        AND bk.during @> g.t AND COALESCE(bk.released_at, 'infinity') > g.t) AS held_other,
             (SELECT count(*) FROM wq WHERE wq.arm = g.arm AND wq.charge_end <= g.t AND wq.seat_at > g.t) AS waiting
        FROM grid g)
SELECT arm, count(*) FILTER (WHERE NOT occ) AS idle_bay_ticks,
       count(*) FILTER (WHERE NOT occ AND noshow AND waiting > 0) AS idle_behind_a_no_show_while_cars_waited,
       count(*) FILTER (WHERE NOT occ AND NOT noshow AND held_other AND waiting > 0) AS idle_behind_another_hold_while_cars_waited,
       count(*) FILTER (WHERE NOT occ AND NOT noshow AND NOT held_other AND waiting > 0) AS idle_and_free_while_cars_waited
  FROM f GROUP BY arm ORDER BY arm;

-- (23) G458: the wash no-shows, by the car's state at its slot; and for those still charging, the charge leg's planned
--      end against the slot, how far the charge ran past it, and how long the hold kept its bay.
WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('43301561-bce5-46c5-84c3-4235db4e4dd4'::uuid, 82)),
ns AS (SELECT r.arm, r.run, b.booking_id, b.vehicle_id, lower(b.during) AS lo, b.released_at AS rel
         FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run JOIN public.stalls s ON s.id = b.stall_id
        WHERE s.stall_type = 'wash_bay' AND b.state = 'released' AND b.release_reason IN ('no_show_grace_elapsed', 'window_elapsed')),
st AS (SELECT ns.*, vs.state,
              (SELECT max(l.planned_end_sim) FROM public.ottoq_itinerary_legs l
                WHERE l.sim_run_id = ns.run AND l.vehicle_id = ns.vehicle_id AND l.leg_type IN ('charge_l2', 'charge_dcfc')
                  AND l.planned_start_sim <= ns.lo + interval '3 min') AS leg_planned_end,
              (SELECT max(o.ended_at) FROM public.ocpp_sessions o
                WHERE o.sim_run_id = ns.run AND o.vehicle_id = ns.vehicle_id AND o.started_at <= ns.lo) AS session_end
         FROM ns CROSS JOIN LATERAL (
              SELECT e.payload -> 'diff' -> 'current_state' ->> 'to' AS state FROM public.ottoq_events e
               WHERE e.sim_run_id = ns.run AND e.entity_id = ns.vehicle_id AND e.event_type = 'vehicle.state_changed'
                 AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at <= ns.lo
               ORDER BY e.sim_clock_at DESC, e.event_id DESC LIMIT 1) vs)
SELECT arm, count(*) AS no_shows,
       count(*) FILTER (WHERE state LIKE 'charging%') AS car_charging,
       count(*) FILTER (WHERE state LIKE 'charging%' AND leg_planned_end <= lo) AS charging_past_the_legs_plan,
       count(*) FILTER (WHERE state IN ('staged_awaiting_service', 'charge_complete_holding', 'arrived_at_gate',
                                        'service_complete_holding')) AS car_idle_in_the_depot,
       count(*) FILTER (WHERE state LIKE 'in_%bay') AS car_in_another_bay,
       round(avg(extract(epoch FROM session_end - leg_planned_end) / 60) FILTER (WHERE state LIKE 'charging%')::numeric) AS overrun_min_mean,
       round(avg(extract(epoch FROM rel - lo) / 60) FILTER (WHERE state LIKE 'charging%')::numeric) AS held_min_mean
  FROM st GROUP BY arm ORDER BY arm;

-- (24) G457: the calendar against a car the arm holds. Per run, the ticks at which a car's charge ended while it held a
--      live bay booking (it is mated through that tick's decide), and the calendar's own seats inside and outside them.
--      The reproduction itself writes, so it is not here: it ran on live at 5:07 PM CT inside a transaction rolled back,
--      and tests/test_bay_activation_per_seat_sql.py repeats it on the live bodies.
WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('43301561-bce5-46c5-84c3-4235db4e4dd4'::uuid, 82),
                               ('fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid, 85)),
ticks AS (SELECT r.arm, r.run, g AS t FROM runs r, generate_series('2026-09-01 11:05+00'::timestamptz, '2026-09-01 23:00+00', interval '5 min') g),
held AS (SELECT DISTINCT t.arm, t.t FROM ticks t
           JOIN public.ocpp_sessions o ON o.sim_run_id = t.run AND o.ended_at = t.t
           JOIN public.ottoq_stall_bookings b ON b.sim_run_id = t.run AND b.vehicle_id = o.vehicle_id
                AND b.purpose IN ('wash', 'detail', 'service') AND b.booked_at_sim <= t.t
                AND COALESCE(b.released_at, 'infinity') > t.t AND upper(b.during) > t.t),
act AS (SELECT r.arm, lower(b.during) AS t, count(*) AS n FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run
         WHERE b.source IN ('bay_reservation_activated', 'bay_reservation_activated_early') GROUP BY 1, 2)
SELECT t.arm, count(*) AS ticks, count(h.t) AS ticks_with_a_held_car_booked,
       COALESCE(sum(a.n) FILTER (WHERE h.t IS NULL), 0) AS calendar_seats_other_ticks,
       COALESCE(sum(a.n) FILTER (WHERE h.t IS NOT NULL), 0) AS calendar_seats_in_those_ticks
  FROM ticks t LEFT JOIN held h ON h.arm = t.arm AND h.t = t.t LEFT JOIN act a ON a.arm = t.arm AND a.t = t.t
 GROUP BY t.arm ORDER BY t.arm;

-- (25) G453: the bay line's order on a run. Each service-bay seat by the path that made it (decide section (4b), the
--      ranked needs-card path, or section (5), first come first served), against the cars that had waited longer at that
--      tick and were not seated. Substitute the run (arm 82's busy day here).
WITH c AS (
  SELECT d.tick_seq, d.sim_clock, d.entity_id AS vid,
         CASE WHEN d.resolved_action_context = 'stall_assignment' THEN '4b' ELSE '5' END AS path,
         (d.outcome_status = 'enacted' AND (d.resolved_action_context = 'stall_assignment'
                                            OR d.enacted_action ->> 'verb' = 'admit_service')) AS seated
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = '43301561-bce5-46c5-84c3-4235db4e4dd4' AND d.action_context = 'task_start'
     AND ((d.resolved_action_context = 'stall_assignment' AND d.context_frame ->> 'stall_type' = 'service_bay')
       OR (d.resolved_action_context IS DISTINCT FROM 'stall_assignment' AND d.context_frame ->> 'service' = 'service'
           AND d.proposed_action ->> 'verb' IN ('admit_service', 'hold_in_queue')))),
fs AS (SELECT vid, min(sim_clock) AS t0 FROM c GROUP BY vid),
seats AS (SELECT DISTINCT ON (c.vid, c.tick_seq) c.* FROM c WHERE c.seated)
SELECT s.path, count(*) AS seats, round(avg(extract(epoch FROM s.sim_clock - f.t0) / 60)::numeric) AS seated_after_min_mean,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM c c2 JOIN fs f2 ON f2.vid = c2.vid
                                       WHERE c2.tick_seq = s.tick_seq AND c2.vid <> s.vid AND NOT c2.seated AND f2.t0 < f.t0)) AS over_a_longer_wait,
       round(avg((SELECT count(DISTINCT c2.vid) FROM c c2 JOIN fs f2 ON f2.vid = c2.vid
                   WHERE c2.tick_seq = s.tick_seq AND c2.vid <> s.vid AND NOT c2.seated AND f2.t0 < f.t0)), 1) AS longer_waits_passed_mean,
       round(avg((SELECT max(extract(epoch FROM s.sim_clock - f2.t0) / 60) FROM c c2 JOIN fs f2 ON f2.vid = c2.vid
                   WHERE c2.tick_seq = s.tick_seq AND c2.vid <> s.vid AND NOT c2.seated AND f2.t0 < f.t0))::numeric) AS longest_wait_passed_min_mean
  FROM seats s JOIN fs f ON f.vid = s.vid GROUP BY s.path ORDER BY s.path;

-- (26) G458: the walk-in path's refusals for a wash bay, by what held the bays. For each decide section (4b) refusal
--      (hold_no_space / no_free_space) at a tick, each wash bay's bookings live at that moment (booked by then, not yet
--      released) overlapping the job's window ([t, t + 25 min) for a deep clean, [t, t + 9 min) for a wash), classed by
--      the asking car's own, a seated car's, or a reservation whose car later came or never came. Final booking rows:
--      a hold the reconcile moved shows where it went, not where it was (its log keeps the old window).
WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('43301561-bce5-46c5-84c3-4235db4e4dd4'::uuid, 82)),
bays AS (SELECT s.id, s.stall_code FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'wash_bay'),
refusals AS (
  SELECT r.arm, r.run, d.sim_clock AS t, d.entity_id AS vehicle_id, d.proposed_action ->> 'purpose' AS purpose,
         CASE WHEN d.proposed_action ->> 'purpose' = 'detail' THEN interval '25 min' ELSE interval '9 min' END AS dur
    FROM runs r JOIN public.ottoq_decisions d ON d.sim_run_id = r.run
   WHERE d.action_context = 'task_start' AND d.proposed_action ->> 'source' = 'needs_card'
     AND d.proposed_action ->> 'stall_type' = 'wash_bay' AND d.enacted_action ->> 'verb' = 'hold_no_space'
     AND d.enacted_action ->> 'reason' = 'no_free_space'),
blk AS (
  SELECT f.arm, f.run, f.t, f.vehicle_id, b.id AS bay,
         array_agg(CASE
           WHEN bk.vehicle_id = f.vehicle_id THEN 'own'
           WHEN lower(bk.during) <= f.t AND bk.state IN ('active', 'done', 'interrupted') THEN 'occupied'
           WHEN bk.state IN ('active', 'done', 'interrupted') THEN 'reserved_showed'
           ELSE 'reserved_never_showed' END) FILTER (WHERE bk.booking_id IS NOT NULL) AS kinds
    FROM refusals f CROSS JOIN bays b
    LEFT JOIN public.ottoq_stall_bookings bk ON bk.sim_run_id = f.run AND bk.stall_id = b.id
         AND bk.booked_at_sim <= f.t AND COALESCE(bk.released_at, 'infinity') > f.t
         AND bk.during && tstzrange(f.t, f.t + f.dur, '[)')
   GROUP BY 1, 2, 3, 4, 5),
per AS (
  SELECT arm, run, t, vehicle_id,
         bool_or(kinds IS NULL) AS a_bay_free,
         bool_or(kinds IS NOT NULL AND 'occupied' <> ALL (kinds) AND 'reserved_showed' <> ALL (kinds) AND 'own' <> ALL (kinds)) AS a_bay_blocked_only_by_no_shows,
         bool_or(kinds IS NOT NULL AND 'own' = ANY (kinds) AND 'occupied' <> ALL (kinds) AND 'reserved_showed' <> ALL (kinds)) AS a_bay_blocked_by_own_hold,
         count(*) FILTER (WHERE kinds IS NOT NULL AND 'occupied' = ANY (kinds)) AS bays_occupied
    FROM blk GROUP BY 1, 2, 3, 4)
SELECT arm, count(*) AS refusals, count(DISTINCT vehicle_id) AS cars, count(DISTINCT t) AS ticks,
       count(*) FILTER (WHERE a_bay_free) AS with_no_blocker_in_the_final_rows,
       count(*) FILTER (WHERE NOT a_bay_free AND a_bay_blocked_only_by_no_shows) AS bay_blocked_only_by_a_no_show,
       count(*) FILTER (WHERE NOT a_bay_free AND NOT a_bay_blocked_only_by_no_shows AND a_bay_blocked_by_own_hold) AS bay_blocked_by_own_hold,
       count(*) FILTER (WHERE bays_occupied = 3) AS all_three_occupied
  FROM per GROUP BY arm ORDER BY arm;

-- (27) G459: (a) the itinerary's L2 legs on each run, and how far each skipped one ended past the car's real charge;
--      (b) the reconcile's charging blocks (BLOCKER 1) on cars that were not charging, by the blocking leg's fate.
WITH runs(run, arm) AS (VALUES ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid, 85),
                               ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86), ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83)),
l2 AS (SELECT r.arm, r.run, l.vehicle_id, l.itinerary_id, l.planned_start_sim, l.planned_end_sim, l.status
         FROM runs r JOIN public.ottoq_itinerary_legs l ON l.sim_run_id = r.run
        WHERE l.leg_type = 'charge_l2'),
x AS (SELECT l2.*,
             (SELECT o.ended_at FROM public.ocpp_sessions o WHERE o.sim_run_id = l2.run AND o.vehicle_id = l2.vehicle_id
                 AND o.ended_at >= l2.planned_start_sim - interval '3 hours' AND o.started_at <= l2.planned_end_sim
               ORDER BY o.ended_at DESC LIMIT 1) AS real_charge_end,
             (SELECT max(ll.planned_end_sim) FROM public.ottoq_itinerary_legs ll
               WHERE ll.sim_run_id = l2.run AND ll.itinerary_id = l2.itinerary_id) AS itinerary_end
        FROM l2)
SELECT arm, count(*) AS l2_legs, count(DISTINCT vehicle_id) AS cars, count(*) FILTER (WHERE status = 'skipped') AS skipped,
       round(avg(extract(epoch FROM planned_end_sim - planned_start_sim) / 60)) AS mean_len_min,
       round(avg(extract(epoch FROM planned_end_sim - real_charge_end) / 60) FILTER (WHERE status = 'skipped')) AS skipped_end_past_real_min_mean,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM planned_end_sim - real_charge_end) / 60)
              FILTER (WHERE status = 'skipped'))::numeric) AS p50_min,
       count(*) FILTER (WHERE status = 'skipped' AND planned_end_sim >= itinerary_end - interval '20 min') AS skipped_within_20min_of_plan_end
  FROM x GROUP BY arm ORDER BY arm;

WITH runs(run, arm) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86),
                               ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid, 85),
                               ('43301561-bce5-46c5-84c3-4235db4e4dd4'::uuid, 82)),
rl AS (SELECT r.arm, r.run, l.* FROM runs r JOIN public.bay_reservation_reconcile_2026_08_02 l ON l.sim_run_id = r.run
        WHERE l.blocked_by LIKE 'charging%' AND l.action IN ('deferred', 'released')),
st AS (SELECT rl.*, (SELECT e.payload -> 'diff' -> 'current_state' ->> 'to' FROM public.ottoq_events e
                      WHERE e.sim_run_id = rl.run AND e.entity_id = rl.vehicle_id AND e.event_type = 'vehicle.state_changed'
                        AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at <= rl.sim_clock
                      ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS vstate
       FROM rl),
lg AS (SELECT st.*, x.leg_type, x.status AS leg_final_status
         FROM st LEFT JOIN LATERAL (
              SELECT l.* FROM public.ottoq_itinerary_legs l
               WHERE l.sim_run_id = st.run AND l.vehicle_id = st.vehicle_id AND l.leg_type IN ('charge_l2', 'charge_dcfc')
                 AND l.planned_end_sim > st.sim_clock AND (l.actual_end_sim IS NULL OR l.actual_end_sim > st.sim_clock)
               ORDER BY l.planned_end_sim DESC LIMIT 1) x ON true
        WHERE st.vstate NOT LIKE 'charging%')
SELECT arm, count(*) AS blocks_on_cars_not_charging, count(DISTINCT booking_id) AS holds,
       count(DISTINCT booking_id) FILTER (WHERE leg_final_status = 'skipped') AS holds_behind_a_leg_never_served,
       round(avg(extract(epoch FROM new_from - old_from) / 60) FILTER (WHERE action = 'deferred')) AS mean_push_min
  FROM lg GROUP BY arm ORDER BY arm;

-- (28) G459: the rehearsal. Every charge to full on four arms, planned three ways against the real session: the rule
--      (below 45% a fast charge at 100 kW, else an L2 at 11 kW, physics estimate), and 0745's (the kind the car can use
--      at the depot, else the rule's kind, on the learned clock). It reads the depot's clock as it stands; after a refit
--      the numbers move, so pin the fit (ottoq_charge_clock_fits) to reproduce 2026-10-17's reading on fit 11.
WITH runs(run, arm, has_l2) AS (VALUES ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83, true), ('0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid, 86, true),
                                      ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84, false), ('fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid, 85, false)),
m AS (SELECT public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111') AS ct),
s AS (SELECT r.arm, r.has_l2, o.vehicle_id, o.soc_start, extract(epoch FROM o.ended_at - o.started_at) / 60 AS real_min,
             CASE WHEN NOT r.has_l2 THEN 'dcfc'
                  WHEN r.arm = 86 AND st.stall_code IN ('NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03','NASH-L2-STALL-04','NASH-L2-STALL-05',
                                                        'NASH-L2-STALL-06','NASH-L2-STALL-07','NASH-L2-STALL-08','NASH-L2-STALL-09','NASH-L2-STALL-10') THEN 'dcfc'
                  ELSE st.stall_type::text END AS real_kind,
             v.battery_capacity_kwh AS batt, v.inlet_max_kw AS inlet, COALESCE(v.inlet_max_kw, 150) AS inlet_p, COALESCE(v.battery_capacity_kwh, 75) AS pack_p,
             public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who
        FROM runs r JOIN public.ocpp_sessions o ON o.sim_run_id = r.run JOIN public.stalls st ON st.id = o.stall_id JOIN public.vehicles v ON v.id = o.vehicle_id
       WHERE o.soc_end >= 99 AND o.ended_at IS NOT NULL AND o.soc_start < 99),
e AS (SELECT s.*,
             CASE WHEN s.soc_start < 45 THEN 'dcfc' ELSE 'l2' END AS kind_today,
             public.ottoq_estimate_charge_minutes(s.soc_start, 100, CASE WHEN s.soc_start < 45 THEN 100 ELSE 11 END, s.inlet_p, s.pack_p, 20, 100, 1.0) AS min_today,
             (public.ottoq_charge_clock((SELECT ct FROM m), 'dcfc', s.who, s.batt, s.soc_start, 100, 350, s.inlet, NULL) ->> 'm')::numeric AS md,
             (public.ottoq_charge_clock((SELECT ct FROM m), 'l2', s.who, s.batt, s.soc_start, 100, 19.2, s.inlet, NULL) ->> 'm')::numeric AS ml
        FROM s),
f AS (SELECT e.*, CASE WHEN NOT e.has_l2 THEN 'dcfc' ELSE e.kind_today END AS kind_a FROM e)
SELECT arm, count(*) AS charges, round(avg(real_min)::numeric, 1) AS real_mean,
       round(100.0 * avg((kind_today = real_kind)::int), 1) AS rule_kind_pct, round(avg(abs(min_today - real_min))::numeric, 1) AS rule_mae,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(min_today - real_min)))::numeric, 1) AS rule_p90_abs,
       round(100.0 * avg((kind_a = real_kind)::int), 1) AS clock_plan_kind_pct,
       round(avg(abs(CASE WHEN kind_a = 'dcfc' THEN md ELSE ml END - real_min))::numeric, 1) AS clock_plan_mae,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(CASE WHEN kind_a = 'dcfc' THEN md ELSE ml END - real_min)))::numeric, 1) AS clock_plan_p90_abs,
       round(100.0 * avg(((CASE WHEN md <= ml THEN 'dcfc' ELSE 'l2' END) = real_kind)::int), 1) AS faster_kind_pct,
       round(avg(abs(CASE WHEN real_kind = 'dcfc' THEN md ELSE ml END - real_min))::numeric, 1) AS clock_mae_if_kind_known
  FROM f GROUP BY arm ORDER BY arm;

-- (29) G458: the wash lane's staff cap. Each five minutes, the wash bays with a seated car, the cars staged and waiting
--      for a wash or deep clean (their charge ended, their wash seat later), and whether section (4b) tried a walk-in at
--      that tick. With two bays washing and no attempt, the lane's headroom (LEAST(bays, wash supervisors) less the cars
--      in a wash or detail bay) was zero.
WITH runs(run, arm) AS (VALUES ('b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid, 84), ('e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid, 83)),
bays AS (SELECT s.id FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'wash_bay'),
ticks AS (SELECT r.arm, r.run, g AS t FROM runs r CROSS JOIN generate_series('2026-09-01 11:00+00'::timestamptz, '2026-09-01 22:55+00', interval '5 min') g),
occ AS (SELECT k.arm, k.run, k.t,
               (SELECT count(DISTINCT b.stall_id) FROM public.ottoq_stall_bookings b
                 WHERE b.sim_run_id = k.run AND b.stall_id IN (SELECT id FROM bays) AND b.state IN ('active', 'done', 'interrupted')
                   AND b.during @> k.t) AS washing
          FROM ticks k),
att AS (SELECT r.arm, d.sim_clock AS t, count(*) AS attempts
          FROM runs r JOIN public.ottoq_decisions d ON d.sim_run_id = r.run
         WHERE d.action_context = 'task_start' AND d.proposed_action ->> 'source' = 'needs_card'
           AND d.proposed_action ->> 'stall_type' = 'wash_bay'
         GROUP BY 1, 2),
w AS (SELECT r.arm, r.run, b.vehicle_id, lower(b.during) AS seat_at
        FROM runs r JOIN public.ottoq_stall_bookings b ON b.sim_run_id = r.run
       WHERE b.stall_id IN (SELECT id FROM bays) AND b.state IN ('done', 'active', 'interrupted') AND b.booked_by LIKE 'otto_q%'),
wq AS (SELECT w.*, (SELECT max(o.ended_at) FROM public.ocpp_sessions o
                     WHERE o.vehicle_id = w.vehicle_id AND o.sim_run_id = w.run AND o.ended_at <= w.seat_at
                       AND o.ended_at >= w.seat_at - interval '6 hours') AS charge_end FROM w),
cand AS (SELECT k.arm, k.t, wq.vehicle_id,
                (SELECT e.payload -> 'diff' -> 'current_state' ->> 'to' FROM public.ottoq_events e
                  WHERE e.sim_run_id = k.run AND e.entity_id = wq.vehicle_id AND e.event_type = 'vehicle.state_changed'
                    AND e.payload -> 'diff' ? 'current_state' AND e.sim_clock_at <= k.t
                  ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS st
           FROM occ k JOIN wq ON wq.arm = k.arm AND wq.charge_end <= k.t AND wq.seat_at > k.t
          WHERE k.washing = 2),
staged AS (SELECT arm, t, count(DISTINCT vehicle_id) AS staged_waiting FROM cand WHERE st = 'staged_awaiting_service' GROUP BY 1, 2)
SELECT o.arm,
       count(*) FILTER (WHERE o.washing = 2 AND s.staged_waiting > 0) AS two_washing_staged_cars_waiting,
       count(*) FILTER (WHERE o.washing = 2 AND s.staged_waiting > 0 AND a.attempts IS NULL) AS of_which_no_walk_in_tried,
       round(avg(s.staged_waiting) FILTER (WHERE o.washing = 2 AND a.attempts IS NULL), 1) AS staged_waiting_mean_then,
       min(o.t) FILTER (WHERE o.washing = 2 AND s.staged_waiting > 0 AND a.attempts IS NULL) - interval '5 hours' AS first_ct,
       max(o.t) FILTER (WHERE o.washing = 2 AND s.staged_waiting > 0 AND a.attempts IS NULL) - interval '5 hours' AS last_ct
  FROM occ o LEFT JOIN staged s ON s.arm = o.arm AND s.t = o.t LEFT JOIN att a ON a.arm = o.arm AND a.t = o.t
 GROUP BY o.arm ORDER BY o.arm;

-- (30) G449, §15: fast-charger handovers with a car waiting on several runs, split by the gap's length. A gap of 15
--      minutes or less is a handover; a longer one is a fault or a car not yet ready. Stall types are read from stalls,
--      so only arms whose build-out converts nothing (dcfc10) read right (query (3c)'s note).
WITH runs(arm, rid) AS (VALUES (83, 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid), (90, '54bc3afc-2634-47f0-bc4b-4fc4c0958c26'::uuid),
                               (91, 'fdeffed1-b46a-4bd4-96eb-771585fac035'::uuid), (92, '061069f7-9ff2-43d5-9d02-0c5a40225a93'::uuid),
                               (93, '6768503c-8fd9-4482-8fa5-c144f875219b'::uuid)),
s AS (
  SELECT r.arm, x.stall_id, x.started_at, x.ended_at, x.stopped_reason,
         lead(x.started_at) OVER (PARTITION BY r.arm, x.stall_id ORDER BY x.started_at) AS next_start
    FROM runs r JOIN public.ocpp_sessions x ON x.sim_run_id = r.rid JOIN public.stalls st ON st.id = x.stall_id
   WHERE st.stall_type::text = 'dcfc' AND x.started_at IS NOT NULL AND x.ended_at IS NOT NULL),
fc_first AS (
  SELECT r.arm, vn.arrived_at, f.started_at AS first_start
    FROM runs r JOIN public.ottoq_visit_needs vn ON vn.sim_run_id = r.rid
    JOIN LATERAL (SELECT y.started_at, sty.stall_type::text AS t FROM public.ocpp_sessions y JOIN public.stalls sty ON sty.id = y.stall_id
                   WHERE y.sim_run_id = vn.sim_run_id AND y.vehicle_id = vn.vehicle_id AND y.started_at >= vn.arrived_at
                   ORDER BY y.started_at LIMIT 1) f ON f.t = 'dcfc'),
g AS (SELECT s.*, extract(epoch FROM (s.next_start - s.ended_at)) / 60.0 AS gap_min,
             (SELECT count(*) FROM fc_first f WHERE f.arm = s.arm AND f.arrived_at <= s.ended_at AND f.first_start > s.ended_at) AS fc_waiting
        FROM s WHERE s.next_start IS NOT NULL)
SELECT g.arm, CASE WHEN gap_min <= 15 THEN 'a: handover, <= 15 min' WHEN gap_min <= 60 THEN 'b: 15-60 min' ELSE 'c: > 60 min' END AS gap,
       count(*) AS n, min(gap_min) AS shortest_min,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY gap_min)::numeric, 2) AS p50_min,
       round(sum(gap_min)::numeric / 60, 1) AS idle_charger_hours,
       string_agg(DISTINCT COALESCE(g.stopped_reason, '-'), ', ') AS prior_session_stopped,
       (SELECT round(sum(extract(epoch FROM (s2.ended_at - s2.started_at)) / 3600)::numeric, 1) FROM s s2 WHERE s2.arm = g.arm) AS charging_hours_all
  FROM g WHERE fc_waiting > 0 GROUP BY 1, 2 ORDER BY 1, 2;

-- (31) G468, §16: the twin's site meter against what the sessions delivered and against the chargers' own readings, per
--      run. The meter is integrated as ottoq_dial_arm_metrics integrates it (each snapshot held until the next); the
--      readings are each tick's TransactionEvent Updated Power.Active.Import over one tick. Arms 83-95.
WITH runs(arm, rid) AS (VALUES (83, 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid), (84, 'b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid),
                               (85, 'fe6d540e-860f-4057-8edf-7d6257b94bff'::uuid), (86, '0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid),
                               (89, '2e0752ff-77b3-4656-9e4f-2b64040ac6b9'::uuid), (90, '54bc3afc-2634-47f0-bc4b-4fc4c0958c26'::uuid),
                               (91, 'fdeffed1-b46a-4bd4-96eb-771585fac035'::uuid), (92, '061069f7-9ff2-43d5-9d02-0c5a40225a93'::uuid),
                               (93, '6768503c-8fd9-4482-8fa5-c144f875219b'::uuid), (94, 'e8b068d2-6dda-4643-a59a-9c2ff37d784e'::uuid),
                               (95, '12c6fd31-1b1c-4fa9-9ce8-c4d6103d955b'::uuid)),
snap AS (
  SELECT r.arm, e.timestamp AS t, e.total_ev_charging_kw AS ev_kw,
         EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (PARTITION BY r.arm ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
    FROM runs r JOIN public.site_energy_snapshots e ON e.sim_run_id = r.rid AND e.depot_id = '11111111-1111-1111-1111-111111111111'),
upd AS (
  SELECT r.arm, o.sim_clock_at AS t,
         sum((SELECT (v ->> 'value')::numeric FROM jsonb_array_elements(o.payload -> 'meterValue' -> 0 -> 'sampledValue') v
               WHERE v ->> 'measurand' = 'Power.Active.Import')) AS kw
    FROM runs r JOIN public.ottoq_ocpp_messages o ON o.sim_run_id = r.rid AND o.message_type = 'TransactionEvent'
   WHERE o.payload ->> 'eventType' = 'Updated' GROUP BY 1, 2),
starts AS (SELECT r.arm, x.started_at AS t, count(*) AS n FROM runs r JOIN public.ocpp_sessions x ON x.sim_run_id = r.rid GROUP BY 1, 2),
ends AS (SELECT r.arm, x.ended_at AS t, count(*) AS n FROM runs r JOIN public.ocpp_sessions x ON x.sim_run_id = r.rid
          WHERE x.ended_at IS NOT NULL GROUP BY 1, 2),
sess AS (SELECT r.arm, count(*) AS sessions, sum(x.energy_delivered_kwh) AS delivered FROM runs r
           JOIN public.ocpp_sessions x ON x.sim_run_id = r.rid GROUP BY 1),
j AS (
  SELECT s.arm, s.dt, s.ev_kw, COALESCE(u.kw, 0) AS readings_at_t, (st.n IS NULL AND en.n IS NULL) AS quiet
    FROM snap s LEFT JOIN upd u ON u.arm = s.arm AND u.t = s.t
    LEFT JOIN starts st ON st.arm = s.arm AND st.t = s.t LEFT JOIN ends en ON en.arm = s.arm AND en.t = s.t)
SELECT j.arm, max(ss.sessions) AS sessions, round(max(ss.delivered), 0) AS delivered_kwh,
       round(sum(j.ev_kw * j.dt) FILTER (WHERE j.dt IS NOT NULL)::numeric, 0) AS meter_kwh,
       round((sum(j.ev_kw * j.dt) FILTER (WHERE j.dt IS NOT NULL) / NULLIF(max(ss.delivered), 0) - 1)::numeric * 100, 1) AS meter_over_sessions_pct,
       (SELECT round(sum(u.kw) * max(j2.dt), 0) FROM upd u, LATERAL (SELECT avg(dt) AS dt FROM snap WHERE snap.arm = j.arm) j2
         WHERE u.arm = j.arm) AS readings_kwh,
       round(sum(j.ev_kw - j.readings_at_t), 0) AS meter_minus_readings_kw_ticks,
       round(sum(j.ev_kw - j.readings_at_t) FILTER (WHERE j.quiet), 0) AS of_which_on_quiet_ticks
  FROM j JOIN sess ss ON ss.arm = j.arm GROUP BY j.arm ORDER BY j.arm;

-- (32) G468, §16: the grid recomputed from the chargers' own readings (the meter's EV load replaced by the readings
--      stamped at the same tick), against the meter: energy, the whole-day half hour and the half hour billed from 180
--      minutes, over full half hours only (G469).
WITH runs(arm, rid) AS (VALUES (83, 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd'::uuid), (84, 'b54f6de5-7cf3-4d91-a0d1-0010a21fec64'::uuid),
                               (86, '0b0d45c2-b777-410c-b4b2-d6bce5a502bd'::uuid), (93, '6768503c-8fd9-4482-8fa5-c144f875219b'::uuid),
                               (94, 'e8b068d2-6dda-4643-a59a-9c2ff37d784e'::uuid), (95, '12c6fd31-1b1c-4fa9-9ce8-c4d6103d955b'::uuid)),
upd AS (
  SELECT r.arm, o.sim_clock_at AS t,
         sum((SELECT (v ->> 'value')::numeric FROM jsonb_array_elements(o.payload -> 'meterValue' -> 0 -> 'sampledValue') v
               WHERE v ->> 'measurand' = 'Power.Active.Import')) AS kw
    FROM runs r JOIN public.ottoq_ocpp_messages o ON o.sim_run_id = r.rid AND o.message_type = 'TransactionEvent'
   WHERE o.payload ->> 'eventType' = 'Updated' GROUP BY 1, 2),
s AS (
  SELECT r.arm, e.timestamp AS t, e.grid_import_kw - e.grid_export_kw AS net_kw, e.total_ev_charging_kw AS ev_kw,
         EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (PARTITION BY r.arm ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
    FROM runs r JOIN public.site_energy_snapshots e ON e.sim_run_id = r.rid AND e.depot_id = '11111111-1111-1111-1111-111111111111'),
c AS (
  SELECT s.arm, s.t, s.dt, GREATEST(s.net_kw, 0) AS g_meter, GREATEST(s.net_kw - s.ev_kw + COALESCE(u.kw, 0), 0) AS g_readings
    FROM s LEFT JOIN upd u ON u.arm = s.arm AND u.t = s.t),
w AS (
  SELECT c.*, min(t) OVER (PARTITION BY arm) AS t0,
         avg(g_meter) OVER (PARTITION BY arm ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS m30,
         avg(g_readings) OVER (PARTITION BY arm ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS r30,
         count(*) OVER (PARTITION BY arm ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS n30
    FROM c)
SELECT arm,
       round(sum(g_meter * dt) FILTER (WHERE dt IS NOT NULL)::numeric, 0) AS grid_kwh_meter,
       round(sum(g_readings * dt) FILTER (WHERE dt IS NOT NULL)::numeric, 0) AS grid_kwh_readings,
       round(max(m30) FILTER (WHERE n30 >= 6)::numeric, 1) AS day_half_hour_meter,
       round(max(r30) FILTER (WHERE n30 >= 6)::numeric, 1) AS day_half_hour_readings,
       round(max(m30) FILTER (WHERE n30 >= 6 AND t >= t0 + interval '180 minutes')::numeric, 1) AS billed_half_hour_meter,
       round(max(r30) FILTER (WHERE n30 >= 6 AND t >= t0 + interval '180 minutes')::numeric, 1) AS billed_half_hour_readings
  FROM w GROUP BY arm ORDER BY arm;
-- n30 >= 6 assumes a 5-minute tick; at 2.5 minutes ask for 12.

-- (33) G469, §17: the arms whose half hour billed from 180 minutes starts in the run's last half hour, and that half hour
--      over full windows wherever the arm's run is still on record (its snapshots are run-scoped and the purge takes them).
WITH a AS (
  SELECT a.arm_id, a.sim_run_id, s.sweep_code,
         (a.arm_metrics ->> 'ticks')::numeric * (a.arm_metrics ->> 'sim_min_per_tick')::numeric AS run_min,
         (a.arm_metrics ->> 'sim_min_per_tick')::numeric AS step_min,
         (a.arm_metrics #>> '{peak_after_open,starts_min,180}')::numeric AS billed_start_min,
         (a.arm_metrics #>> '{peak_after_open,peak_30min_kw,180}')::numeric AS billed_kw,
         (a.arm_metrics #>> '{peak_after_open,demand_charge_usd_month,180}')::numeric AS billed_usd
    FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE a.complete AND a.arm_metrics ? 'peak_after_open'),
p AS (SELECT * FROM a WHERE billed_start_min > run_min - 30),
w AS (
  SELECT p.arm_id, e.timestamp AS t,
         avg(GREATEST(COALESCE(e.grid_import_kw, 0), 0)) OVER (PARTITION BY p.arm_id ORDER BY e.timestamp
             RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30,
         count(*) OVER (PARTITION BY p.arm_id ORDER BY e.timestamp
             RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS n30,
         min(e.timestamp) OVER (PARTITION BY p.arm_id) AS t0, p.step_min
    FROM p JOIN public.site_energy_snapshots e ON e.sim_run_id = p.sim_run_id AND e.depot_id = '11111111-1111-1111-1111-111111111111')
SELECT (SELECT count(*) FROM a) AS arms_with_after_open, p.arm_id, p.sweep_code, p.run_min, p.billed_start_min, p.billed_kw, p.billed_usd,
       (SELECT round(max(w.g30)::numeric, 1) FROM w WHERE w.arm_id = p.arm_id AND w.n30 * w.step_min >= 30
           AND w.t >= w.t0 + interval '180 minutes') AS billed_kw_full_windows
  FROM p ORDER BY p.arm_id;
