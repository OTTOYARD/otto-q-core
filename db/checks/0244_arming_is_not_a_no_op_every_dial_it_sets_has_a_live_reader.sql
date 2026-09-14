-- ============================================================================
-- 0244 — ARMING IS NOT A NO-OP. EVERY DIAL IT SETS HAS A LIVE READER ON THE
--        DECIDE PATH.
-- ============================================================================
-- Measured 2026-09-14 19:52 UTC, immediately after 0323 was applied.
--
-- THE QUESTION WORTH ASKING, and the one that would have made 0323 worthless:
-- 0323 made both run doors call ottoq_agentic_arm, closing the gap where 1,147
-- runs had booted with the proposer door shut. But a migration that writes dials
-- NOBODY READS closes nothing -- it moves the gap one layer down and makes it
-- harder to see. G52 is exactly that failure in another component ("the
-- dial-writing agent has no seat in the decide path").
--
-- READ THE ASSIGNMENT FIRST (0235). ottoq_agentic_arm sets exactly three dials:
--
--     proposer_frame_facts            = 1
--     proposer_hold_enabled           = 1
--     cuopt_first_refusal_max_defers  = 1
--
-- and refuses a run_by='cert_harness' run with ERRCODE 42501, so a certification
-- arm can never be armed -- the guarantee 0323's own guard leans on.
--
-- THEN FIND THE READERS. Measured:
--
--   proposer_frame_facts            -> public.ottoq_build_decision_frame
--   proposer_hold_enabled           -> public.ottoq_cuopt_defer_hold
--   cuopt_first_refusal_max_defers  -> public.ottoq_cuopt_first_refusal_arm
--                                      public.ottoq_sim_decide_and_dispatch
--
-- All four are on the live decide path, and the first is the frame builder
-- itself -- so arming genuinely changes what the proposer is shown, which is the
-- whole point. THE GAP IS CLOSED, not moved.
--
-- ONE PRECISION, because this file would otherwise repeat the defect it guards
-- against. A naive search for the dial name also returns
-- public.ottoq_sim_run_scenario and twin.ottoq_sim_start_run. Those two do NOT
-- read the dial -- they contain the string because 0323's injected COMMENT
-- explains why the cert_harness guard is not optional. That is the same
-- text-versus-code trap that made 0323's own A1 abort on its first apply. The
-- assertions below therefore exclude the two start doors by name and say why,
-- rather than reporting six readers where there are four.
--
-- ALSO EXCLUDED, and for a different reason: ottoq_agentic_arming (the view over
-- armed runs), ottoq_ab_pair, ottoq_determinism_pair and
-- ottoq_determinism_pair_replay. Those are harness and reporting objects, not
-- the decide path. Counting them would inflate the answer with instruments that
-- observe the dial rather than obey it.
--
-- WHAT MAY BE SAID: "arming sets three dials and each is read by the decide
-- path; the frame builder reads the one that changes what a proposer sees."
-- WHAT MAY NOT: that a UI-started run has been observed armed end to end. At the
-- time of measurement no non-certification run had started since 0323 applied,
-- so ottoq_sim_runs.payload->'agentic_arm' -- the receipt 0323 writes -- has no
-- rows to show. That is the remaining proof and it needs one twin run started
-- through the UI door, which cannot happen while a certification round is in
-- flight.
-- ============================================================================

-- A1. The three dials, read from the arming function rather than from memory.
SELECT 'A1 dials armed' AS assertion,
       (p.prosrc ~ 'proposer_frame_facts')           AS sets_frame_facts,
       (p.prosrc ~ 'proposer_hold_enabled')          AS sets_hold,
       (p.prosrc ~ 'cuopt_first_refusal_max_defers') AS sets_first_refusal,
       (p.prosrc ~ 'cert_harness')                   AS refuses_cert_arms
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agentic_arm';

-- A2. THE LOAD-BEARING ONE: each dial has at least one DECIDE-PATH reader.
--     Excludes the arming function itself, the two start doors (which only
--     mention the dial in 0323's comment), and the harness/reporting objects.
WITH dials(d) AS (VALUES
    ('proposer_frame_facts'),
    ('proposer_hold_enabled'),
    ('cuopt_first_refusal_max_defers'))
SELECT 'A2 readers' AS assertion,
       dials.d AS dial,
       count(p.oid) AS decide_path_readers,
       coalesce(string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY p.proname),
                '(NOBODY READS THIS -- arming would be a no-op)') AS who
  FROM dials
  LEFT JOIN pg_proc p ON p.prosrc LIKE '%' || dials.d || '%'
  LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
   AND n.nspname IN ('public','twin','ottoq')
 WHERE (n.nspname IS NOT NULL OR p.oid IS NULL)
   AND coalesce(p.proname, '') NOT IN (
         'ottoq_agentic_arm',            -- the writer
         'ottoq_sim_run_scenario',       -- comment only (0323)
         'ottoq_sim_start_run',          -- comment only (0323)
         'ottoq_agentic_arming',         -- reporting view function
         'ottoq_ab_pair',                -- harness
         'ottoq_determinism_pair',       -- harness
         'ottoq_determinism_pair_replay' -- harness
       )
 GROUP BY dials.d
 ORDER BY dials.d;

-- A3. The frame builder specifically. If this one ever stops reading
--     proposer_frame_facts, arming stops changing what the proposer is shown and
--     every claim above is void, whatever the other two dials do.
SELECT 'A3 frame builder' AS assertion,
       (p.prosrc ~ 'proposer_frame_facts') AS frame_builder_reads_the_dial
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame';

-- A4. The receipt 0323 writes. Expect ZERO rows until a non-certification run
--     starts -- which is the honest state, not a failure.
SELECT 'A4 receipts' AS assertion,
       count(*) AS armed_runs,
       count(*) FILTER (WHERE (payload->'agentic_arm'->>'ok')::boolean) AS armed_ok,
       max(started_at) AS newest
  FROM public.ottoq_sim_runs
 WHERE payload ? 'agentic_arm';
