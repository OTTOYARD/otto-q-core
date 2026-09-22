-- 0319  **Chase asked whether `busy_day` injects the faults that put 86 of 116 vehicles into
--       `tow_requested` on run `d68d05bb`. IT DOES. The 7x DTC rate is live, and
--       `db/checks/0237`'s conclusion that it is "declared and not applied" is RETRACTED.**
--
--       `0237` is not wrong about what it measured. It is wrong about what that means, and the gap
--       between those two is the finding.
--
-- ══ §1 WHAT `0237` ESTABLISHED, AND IT STILL STANDS ════════════════════════
--
-- `0237` censused every database function in `public`, `twin` and `ottoq` for the literal strings
-- `dtc_rate_multiplier` and `incident_rate_multiplier`, found none, and listed them under **"NOT
-- READ BY ANY DATABASE FUNCTION"**. Re-measured today: still true. `ottoq_scenarios`'s
-- `timeline.fault_injection` jsonb is mentioned only by `ottoq_sim_run_scenario`, which packs it
-- into a payload and never interprets it. `0237`'s own words — *"packing is not interpreting"* —
-- are correct.
--
-- ══ §2 WHAT IT CONCLUDED FROM THAT, AND THIS PART IS FALSE ═════════════════
--
-- `0237` §C reads:
--
--     busy_day declares fault_injection {dtc_rate_multiplier: 7, incident_rate_multiplier: 0.4}
--     AND busy_day IS A CERTIFIED CANON COLUMN [...] A sevenfold diagnostic-trouble-code rate is
--     declared and not applied, so what the canon certifies is reproducibility of a scenario that
--     is milder than its own declaration says.
--
-- **The sevenfold rate IS applied.** Measured on run `d68d05bb` (busy_day, seed 700001, 1,104
-- ticks, 2026-09-21):
--
--     SELECT public.ottoq_profile_rate_mult('d68d05bb-…','dtc');   -->   7.0
--
-- The canon certifies a scenario that is exactly as harsh as its declaration says. The sentence
-- above must not be quoted again.
--
-- ══ §3 THE CHAIN, TRACED END TO END ════════════════════════════════════════
--
-- The value reaches the engine through a SECOND declaration that carries the same numbers under
-- different key names:
--
--   (a) `public.ottoq_variability_profiles` holds 13 TEMPLATE rows (`sim_run_id IS NULL`), one per
--       scenario name. The `busy_day` template's `knobs._rates` is:
--
--           {"dtc": 7.0, "arrival": 2.0, "incident": 0.4,
--            "idle_fraction": 1.9, "trip_duration": 0.30}
--
--   (b) At run start, `public.ottoq_variability_instantiate(run, template_name)` copies that
--       template into a per-run row. Its whole body is a `SELECT knobs ... WHERE name =
--       p_template_name` (falling back to `'__default__'`) and an INSERT. **It does not read
--       `ottoq_scenarios` at all.** The run's row carries `notes = 'instantiated from busy_day'`,
--       created at 21:32:24 — the second the run started.
--
--   (c) `public.ottoq_profile_rate_mult(run, 'dtc')` returns
--       `_rates.dtc * COALESCE(_global.rate_mult, 1)` = **7.0**.
--
--   (d) `twin.ottoq_sim_advance_deployed_telemetry` passes it as the fifth argument:
--
--           twin.ottoq_sim_maybe_spawn_dtc(v_seed, v_salt, p_tick_minutes, v_active_frac,
--                                          ottoq_profile_rate_mult(p_sim_run_id, 'dtc'))
--
--   (e) `twin.ottoq_sim_maybe_spawn_dtc` computes
--
--           v_per_active_min := 0.0001;
--           v_effective_p := v_per_active_min * p_tick_minutes * p_active_fraction
--                            * COALESCE(p_rate_mult, 1);
--
--       so the baseline one-in-ten-thousand per active minute is multiplied by 7, and the DTC is
--       then drawn from `ottoq_dtc_catalog` by seeded random across six categories.
--
-- **So the consumer was never missing. It reads a different table.** `0237` predicted exactly this
-- in its §D — *"or was replaced later by something with its own opinion, as the ChargerHelp
-- calibrated fault model replaced whatever fault_injection was meant to drive"* — and then did not
-- follow that thought to the variability profile.
--
-- ══ §4 THE DEFECT IS DUPLICATION, NOT ABSENCE ══════════════════════════════
--
-- Two places declare the same two numbers:
--
--     ottoq_scenarios.timeline.fault_injection      {dtc_rate_multiplier: 7.0,
--                                                    incident_rate_multiplier: 0.4}   INERT
--     ottoq_variability_profiles[name='busy_day']   {_rates.dtc: 7.0,
--                                                    _rates.incident: 0.4}            LIVE
--
-- They agree today because whoever wrote them wrote both. **Edit the scenario's and nothing
-- happens. Edit the template's and behaviour changes while the scenario row still advertises the
-- old figure.** That is strictly worse than `0237`'s reading of an inert knob, because an inert
-- knob misleads in one direction and a duplicated one misleads in whichever direction you last
-- edited. Same family as `0231` (a COMMENT asserting a protection the mechanism cannot read) and
-- `0318` §10 (`forces_recert` argued in a header while the floor reads a table): **the artifact
-- that looks like the configuration is not the one the code reads.**
--
-- ══ §5 AND THE SAME CORRECTION LANDS ON `0237`'s HEADLINE EXAMPLE ══════════
--
-- `0237` §C's lead case is `charger_outage_morning_rush`: *"Its entire defining feature — three
-- DCFC stalls offline through the morning rush — is not implemented. The scenario runs as an
-- ordinary day under a name that promises a failure mode."* **Its template carries
-- `_rates: {charger_fault: 4}`.** It is not an ordinary day; it runs a fourfold charger-fault rate.
-- What is genuinely unimplemented is the DETERMINISTIC form — three named stalls offline across a
-- fixed window — which the stochastic 4x does not reproduce. That distinction matters for a
-- certification scenario and is worth keeping; "runs as an ordinary day" is not.
--
-- The live templates, for the record: `busy_day` dtc 7 / arrival 2 / incident 0.4,
-- `major_charger_outage` charger_fault 10, `charger_outage_morning_rush` charger_fault 4,
-- `dr_event_cascade` dr_ignition 3, `rush_hour_gridlock` arrival 1.5 / eta_delay 3,
-- `heat_wave` dr_ignition 2, `winter_storm` dtc 2, `aggressive_fleet_turnover` dtc 1.5 /
-- arrival 2 / incident 1.3. `normal_day`, `grid_brownout_at_peak`,
-- `solar_underperformance_partly_cloudy`, `__default__` and `__chaos__` carry no `_rates`.
-- **So the failure library is largely LIVE**, which inverts `0237` §E's answer to `0236` ("find a
-- declarative way to make power scarce — the answer is no"): `major_charger_outage` at 10x
-- charger_fault is exactly such a lever, and it was sitting in the table the census did not read.
--
-- ══ §5b AND THE DIVERGENCE WATCH CAUGHT TWO CASES ON ITS FIRST RUN, WHICH IS
--        WHERE `0237`'s SENTENCE IS ACTUALLY TRUE ══════════════════════════
--
-- Running §3's query immediately found two scenarios that declare a DTC multiplier and have **no
-- variability template at all**:
--
--     bench_busy_day                    scenario says 7.0    template NULL    DIVERGED
--     bench_aggressive_fleet_turnover   scenario says 1.5    template NULL    DIVERGED
--
-- `ottoq_variability_instantiate` falls back to the `'__default__'` template, which carries no
-- `_rates`, so `ottoq_profile_rate_mult` returns 1 and these two run at the BASELINE fault rate
-- while their scenario rows advertise 7x and 1.5x.
--
-- **So `0237`'s sentence is not wrong — it is misfiled.** *"A sevenfold DTC rate is declared and
-- not applied"* is false of `busy_day` and TRUE OF `bench_busy_day`. `0237` §C noted that `0309`
-- cloned scenarios to Benchmark and worried the inert copy was "now on two depots"; the real
-- situation is the reverse of what it feared — the ORIGINAL is live and the CLONE is inert,
-- because `0309` copied the `ottoq_scenarios` row and not the `ottoq_variability_profiles`
-- template. A clone that copies the declaration and not the mechanism is the duplication of §4
-- turning into a divergence, observed rather than predicted.
--
-- Not fixed here. Adding the two missing templates is a data change to the scenario library that
-- affects what `bench_*` certifies, and rule 8 makes Benchmark a non-target anyway — no run has
-- ever executed there. Recorded so nobody quotes a `bench_*` scenario's declared stress, and so
-- that whoever revives Benchmark copies templates too.
--
-- ══ §6 THE LESSON, WHICH IS A METHOD AND NOT A FACT ════════════════════════
--
-- `0237` searched for a KEY NAME. The value arrives RENAMED — `dtc_rate_multiplier` becomes
-- `_rates.dtc` — and no census of names can find a renamed value. The check that would have
-- settled it in one line was available the whole time and is an EFFECT measurement, not a search:
--
--     SELECT public.ottoq_profile_rate_mult('<run>', 'dtc');
--
-- **When asking "is this knob live?", measure the effect, not the spelling.** A grep proves a
-- string is absent; only an evaluation proves a behaviour is absent. `0237` was careful to scope
-- its claim ("this is a census of DATABASE function sources... it does NOT prove these knobs are
-- read nowhere") and the scope note was the right instinct pointed at the wrong layer — it worried
-- about edge functions and external harnesses, and the answer was in another table in the same
-- database.
--
-- ══ §7 WHAT THIS DOES TO THE CAPACITY NUMBER FROM `d68d05bb` ═══════════════
--
-- I reported to Chase that the twin depot's wall is service and wash bays — 116 vehicles wanted
-- service, 27 got a bay, `svc_cap: 2`, `wash_cap: 3`. **That measurement was taken under
-- deliberate stress and must always be quoted with it:** `arrival` 2.0 and `dtc` 7.0. It is a
-- number about a depot under a doubled arrival rate and a sevenfold fault rate, which is what
-- `busy_day` is for. It is NOT the nominal capacity of the site, and the difference is the whole
-- question Chase is asking.
--
-- **What is NOT established:** that the 7x DTC rate accounts for all 86 `tow_requested` vehicles.
-- The arithmetic does not obviously reach it — 0.0001 × 0.5 min × 7 × 1,104 ticks × an active
-- fraction near 0.45 is on the order of 17% per vehicle, or ~20 of 116, not 74%. So either the
-- active fraction is much higher than the dispatch target, or there are further fault sources:
-- `twin.ottoq_sim_vehicle_exception_handler` carries its own probability dial, and the wear path
-- (`twin.ottoq_sim_advance_wear_counters`, `ottoq_twin_wear_window`) can condemn a vehicle without
-- a DTC. **Do not attribute the 86 to the 7x until that is decomposed.** The honest sentence today
-- is: *"the 7x DTC injection is live and is one confirmed contributor; the remainder is unattributed."*

\echo '=== 0319 §1 — the key 0237 censused is still read by nothing ==='
SELECT count(*) AS functions_reading_the_scenario_key
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                      '--[^' || chr(10) || ']*', '', 'g')
       ~ '(dtc|incident)_rate_multiplier';
