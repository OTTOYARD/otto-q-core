-- ============================================================================
-- 0243 — THE HUB TAKES DELIVERY ON BOTH SIDES AND HAS NEVER SHIPPED ANYTHING
--        OUT. INBOUND IS REAL, THE FLOOR IS REAL, THE DOCK HAS NO TRUCKS.
-- ============================================================================
-- Measured 2026-09-14 ~19:05 UTC (2:05 PM CT), answering Chase's question
-- directly: "make sure the variable/twin data and communication is being either
-- sent or received accordingly ... almost like a logistics hub, where things
-- come in, they're sorted and optimized and placed into the correct location
-- for output."
--
-- The metaphor is exact, and it is the right test. Measured against it:
--
-- ── INBOUND: REAL, AND THIS IS THE LOAD-BEARING RESULT ──────────────────────
-- The twin is NOT special-cased. It writes through the same tables a real feed
-- writes, separated only by data_source. That is CLAUDE.md 2.8's co-existence
-- discipline, and it is holding:
--
--   ottoq_telemetry_packets   419,665 twin
--   ottoq_ocpp_messages       533,980 twin
--   ottoq_events              829,138 twin  +  3,991 production
--   ottoq_vehicle_commands    820,348 twin  +      1 production
--   ottoq_energy_commands      36,659 twin
--
-- production rows sit in the SAME tables as twin rows. So the orchestration
-- layer cannot tell which it is reading, which is the entire reason a twin
-- result is worth anything. This half needs no work.
--
-- ── THE FLOOR: REAL ─────────────────────────────────────────────────────────
-- Run e02e92b4 (48 ticks, ordinary twin entry point): 122 stall_assignment
-- decisions, 1,420 rule-gated task starts, 541 bookings, 629 recall decisions,
-- 43 SDRs, 24 energy commands, 5 live proposals (a per-tick working set --
-- see 0242 before counting those).
--
-- ── OUTBOUND: TWO DIFFERENT PROBLEMS, AND ONLY ONE OF THEM IS A HOLE ────────
--
-- (1) ottoq_vehicle_commands HAS a full outbound lifecycle. The columns exist
--     -- status, delivered_at, delivered_to, confirmed_at, confirmed_by,
--     executed_at, reason_code -- and public.ottoq_fleet_claim_commands is a
--     real claim-and-lease: FOR UPDATE ... SKIP LOCKED, bounded batch, actor
--     recorded. Measured across all 822,887 commands:
--
--       status    n        delivered  confirmed  executed  distinct consumers
--       executed  468,420          0    468,420   468,420                   0
--       refused   327,408          0    327,408         0                   0
--       expired    26,594          0     26,593         0                   0
--       issued        465          0          0         0                   0
--
--     delivered_at has NEVER been set. Not once, in 822,887 rows. And the
--     reason is in the claim function's own predicate:
--
--         AND c.data_source = 'production'   -- 0271's rule; a twin command is
--                                            -- never delivered
--
--     That gate is CORRECT -- a twin command must never reach a real vehicle.
--     But its consequence is the finding: THE TWIN SHORT-CIRCUITS THE DELIVERY
--     PATH ENTIRELY. It enacts its own commands internally, which is why
--     executed=468,420 while delivered=0. So the twin proves the inbound side
--     and the floor, and proves NOTHING WHATEVER about the outbound contract.
--     With exactly 1 production command ever written, that contract has never
--     carried traffic and has never been tested by anything.
--
--     This is a socket that is built and unplugged, not a missing socket.
--     It is G8's measured basis.
--
-- (2) ottoq_energy_commands has NO delivery lifecycle AT ALL. Its full column
--     list:
--
--       command_id, sim_run_id, depot_id, tick_seq, issued_at, source,
--       command_type, setpoint_kw, horizon_min, reason, status, executed_at,
--       executed_note, data_source, created_at
--
--     No delivered_at. No delivered_to. No confirmed_at/confirmed_by. No claim
--     function anywhere in the database writes it. 36,659 rows and no way for
--     an external consumer to take delivery of one or acknowledge it.
--
--     THIS IS THE ACTUAL HOLE, and it matters more than it looks: energy is a
--     named inbound feed, so the hub accepts energy data and cannot ship energy
--     instructions back out through any audited path. It is also exactly where
--     CLAUDE.md 2.5's publication boundary has to be enforced -- forward
--     schedules out, never real-time setpoints -- and a lifecycle is where that
--     boundary would be expressed. G9 adjacent; this is its measured basis.
--
-- ── THE ASYMMETRY, STATED ONCE ──────────────────────────────────────────────
-- Vehicles have a dock with no trucks. Energy has no dock. Neither is broken
-- today because nothing external is connected; both block "production" in any
-- sense that involves a second party.
--
-- WHAT MAY BE SAID. SAY: "inbound is shared-table and proven at volume; the
-- orchestration floor is proven; the outbound contract exists for vehicles,
-- is correctly gated against twin traffic, and has never been exercised."
-- DO NOT SAY the loop is closed end to end. It is closed IN and THROUGH. It
-- is not closed OUT.
-- ============================================================================

-- A1. Inbound co-existence: twin and production in the same tables.
SELECT 'A1 inbound' AS assertion, 'ottoq_events' AS tbl, COALESCE(data_source,'(null)') AS src, count(*) AS n
  FROM ottoq_events GROUP BY 3
UNION ALL
SELECT 'A1 inbound', 'ottoq_vehicle_commands', COALESCE(data_source,'(null)'), count(*)
  FROM ottoq_vehicle_commands GROUP BY 3
UNION ALL
SELECT 'A1 inbound', 'ottoq_telemetry_packets', COALESCE(data_source,'(null)'), count(*)
  FROM ottoq_telemetry_packets GROUP BY 3
 ORDER BY 2, 4 DESC;

-- A2. THE FINDING: delivered_at has never been set on any vehicle command.
--     Expect delivered = 0 and distinct_consumers = 0 on every status.
SELECT 'A2 never delivered' AS assertion,
       status, count(*) AS n,
       count(delivered_at)          AS delivered,
       count(confirmed_at)          AS confirmed,
       count(executed_at)           AS executed,
       count(DISTINCT delivered_to) AS distinct_consumers
  FROM ottoq_vehicle_commands
 GROUP BY status
 ORDER BY n DESC;

-- A3. The gate that explains it, quoted from the live function.
SELECT 'A3 production-only gate' AS assertion,
       p.proname,
       (p.prosrc ~* 'data_source\s*=\s*''production''') AS gated_to_production
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_fleet_claim_commands';

-- A4. THE HOLE: ottoq_energy_commands has no delivery columns.
--     Expect zero rows. Any row returned means the hole has been closed.
SELECT 'A4 energy has no dock' AS assertion, column_name
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'ottoq_energy_commands'
   AND column_name IN ('delivered_at','delivered_to','confirmed_at','confirmed_by')
 ORDER BY column_name;

-- A5. And nothing anywhere claims an energy command. Expect zero rows.
SELECT 'A5 no energy claimer' AS assertion, n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc ~* 'ottoq_energy_commands'
   AND p.prosrc ~* 'delivered_at|delivered_to'
 ORDER BY 2;
