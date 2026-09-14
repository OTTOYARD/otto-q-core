-- ---------------------------------------------------------------------------
-- watch-run.sql -- ONE query. Run id in, the orchestration chain out, hop by hop.
--
-- WHY THIS EXISTS. Asked "does OTTO-Q orchestrate end to end", the honest reply
-- is not a paragraph -- it is to start a run and show the chain moving. The
-- determinism certification cannot answer that question even in principle:
-- ottoq_determinism_pair writes cuopt_propose_enabled=0 into every arm it
-- starts (tagged '0152_cert_quiesce'), so the proposer is OFF inside every
-- certification by design. This is the instrument for the other question.
--
-- THE TWO-BUTTON RUN THIS READS:
--     SELECT twin.ottoq_sim_start_run('bench_busy_day', NULL, NULL, <seed>, 'otto_twin');
--     SELECT public.ottoq_agentic_arm('<run>', '<who>');   -- verdict must be "armed"
--   then pg_cron job 12 (ottoq_demo_metronome, every minute) advances it.
--   ottoq_agentic_arm REFUSES a run_by='cert_harness' run, so this cannot be
--   pointed at a certification arm by accident.
--
-- USAGE  psql ... -v run="'<sim_run_id>'" -f scripts/watch-run.sql
--
-- ---------------------------------------------------------------------------
-- READ THE note COLUMN, NOT JUST THE COUNT. Three hops are known to read higher
-- than they deserve, and this file is useless if it flatters:
--
--   hop 5  ARMED IS NOT FIRED. ottoq_agentic_arm opens the door; it does not
--          make a proposer walk through it. A run can be correctly armed and
--          still show 0 proposals because no proposer is pointed at it -- cuOpt
--          reaches an external endpoint, and the CP-SAT bridge is a dispatched
--          job. 0 here means NOBODY PROPOSED, not "the agent layer is broken"
--          and not "the agent layer works".
--
--   hop 7  THE SOURCE BREAKDOWN IS THE POINT, not the total. A decision whose
--          enacted_action carries no 'source' cannot be attributed to a
--          proposer OR to the kernel, so it is evidence for neither. G67
--          measured ~87% source-less fleet-wide. Read that line before quoting
--          the count above it.
--
--   hop 8  0 refusals is ambiguous. It means either the shield refused nothing
--          or the shield was not asked. Compare the evaluation count against
--          the decision count at hop 7; db/checks/0146 convicted baseline
--          policies that evaluated NO rules at all while looking productive.
-- ---------------------------------------------------------------------------
WITH R AS (SELECT :run::uuid AS id)
SELECT * FROM (
  SELECT 0 AS hop, 'RUN' AS stage,
    (SELECT tick_count::text FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id) AS n,
    (SELECT scenario_code||' seed='||random_seed||' '||status||' clock='||
            to_char(sim_clock_current,'MM-DD HH24:MI')
       FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id) AS note

  UNION ALL SELECT 1,'world: telemetry packets',
    (SELECT count(*)::text FROM public.ottoq_telemetry_packets, R WHERE sim_run_id=R.id),
    (SELECT count(*) FILTER (WHERE current_lat IS NOT NULL)||' positioned, '||
            count(DISTINCT vehicle_id)||' vehicles'
       FROM public.ottoq_telemetry_packets, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 2,'world: energy commands',
    (SELECT count(*)::text FROM public.ottoq_energy_commands, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT command_type,', '),'(none)')
       FROM public.ottoq_energy_commands, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 3,'need: visit needs',
    (SELECT count(*)::text FROM public.ottoq_visit_needs, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(status||'='||n,' '),'(none)') FROM
       (SELECT vn.status, count(*) n FROM public.ottoq_visit_needs vn, R
         WHERE vn.sim_run_id=R.id GROUP BY 1 ORDER BY 2 DESC) t)

  UNION ALL SELECT 4,'recall: decisions',
    (SELECT count(*)::text FROM public.ottoq_recall_decisions, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT implementation,', '),'(none)')
       FROM public.ottoq_recall_decisions, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 5,'AGENT: proposals',
    (SELECT count(*)::text FROM public.ottoq_external_proposals, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(source||'/'||status||'='||n,' '),'(NO AGENT PROPOSED)') FROM
       (SELECT ep.source, ep.status, count(*) n FROM public.ottoq_external_proposals ep, R
         WHERE ep.sim_run_id=R.id GROUP BY 1,2) t)

  UNION ALL SELECT 6,'AGENT: deferrals (right of first refusal)',
    (SELECT count(*)::text FROM public.ottoq_cuopt_deferrals, R WHERE sim_run_id=R.id),
    'ticks the kernel waited for a proposer before deciding itself'

  UNION ALL SELECT 7,'KERNEL: decisions disposed',
    (SELECT count(*)::text FROM public.ottoq_decisions, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(src||'='||n,' '),'(none)') FROM
       (SELECT COALESCE(d.enacted_action->>'source','(no source)') src, count(*) n
          FROM public.ottoq_decisions d, R WHERE d.sim_run_id=R.id
         GROUP BY 1 ORDER BY 2 DESC LIMIT 5) t)

  UNION ALL SELECT 8,'SHIELD: rule evaluations',
    (SELECT count(*)::text FROM public.ottoq_rule_evaluations, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(count(*) FILTER (WHERE NOT passed)::text,'0')||' refusals'
       FROM public.ottoq_rule_evaluations, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 9,'ASSET: stall bookings',
    (SELECT count(*)::text FROM public.ottoq_stall_bookings, R WHERE sim_run_id=R.id),
    'the EXCLUDE constraint makes an overlap physically impossible'

  UNION ALL SELECT 10,'ASSET: commands emitted',
    (SELECT count(*)::text FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT command_type,', '),'(none)')
       FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 11,'OUTCOME: service detail records',
    (SELECT count(*)::text FROM public.ottoq_service_detail_records, R WHERE sim_run_id=R.id),
    'CLAUDE.md 2.6: every completed operation must terminate in an SDR'
) x ORDER BY hop;