-- EXPECT 0. 0237 measured this correctly and it has not changed.

\echo '=== 0319 §2 — and yet the multiplier is live, under another name ==='
SELECT name,
       knobs #>> '{_rates,dtc}'      AS dtc_mult,
       knobs #>> '{_rates,incident}' AS incident_mult,
       knobs #>> '{_rates,arrival}'  AS arrival_mult
  FROM public.ottoq_variability_profiles
 WHERE sim_run_id IS NULL AND knobs #> '{_rates}' IS NOT NULL
 ORDER BY name;
-- EXPECT busy_day at dtc 7.0 / incident 0.4 / arrival 2.0 -- the same two numbers the scenario
-- declares, in the table that is actually read.

\echo '=== 0319 §3 — the scenario and the template, side by side ==='
SELECT s.scenario_code,
       s.timeline #>> '{fault_injection,dtc_rate_multiplier}'      AS scenario_says_dtc,
       t.knobs    #>> '{_rates,dtc}'                              AS template_says_dtc,
       s.timeline #>> '{fault_injection,incident_rate_multiplier}' AS scenario_says_incident,
       t.knobs    #>> '{_rates,incident}'                          AS template_says_incident,
       (s.timeline #>> '{fault_injection,dtc_rate_multiplier}')
         IS DISTINCT FROM (t.knobs #>> '{_rates,dtc}')             AS DIVERGED
  FROM public.ottoq_scenarios s
  LEFT JOIN public.ottoq_variability_profiles t
         ON t.sim_run_id IS NULL AND t.name = s.scenario_code
 WHERE s.timeline #> '{fault_injection}' IS NOT NULL
    OR t.knobs    #> '{_rates}'          IS NOT NULL
 ORDER BY s.scenario_code;
-- THE STANDING WATCH. `DIVERGED` true on any row means the scenario table advertises a fault rate
-- the engine does not run. They agree today only because one author wrote both. This is the query
-- to run before quoting any scenario's declared stress.

\echo '=== 0319 §4 — the effect measurement, which is the only proof of liveness ==='
SELECT r.scenario_code,
       left(r.sim_run_id::text,8)                                 AS run,
       public.ottoq_profile_rate_mult(r.sim_run_id,'dtc')          AS dtc_mult_applied,
       public.ottoq_profile_rate_mult(r.sim_run_id,'incident')     AS incident_mult_applied,
       public.ottoq_profile_rate_mult(r.sim_run_id,'arrival')      AS arrival_mult_applied,
       p.notes
  FROM public.ottoq_sim_runs r
  LEFT JOIN public.ottoq_variability_profiles p ON p.sim_run_id = r.sim_run_id
 ORDER BY r.started_at DESC LIMIT 5;
-- One evaluation beats any number of greps. A grep proves a string is absent; only this proves a
-- behaviour is present.
