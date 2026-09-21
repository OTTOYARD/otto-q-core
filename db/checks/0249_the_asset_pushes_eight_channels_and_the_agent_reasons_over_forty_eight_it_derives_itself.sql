-- 0249  THE ASSET PUSHES EIGHT CHANNELS. THE AGENT REASONS OVER FORTY-EIGHT
--       THAT OTTO-Q DERIVES ITSELF. AND I CLAIMED TWO OF THE DARK ONES WERE
--       POPULATED.
--
-- Chase asked the architecture question directly: "does the agent need to see
-- all the variable lists, or just the variables that are pushed to it? ... Should
-- OTTO-Q also have insight into all possible variables? Maybe it knows all
-- possible variables and is scanning for those ... maybe the optimum is to know
-- both?"
--
-- It was answered in prose and never measured. This file measures it, on run
-- dde654cc-b734-4c75-a401-0358f4e02d2d (busy_day, armed 7/7, 1,112 ticks,
-- completed), by counting NOT-NULL per column rather than by reading a schema.
--
-- ── 0. THE CORRECTION FIRST, BECAUSE IT IS MINE ────────────────────────────
--
-- Migration 0350's commit message says the per-asset variables are "populated"
-- and names four telemetry columns as examples: `dtc_codes`, `active_warnings`,
-- `packet_integrity`, `dropped_reason`. Measured on the same run:
--
--   packet_integrity    16,771 of 16,771   correct
--   dropped_reason         523 of 16,771   correct -- exactly the dropped packets
--   dtc_codes                5 of 16,771   0.03%
--   active_warnings          0 of 16,771   NEVER CARRIED
--
-- So two of the four I named as populated are not. `active_warnings` has never
-- carried a value on this run, and `dtc_codes` carried five. The schema is deep;
-- the FEED is not, and I wrote the reassuring version of that sentence without
-- counting. The finding 0350 was built on -- that the agent could not see
-- per-asset detail -- is unaffected and was correct. The claim about the
-- telemetry feed's depth was not.
--
-- ══ 1. WHAT THE ASSET ACTUALLY PUSHES ══════════════════════════════════════
--
-- ottoq_telemetry_packets, 30 columns, 16,771 rows on this run. Per column:
--
--   always populated (13)  the 8 signal channels below plus ids, timestamps,
--                          packet_integrity and signal_strength_pct
--   never populated  (7)   active_warnings · cabin_temp_c · heading_deg
--                          motor_temp_c · odometer_km · power_15min_avg_kw
--                          range_remaining_km
--   partial          (10)  dtc_codes 5 · dropped_reason 523 · and the 8 signal
--                          channels at 16,248 (96.9%)
--
-- THE EIGHT CHANNELS THAT CARRY PHYSICS, each 16,248 of 16,771:
--
--   soc_pct · battery_temp_c · ambient_temp_c · instant_power_kw
--   speed_kmh · current_lat · current_lng · tire_pressures_psi
--
-- The missing 3.1% is not a gap: 16,771 - 16,248 = 523, which is exactly the
-- `dropped` packet count, and a dropped packet is modelled as carrying no
-- reading. So the feed is internally consistent -- it is narrow, not broken.
--
-- ══ 2. WHAT OTTO-Q DERIVES ═════════════════════════════════════════════════
--
-- vehicle_need_profile, 48 columns, 220 rows. ZERO always-null columns.
--
--   always populated (40)
--   conditionally populated (8), and every one is conditional for a REASON
--     rather than from a gap:
--       next_deploy_at        92%   -- vehicles without a scheduled deploy
--       wear_km_applied       52%   -- and wear_km_applied_run, same 52%
--       dcfc_block_reason     16%   -- exactly the DCFC-blocked population
--       item_description      14%   -- and item_reported_at, same 14%
--       rider_flag_kind        2%   -- and rider_flag_due_at, same 2%
--
-- Each pair moves together, which is what a correctly-modelled optional field
-- looks like. Nothing here is silently empty.
--
-- ══ 3. SO THE ANSWER TO THE QUESTION ═══════════════════════════════════════
--
-- Today the agent reasons ALMOST ENTIRELY OVER DERIVED STATE.
--
--   pushed by the asset   8 physical channels
--   derived by OTTO-Q     48 of 48 columns carrying data
--
-- Every fault, every deadline, every interlock the agent acts on --
-- open_fault_codes, worst_fault_severity, priority_class, dcfc_safe +
-- dcfc_block_reason, battery_soh, sensor_health, tire_tread_mm, brake_wear_pct,
-- next_deploy_at -- is on the OTTO-Q side of the boundary. The depth is real. It
-- is just not arriving from the asset.
--
-- Which means the "happy medium" Chase guessed at is already the shape of the
-- system, but lopsided: OTTO-Q knows a great deal and is TOLD very little. A
-- real OEM feed would invert that ratio, and the eight channels are exactly the
-- eight an OEM would send first, so the ingress contract is right as far as it
-- goes.
--
-- ══ 4. THE PART THAT IS A RISK RATHER THAN A CURIOSITY ══════════════════════
--
-- The OTTO-TWIN repo's law: "If you build a code path that only works because
-- this is a simulation, you have broken the pitch."
--
-- The inverse bites here. Seven telemetry columns exist in the contract and have
-- NEVER been emitted by the twin, so no OTTO-Q code path that consumes them from
-- telemetry has ever executed. `active_warnings` is the sharpest: it is the
-- warnings channel, an OEM would push it on day one, and on this run it is
-- 0 of 16,771. `range_remaining_km` is the second: ottoq_agent_asset_depth
-- already surfaces `min_range_remaining_km` and it reads NULL for that reason.
--
-- So the swap test is narrower than "unplug the twin, plug in a real depot."
-- It holds for the eight channels. For the other seven it is untested, and
-- untested is not the same as working. That is not an argument for removing the
-- columns -- it is an argument for the twin emitting them, which is a
-- twin-side build and belongs to whoever owns twin.ottoq_sim_emit_telemetry.
--
-- Tracked as G70. Nothing in this file changes engine state; it is measurement.
--
-- ── ONE NOTE ON RE-DERIVING THESE NUMBERS ──────────────────────────────────
--
-- ottoq_telemetry_packets is class `engine` in ottoq_run_scope_registry, so the
-- next ottoq_start_demo_run purges dde654cc's 16,771 packets and Q1/Q3 below
-- return nothing for that run id. That is the registry working, not data loss:
-- the figures are recorded above precisely because the rows are not permanent.
-- To re-derive on a later run, substitute its sim_run_id. Q2 (the derived
-- profile), Q4 (the ingress census) and Q5 are run-independent and keep working.
--
-- ── THE QUERIES, so every number above can be re-derived ───────────────────

