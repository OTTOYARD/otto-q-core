-- 0283  THE MPC CHARGE CAP IS RESPECTED ON 96% OF SNAPSHOTS, NOT ALL OF THEM — SO THE
--       WORD `0389` AND `0282` USED, "THE CAP THE DECIDE PATH ENFORCES", IS TOO STRONG
--       AND IS CORRECTED HERE. THE HARD SERVICE LIMIT WAS NEVER APPROACHED.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live demo run
-- `1efeb1cd-f9b6-4515-8e61-2e5a04121112` (busy_day, seed 101959) at ~400 ticks. Energy
-- snapshots and energy commands are both `class='engine'` and purge with the run, so every
-- figure carries this run id and none of it is a claim about the table.
--
-- ══ 1. THE CORRECTION, AND WHY IT MATTERS ══════════════════════════════════
--
-- `0389` justified deriving CP-SAT's site descriptor from `ottoq_active_charge_cap_kw` by
-- quoting that function's own comment: *"this value is the site power cap the decide path
-- plans against."* `db/checks/0282` §4 then wrote **"the cap the decide path enforces."**
-- Those are not the same verb and the measurement below supports only the first.
--
--   snapshots on this run                                    **399**
--   snapshots with a cap reconstructible at their own time    **399**
--   snapshots where aggregate EV charging EXCEEDED that cap    **17  (4.3%)**
--   worst excursion                                        **344 kW**
--   mean excursion, over the 17                             **92 kW**
--   cap range over the run                          **372 – 1,826 kW**
--   EV charging peak                                     **1,618 kW**
--
-- So the cap is a strong advisory that holds 95.7% of the time, not an inviolable
-- constraint. The cuOpt edge function has been saying so in its own fire records the whole
-- time -- `energy.cap_enforced: false`, with `would_trim_by_cap: 6` against
-- `trimmed_by_cap: 0` -- and 0282 should have read that field rather than the function's
-- comment. **SAY: "the cap the decide path plans against, and stays under on 96% of
-- snapshots." DO NOT SAY it enforces one.**
--
-- **This does not weaken `0389`.** Its change was to stop handing CP-SAT a constant 2500 kW
-- when the engine's own cap was several times lower; that is right whether the cap is
-- enforced or advisory, and arguably more useful if advisory, since a solver that plans
-- under the advisory cap is how the excursions get smaller. What 0389 must not be quoted as
-- is a fix to an enforcement gap. It is a fix to a modelling INPUT.
--
-- ══ 2. AND THE HARD LIMIT IS NOT THE ONE AT ISSUE ══════════════════════════
--
-- `depots.service_max_kw` is **2,500 kW** and nothing on this run came near it: EV charging
-- peaked at 1,618 kW and grid import at 1,672 kW. The two numbers must not be conflated --
-- 2,500 is the wire, and the MPC's `charge_cap_kw` is a dispatch decision inside it that
-- moved by a factor of five during one night.

WITH s AS (
  SELECT "timestamp" AS ts, total_ev_charging_kw AS ev, grid_import_kw AS gi
    FROM public.site_energy_snapshots
   WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
     AND depot_id   = '11111111-1111-1111-1111-111111111111'),
c AS (
  SELECT s.*,
         (SELECT e.setpoint_kw FROM public.ottoq_energy_commands e
           WHERE e.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
             AND e.command_type = 'charge_cap_kw'
             AND e.issued_at <= s.ts
           ORDER BY e.issued_at DESC, e.tick_seq DESC NULLS LAST LIMIT 1) AS cap
    FROM s)
