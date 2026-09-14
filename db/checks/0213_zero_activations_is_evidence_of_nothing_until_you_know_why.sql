-- =====================================================================
-- 0213  "ZERO ACTIVATIONS" IS EVIDENCE OF NOTHING UNTIL YOU KNOW WHY
-- =====================================================================
-- Read-only. Measured 2026-09-14 ~03:45-04:00 UTC (10:45-11:00 PM CT,
-- 2026-09-13) against the live otto-q-core engine and this repo.
--
-- ---------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
-- Chase, on being handed a cut list built partly on activation counts:
--
--   "Just because something hasn't fired doesn't mean we don't need it.
--    It could just be wired incorrectly."
--
-- He is right, and this session is the proof. THREE components were
-- judged dead or failing on their counts, and all three turned out to
-- be correctly built and incorrectly connected:
--
--   NEMOTRON      14 days silent, 0 recent decisions.
--                 NOT broken. 0105 deliberately quiesces the LLM
--                 proposer on cert runs, and 1,057 of the last 1,090
--                 retained runs were cert_harness. It had no PERMITTED
--                 caller. One non-cert run woke it with nothing else
--                 changed (db/checks/0209).
--
--   THE ANTHROPIC 0 proposals in its entire life, key live since
--   ADVISOR       2026-09-13 evening.
--                 NOT broken, NOT gated, NOT unwritten. The `anthropic`
--                 python package was never installed in CI.
--                 bridge/llm_proposer.py imports its client lazily so
--                 the tests pass through a fake, and nothing noticed
--                 until something actually tried to fire. One line of
--                 workflow YAML; it then produced 24 proposals with
--                 reasoning attached.
--
--   CP-SAT        90 proposals, 0 enacted, then 6 of 329.
--                 NOT ignored, NOT outranked, NOT expired. 18 of the 23
--                 that met noop_no_candidate named a stall that had
--                 been booked BEFORE CP-SAT even proposed
--                 (db/checks/0212 §8). It solved against a stale world.
--
-- Three for three. The inference "it never fired, so we do not need it"
-- was wrong every time it was available to be wrong in this session.
--
-- ---------------------------------------------------------------------
-- THE STANDING RULE THIS FILE ASSERTS
--
--   An activation count of zero is a QUESTION, not a VERDICT.
--   Before any component is cut for silence, establish WHICH of these
--   it is, with evidence:
--
--     (a) no caller exists          -- unplugged; the wire is the fix
--     (b) a caller exists but is    -- gated; find the dial
--         forbidden to call it
--     (c) it is called and its      -- consumed and beaten; find what
--         output loses                 takes the resource first
--     (d) it is called and errors   -- read the error, do not infer
--     (e) it genuinely has no job   -- THE ONLY ONE THAT JUSTIFIES A CUT
--
--   (a) through (d) are wiring findings. Only (e) is a need finding,
--   and (e) may not be concluded by elimination -- it requires a
--   positive argument that the capability is not wanted.
--
-- cuOpt is cut on (e), and on nothing else: against cuOpt 26.08 all four
-- load-bearing constructs of the site problem are absent -- cumulative
-- resource, disjunctive machine, sequence-dependent gap, and any
-- scheduling solver family (CLAUDE.md 2.5, sourced to
-- docs/research/answers/R-12). It is not silent-because-miswired. It
-- cannot express the problem. That is a different sentence and it is
-- the only one that earns a deletion.
--
-- ---------------------------------------------------------------------
-- AND THE MEASUREMENT THAT PROMPTED IT
--
-- Five agent-shaped edge functions exist. THREE HAVE NO CALLER OF ANY
-- KIND -- no database function references them, no cron job invokes
-- them. They are case (a): unplugged, not unneeded.
--
--   ottoq-approval-copilot   NO DB CALLER   no cron
--   ottoq-feed-agents        NO DB CALLER   no cron
--   ottoq-nemotron-copilot   NO DB CALLER   no cron
--   ottoq-run-blackbox       NO DB CALLER   no cron
--   ottoq-ottocommand        NO DB CALLER   no cron   (UI-invoked; the
--                                                      chat surface)
--
-- against the two that ARE wired:
--
--   ottoq-orchestrator-agent  called by ottoq_cron_tick,
--                             ottoq_sim_decide_and_dispatch,
--                             ottoq_run_blackbox(_meta)
--   ottoq-orchestrate-tick    called by ottoq_cron_tick
--
-- Nobody removed a caller from the first four. One was never written.
-- The question for each is therefore "what should call it, on what
-- trigger, with what guard" -- which is the agentic loop's design, not
-- its obituary.
-- =====================================================================

-- §1  THE CENSUS. Which agent-shaped edge functions have a caller?
--     Re-runnable; add names to the array as surfaces are added.
WITH fns AS (
  SELECT unnest(ARRAY['ottoq-approval-copilot','ottoq-feed-agents','ottoq-nemotron-copilot',
                      'ottoq-orchestrator-agent','ottoq-ottocommand','ottoq-orchestrate-tick',
                      'ottoq-cuopt-propose','ottoq-run-blackbox']) AS edge_fn
)
SELECT f.edge_fn,
       COALESCE((SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname IN ('public','ottoq','twin')
                    AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                                       '--[^' || chr(10) || ']*','','g')
                        LIKE '%' || f.edge_fn || '%'), '(NO DB CALLER)') AS db_callers,
       COALESCE((SELECT string_agg(c.jobname, ', ') FROM cron.job c
                  WHERE c.command LIKE '%' || f.edge_fn || '%'), '(no cron)') AS cron_jobs
  FROM fns f ORDER BY 1;
-- MEASURED 2026-09-14 03:4x UTC: see the header table. Three agent
-- surfaces plus the blackbox and the chat panel have no DB caller.

-- §2  THE SHAPE OF CASE (b), so it is recognisable next time: a caller
--     exists and is forbidden. This is the Nemotron pattern.
SELECT param_key,
       (SELECT param_value FROM public.ottoq_policy_params
         WHERE scope_type='global' AND param_key = c.param_key) AS global_override,
       c.default_value AS catalog_default
  FROM public.ottoq_policy_param_catalog c
 WHERE c.param_key IN ('orchestrator_agent_enabled','cuopt_propose_enabled')
 ORDER BY 1;
-- A dial reading 0 is case (b). A dial reading 1 with no activity is
-- case (a), (c) or (d) -- and CLAUDE.md records that ottoq_policy_get
-- never consults this catalog, so the EFFECTIVE default is whatever the
-- call site hardcodes as its third argument, not what is printed here.

-- §3  THE SHAPE OF CASE (c), consumed and beaten. This is the
--     service-proposer and CP-SAT pattern: decisions NAME the source and
--     every one is a no-op.
SELECT d.l2_engine,
       count(*)                                                    AS decisions,
       count(*) FILTER (WHERE d.outcome_status = 'enacted')         AS enacted,
       count(*) FILTER (WHERE d.outcome_status = 'noop_no_candidate') AS beaten_to_the_resource
  FROM public.ottoq_decisions d
 GROUP BY 1
HAVING count(*) FILTER (WHERE d.outcome_status = 'enacted') = 0
   AND count(*) > 0
 ORDER BY decisions DESC;
-- A source appearing here is HEARD and CONSUMED. Its problem is never
-- that nobody asked -- it is that something took the resource first.
-- Do not cut anything on this list for silence; it is not silent.
