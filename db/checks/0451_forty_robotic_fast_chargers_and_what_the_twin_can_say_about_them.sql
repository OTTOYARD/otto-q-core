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
--   Every arm: the twin depot, 6 AM CT for 12 hours at 5 sim-minutes a tick (144 ticks), value_2026_09_30's first
--   seed, OTTO-Q, deploy_peak_fraction 0.90, past the dial floor. ONE SEED PER CELL: each figure is a single reading,
--   not a range (G153), and the two arms of one cell that the overlapping sweeps will produce (0728's note) are the
--   first measure of how far one reading can move. "after 3 h" is the 30-minute peak from 180 minutes into the day,
--   past the opening plug-in, which is what ottoq_value_summary bills (0577); "whole day" includes the opening. Every
--   battery planned against the whole day (G447, §11), so the demand charges are its conceding the afternoon.
--   Arms read 08:18 UTC (82-84), 09:01 UTC (85), 09:33 UTC (86) and 10:07 UTC (87).
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
--   82-87; 0728's gated arm and 0731's bill-window pairs land after it.
--
--   1. LEAN IN. Robotic fast charging is the edge, and the evidence is the slow tail and the car-hours, not the median.
--      On the normal day forty robotic posts served 45% more cars in 12 hours than the depot as built, cut the slowest
--      5% from 428 to 248-270 minutes, and met 121 more car-hours of ride demand (15% unmet against 26%), every car at
--      100% with nothing open. A robot on every post is what makes that possible: no car waits for a person to plug it
--      in, so the depot's limit stops being connectors and labour and becomes power and time.
--
--   2. SIZE THE POSTS BY THEIR PRICE, NOT BY THE STALLS. Forty posts were busy 41% of the day against the ten's 69%,
--      and the curve bends: posts 11-20 met 5.8 car-hours each in the 12-hour day, posts 21-40 met 3.1 each (§3). At the
--      value sweep's own prices (ottoq_margin_prices: $20 a deployed car-hour, range $16-24, its Waymo-review source;
--      about $206,000 installed per 350 kW charger, its INL source, before the robot itself), a month of such days is
--      worth about $3,500 per post for posts 11-20 and $1,900 per post for posts 21-40, against about $1,700 a month
--      for a post's installed price spread straight over ten years with no financing, robot or upkeep. ASSUMPTIONS, all
--      of them: one seed, a 12-hour day and nothing for the night. On that reading twenty posts clearly pay, and the
--      second twenty pay only if the night, the robot's price and more seeds come out in their favour. A staged build,
--      twenty now and the rest as measured demand fills them, buys the same answer with half the capital at risk.
--
--   3. DO NOT SIZE THE GRID TO THE NAMEPLATE. Forty posts with nothing holding them drew 3.9 MW for the 6 AM plug-in.
--      On the existing 2.5 MW service, behind 2.4 MW of shared cabinets, they met 948.3 car-hours (0726's sharing
--      alone) and 941.8 (held at 2.16 MW, 0729) against 942.7 on a grid grown to 8 MW. The megawatt worry is a control
--      question, and its answer is a site controller holding a limit that OTTO-Q sets: shared cabinets (the Kempower and
--      ABB units 0567 and 0728 cite) with OTTO-Q deciding the split. No utility upgrade is needed for this day's load.
--
--   4. THE BILL TO MANAGE IS THE DEMAND CHARGE, AND THE TARIFF IS A YEARLY DECISION. At GSA-3's $21.40-21.78 per kW
--      of the month's highest half hour, the unmanaged forty cost $51,228 a month in demand on the whole day against
--      $35,419 held; past the opening both sit near $22,000 against $15,271 as built. NES's EVC schedule has no demand
--      charge at 21.773 c/kWh, and beats GSA-3 for the charging meter below a 17.4% monthly load factor; it carries a
--      one-year term and 90 days' notice back (§4). A held site keeps its load factor up and stays on GSA-3.
--
--   5. WHAT THE ENGINE NEEDS BEFORE A REAL CONVERSION, as certified changes, each already measured in the twin:
--      (a) a new session is metered at its share from its first reading (G448). On the managed arm all 85 refusals
--          came with the meter itself over the held cap, from cars started a tick earlier still metered at full rate
--          (§3). (b)'s reading removed every refusal of the other kind (the meter under the cap and the car's full
--          rating on top: all 84 on the shared arm), and until (a) is fixed the meter puts them back;
--      (b) the shield judges a site that divides its power by the limit it holds (0729 models it; production needs the
--          site controller's limit in the charge start's context, and the controller itself);
--      (c) the battery plans for the bill that is charged, and is ready for the surges OTTO-Q itself schedules: it
--          charged at 425 kW in the tick the fleet plugged in, shaved one tick late, and idled all afternoon (G447);
--      (d) one answer for how much power a car can take (G443: twelve cars, four answers);
--      (e) the site gate reads the meter, not a band estimate 1.50x high (0727).
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
--      against max-min fair on the same seeds: the due cars on time (8 of 72 free, 4 of 66 held, §3) are its target.
--
--   7. WHAT IS NOT KNOWN YET. One seed per cell, so every gap above is a single reading (the replicate of dcfc40.otto_q
--      in 0725's sweep is the first measure of how far one moves). A 12-hour day from 6 AM: no night, where L2's slow
--      charge costs least. busy_day's wall is the two service bays (§5), which more chargers cannot move. The battery's
--      worth on the billed window is 0731's three paired arms.
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