SELECT count(*) AS snapshots,
       count(cap) AS with_a_cap,
       count(*) FILTER (WHERE ev > cap) AS ev_over_cap,
       round(100.0 * count(*) FILTER (WHERE ev > cap) / NULLIF(count(cap), 0), 1) AS pct_over,
       round(max(ev - cap)) AS worst_over_kw,
       round(avg(ev - cap) FILTER (WHERE ev > cap)) AS mean_over_kw,
       round(min(cap)) AS cap_min_kw, round(max(cap)) AS cap_max_kw,
       round(max(ev)) AS ev_peak_kw, round(max(gi)) AS grid_peak_kw,
       (SELECT round(service_max_kw) FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS hard_service_kw
  FROM c;

-- ══ 3. A MECHANISM I PROPOSED AND THE DATA REFUSED ═════════════════════════
--
-- The obvious story is a tightening transient: the MPC re-issues the cap every tick, a
-- session admitted under a high cap keeps drawing when the cap drops, and the excursion is
-- the lag. **The data does not support it.** Over the 17 excursions the mean tick-over-tick
-- cap change was **−8 kW**, and the single largest drop on the whole run, **−753 kW**,
-- occurred on a snapshot that stayed UNDER its cap. The excursions instead sit at a mean
-- cap of 757 kW against a mean EV draw of 849 kW -- ordinary drift above an ordinary cap,
-- not a step response.
--
-- **So the mechanism is not established, and that is the finding.** It is recorded as an
-- open question rather than dressed as an answer: a plausible causal story that the numbers
-- decline to confirm is worth exactly one paragraph and no conclusions.

WITH s AS (
  SELECT "timestamp" AS ts, total_ev_charging_kw AS ev
    FROM public.site_energy_snapshots
   WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
     AND depot_id   = '11111111-1111-1111-1111-111111111111'),
c AS (
  SELECT s.*,
         (SELECT e.setpoint_kw FROM public.ottoq_energy_commands e
           WHERE e.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
             AND e.command_type = 'charge_cap_kw' AND e.issued_at <= s.ts
           ORDER BY e.issued_at DESC, e.tick_seq DESC NULLS LAST LIMIT 1) AS cap
    FROM s),
d AS (SELECT ts, ev, cap, cap - lag(cap) OVER (ORDER BY ts) AS cap_delta FROM c)
SELECT (ev > cap) AS over_cap, count(*) AS n,
       round(avg(cap)) AS mean_cap_kw, round(avg(ev)) AS mean_ev_kw,
       round(avg(cap_delta)) AS mean_cap_delta_kw,
       round(min(cap_delta)) AS worst_cap_drop_kw
  FROM d GROUP BY 1 ORDER BY 1;

-- ══ 4. A READER TRAP IN `ottoq_active_charge_cap_kw`, AND I FELL IN IT FIRST ═
--
-- The function is **correct for "now" and cannot answer a historical question**, and
-- nothing about it says so. It filters `status = 'executed'`, and the MPC supersedes: this
-- run holds **396** `charge_cap_kw` commands of which **395 are `superseded` and exactly 1
-- is `executed`**. Asked about any past timestamp it therefore returns the ONE current
-- command, because that is the only row that passes the status filter -- and it passes for
-- every input clock, since its `issued_at + horizon >= p_sim_clock` test is satisfied by a
-- command issued after the clock asked about.
--
-- **Two wrong numbers came out of that before a right one did**, and both are recorded
-- because the shape repeats:
--
--   (a) Calling the function per snapshot returned a CONSTANT cap for all 382 snapshots and
--       produced "371 of 382 over cap, worst 1,221 kW". That was the current cap compared
--       against the whole run's history. **Retracted.**
--   (b) Adding `issued_at <= ts` to the function's own predicate returned a cap for **1**
--       snapshot of 387, because the status filter had already discarded the 395 superseded
--       rows that carry the history. "0 of 1 over cap" is technically true and answers
--       nothing. **Retracted.**
--
-- Only (c) -- reading `ottoq_energy_commands` directly, taking the latest command issued at
-- or before each snapshot **regardless of status** -- reconstructs what was actually in
-- force. That is §2's number.
--
-- **The general rule this earns:** a function whose name is a present tense
-- (`..._active_...`) is a question about now, and a superseding writer means its history
-- lives in the rows it filters out. Reconstruct from the table, never by re-calling the
-- accessor with an old clock. Note this does NOT affect `0389`: the descriptor is built at
-- the current clock, which is the one input the function answers correctly.

SELECT command_type, status, count(*) AS n,
       min(issued_at)::timestamp(0) AS first_issued,
       max(issued_at)::timestamp(0) AS last_issued,
       round(min(setpoint_kw)) AS setpoint_min, round(max(setpoint_kw)) AS setpoint_max
  FROM public.ottoq_energy_commands
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
   AND command_type = 'charge_cap_kw'
 GROUP BY 1, 2 ORDER BY n DESC;

-- ══ 5. AND ONE HYPOTHESIS ABOUT CLOCKS THAT WAS ALSO WRONG ═════════════════
--
-- I suspected `issued_at` was wall-clock while `p_sim_clock` is sim-clock -- a mismatch that
-- would make the horizon test meaningless, and the kind of defect CLAUDE.md rule 7 exists to
-- catch. **It is not.** This run's current command carries `issued_at = 2026-09-20
-- 04:25:09`, which is its `sim_clock_current` to the second, against a real `now()` of
-- 19:55. `issued_at` is sim time and the function's arithmetic is sound. Recorded because a
-- clock-domain suspicion is cheap to check -- one query comparing the two columns -- and
-- expensive to carry around unchecked.

SELECT (SELECT max(issued_at)::timestamp(0) FROM public.ottoq_energy_commands
         WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
           AND command_type = 'charge_cap_kw') AS last_command_issued_at,
       sim_clock_current::timestamp(0) AS run_sim_clock,
       now()::timestamp(0)             AS real_clock,
       'issued_at tracks the SIM clock, not the wall clock' AS finding
  FROM public.ottoq_sim_runs
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112';