-- Q1  per-column NOT-NULL census of the pushed feed, scoped to one run.
--     to_jsonb(t) rather than dynamic SQL: it needs no column list, so a column
--     added tomorrow appears here without this file being edited.
WITH tp AS (
  SELECT e.k,
         count(*) FILTER (WHERE e.v <> 'null'::jsonb) AS populated,
         count(*)                                     AS rows
    FROM public.ottoq_telemetry_packets t,
         jsonb_each(to_jsonb(t)) AS e(k, v)
   WHERE t.sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d'
   GROUP BY 1
)
SELECT k, populated, rows, round(100.0 * populated / rows, 1) AS pct,
       CASE WHEN populated = 0    THEN 'NEVER CARRIED'
            WHEN populated = rows THEN 'always'
            ELSE 'partial' END AS verdict
  FROM tp
 ORDER BY populated, k;

-- Q2  the same census over what OTTO-Q derives. No run predicate: the profile is
--     per-vehicle and not run-scoped.
WITH np AS (
  SELECT e.k,
         count(*) FILTER (WHERE e.v <> 'null'::jsonb) AS populated,
         count(*)                                     AS rows
    FROM public.vehicle_need_profile p,
         jsonb_each(to_jsonb(p)) AS e(k, v)
   GROUP BY 1
)
SELECT k, populated, rows, round(100.0 * populated / rows) AS pct
  FROM np
 WHERE populated < rows
 ORDER BY populated, k;

-- Q3  the consistency check that makes "narrow, not broken" a measurement
--     rather than a hope: the shortfall on every signal channel must equal the
--     dropped-packet count exactly.
SELECT (SELECT count(*) FROM public.ottoq_telemetry_packets
         WHERE sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d')            AS packets,
       (SELECT count(*) FROM public.ottoq_telemetry_packets
         WHERE sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d'
           AND packet_integrity = 'dropped')                                   AS dropped,
       (SELECT count(*) FROM public.ottoq_telemetry_packets
         WHERE sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d'
           AND soc_pct IS NULL)                                                AS soc_null,
       ((SELECT count(*) FROM public.ottoq_telemetry_packets
          WHERE sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d'
            AND packet_integrity = 'dropped')
        = (SELECT count(*) FROM public.ottoq_telemetry_packets
            WHERE sim_run_id = 'dde654cc-b734-4c75-a401-0358f4e02d2d'
              AND soc_pct IS NULL))                                            AS shortfall_is_exactly_dropped;

-- Q4  the ingress boundary, re-asserted because section 3's conclusion rests on
--     it: exactly one routine inserts telemetry, and it is twin-side, so a real
--     OEM feed replaces ONE writer. (0350 established this; it is re-derived
--     here rather than cited, because a boundary claim that is only ever quoted
--     stops being measured.)
--
--     AND THE FIRST VERSION OF THIS QUERY WAS WRONG IN THIS FILE'S OWN FAVOURITE
--     WAY. It read `prosrc ILIKE '%insert into%ottoq_telemetry_packets%'`, which
--     matches any routine mentioning both strings ANYWHERE in its body, and
--     returned THREE names -- so the file would have carried "exactly one
--     inserter" above a query returning three. Anchored on the comment-stripped
--     body it returns one, and 0350's census was right all along. Twelve
--     routines mention the table; eleven only read it.
SELECT n.nspname || '.' || p.proname AS inserter
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
         ~* 'insert\s+into\s+(public\.)?ottoq_telemetry_packets'
 ORDER BY 1;

-- Q5  and the seven dark channels named as data, so a twin-side build has a
--     work list rather than a paragraph.
SELECT unnest(ARRAY['active_warnings','range_remaining_km','odometer_km',
                    'motor_temp_c','cabin_temp_c','heading_deg',
                    'power_15min_avg_kw']) AS never_emitted_column;
