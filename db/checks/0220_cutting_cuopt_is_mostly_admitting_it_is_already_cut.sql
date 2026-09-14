-- 0220  CUTTING CUOPT IS MOSTLY ADMITTING IT IS ALREADY CUT
--
-- Read-only. Chase's instruction was "definitely cut cuOpt." Before changing
-- anything, this measures what "cuOpt" currently IS in the live engine -- and
-- the answer changes what the cut should be, and makes it far smaller and far
-- more dangerous in one specific place than the instruction implies.
--
-- ===========================================================================
-- 1. THE GATE IS ALREADY CLOSED AT EVERY SCOPE THAT SETS IT

SELECT param_key, scope_type, count(*) AS rows, min(param_value) AS lo, max(param_value) AS hi,
       max(updated_at)::date AS last_written
  FROM public.ottoq_policy_params WHERE param_key ILIKE '%cuopt%'
 GROUP BY 1,2 ORDER BY 1,2;

--   cuopt_propose_enabled   global    1 row   0 .. 0     2026-09-02
--                           depot     1 row   0 .. 0     2026-09-09
--                           run     677 rows  0 .. 0     2026-09-13
--
-- Every scope, every row, zero. And the GLOBAL row is what makes it stick:
-- ottoq_cuopt_defer_hold reads the key with a CALLER DEFAULT OF 1, so a run
-- with no row of its own would enable cuOpt -- except that ottoq_policy_get
-- resolves run -> depot -> global before it ever reaches the caller default,
-- and the global row says 0. One row is holding the whole thing off.
--
-- ===========================================================================
-- 2. THE ENDPOINT HAS BEEN SILENT FOR FIFTEEN DAYS, AND THE LEDGER'S ROW
--    COUNT DOES NOT MEASURE CALLS

SELECT stage, count(*) AS rows_all_time,
       count(*) FILTER (WHERE called_at > now() - interval '2 days') AS rows_last_2d,
       count(*) FILTER (WHERE http_status IS NOT NULL) AS actual_http_calls,
       max(called_at)::date AS last
  FROM public.cuopt_invocation_log GROUP BY 1 ORDER BY 2 DESC;

--   stage      rows all time   last 2 days   ACTUAL HTTP CALLS   last row
--   sql_gate          19,995         2,249                   0   2026-09-14
--   edge                 538             0                  16   2026-09-09
--
--   rows in cuopt_invocation_log                       20,533
--   rows carrying an http_status (a real NVIDIA call)       16
--   proposals those 16 calls returned                      136
--   last real call                     2026-08-30 04:36:02 UTC
--   silent for                                 15 days 2 hours
--
-- THE NUMBER TO NEVER QUOTE IS 20,533. CLAUDE.md's Part 3 has carried this
-- ledger as "cuOpt invocations" through three refreshes -- 255, then 12,478,
-- then 15,346 -- and every one of those is a count of LEDGER ROWS, of which
-- 19,995 are sql_gate rows recording that the gate declined to call anything.
-- The count of times this engine has actually called NVIDIA, over its whole
-- life, is SIXTEEN. That is consistent with SOLVER_STATE §9's own derivation
-- (16 calls, 136 proposals); what is new here is that the row count has since
-- grown by another ~5,000 while the call count has not moved at all.
--
-- And it is still growing: 2,249 sql_gate rows in the last two days, the most
-- recent today. A reader who equates rows with invocations would conclude
-- cuOpt is busier than ever. It has not placed a call in fifteen days.
--
-- ===========================================================================
-- 3. WHAT "CUOPT" IS AS CODE -- eight functions, two of which read the gate

SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc ILIKE '%cuopt_propose_enabled%') AS reads_the_gate,
       length(p.prosrc) AS src_len
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.proname ILIKE '%cuopt%' AND n.nspname IN ('public','twin','ottoq') ORDER BY 1;

--   public.cuopt_invocation_log_append_only     no     94
--   public.cuopt_log_gate                       no    763
--   public.ottoq_cuopt_defer_arm                no  1,701
--   public.ottoq_cuopt_defer_hold              YES  2,477   <-- SHARED
--   public.ottoq_cuopt_defer_roll               no    930
--   public.ottoq_cuopt_first_refusal_arm        no  2,944
--   public.ottoq_cuopt_refresh                 YES  9,163   <-- the invoker
--   public.ottoq_fn_backup_enact_cuopt_batch    no  6,463   (already a backup)
--
-- ===========================================================================
-- THE FINDING THAT CHANGES THE PLAN
--
-- FIVE OF THOSE EIGHT ARE NOT CUOPT. They are the propose/dispose deferral
-- machinery, which carries a cuOpt name for historical reasons and is now
-- LOAD-BEARING FOR THE CP-SAT PROPOSER that 0218 armed this morning:
--
--   ottoq_cuopt_defer_hold releases on
--     (cuopt_propose_enabled >= 1 OR proposer_hold_enabled >= 1)
--     AND ... p.source IN (SELECT source FROM ottoq_proposer_precedence
--                           WHERE holds_tick)
--
--   and ottoq_proposer_precedence declares holds_tick for FOUR sources:
--     cuopt (rank 0), cuopt_fallback (1), forward_lex (10), llm_advisor (20).
--
-- So the right-of-first-refusal is already source-neutral by design; only the
-- NAMES are cuOpt's. 0284's new ottoq_first_refusal_outcomes measures holds
-- for all four. And 0278's arming writes cuopt_first_refusal_max_defers=1 on
-- every armed run -- 636 run rows, most written TODAY, by the agentic layer,
-- through a key with cuOpt in its name.
--
-- CUTTING "EVERYTHING CUOPT" BY NAME WOULD THEREFORE CUT THE CP-SAT PROPOSER'S
-- RIGHT OF FIRST REFUSAL ON THE SAME DAY IT FIRST WORKED. That is the one
-- genuinely dangerous move available here, and it is the move the instruction
-- most naturally reads as.
--
-- ===========================================================================
-- THE CUT, IN THE ORDER IT IS SAFE TO DO IT (not executed here)
--
--   1. PIN THE GATE, don't just leave it. cuopt_propose_enabled is 0 at global
--      scope because someone wrote it there; ottoq_cuopt_defer_hold's caller
--      default is still 1, so DELETING that row would turn cuOpt back ON for
--      every run without one. The first migration changes the caller default
--      to 0 so the off state stops depending on a single data row.
--
--   2. RETIRE THE INVOKER. ottoq_cuopt_refresh is the only function that calls
--      the endpoint. It is the whole cut: gate it to an immediate no-op, keep
--      the body as ottoq_fn_backup_* the way the repo already does, and stop
--      writing 2,249 sql_gate rows every two days to record a call that is
--      never attempted.
--
--   3. RENAME NOTHING YET. The five deferral functions keep their cuOpt names
--      until the CP-SAT path has more than one armed run of evidence behind it
--      (0219/G54). A rename is a CREATE + a call-site sweep across
--      ottoq_decide_tick, and doing it in the same window as a behavioural
--      change is how a rename becomes an outage.
--
--   4. CORRECT THE QUOTED NUMBER. CLAUDE.md Part 3 and rule 6 must stop
--      carrying the ledger row count as "invocations". The honest sentence:
--      "cuOpt was called sixteen times in this engine's life, returned 136
--      proposals, and has not been called since 2026-08-30; the 20,533-row
--      ledger is 19,995 gate refusals and 538 edge rows."
--
-- Step 4 is free and can be done now. Steps 1 and 2 are one small migration
-- each and want a quiesced window. Step 3 waits on evidence.
