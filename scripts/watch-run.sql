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
-- THE ONE-BUTTON RUN THIS READS (it was two buttons until 2026-09-14):
--     SELECT twin.ottoq_sim_start_run('bench_busy_day', NULL, NULL, <seed>, 'otto_twin');
--   then pg_cron job 12 (ottoq_demo_metronome, every minute) advances it.
--
--   ARMING IS NO LONGER A SEPARATE STEP. Migration 0323 injected the
--   ottoq_agentic_arm call into BOTH start doors -- public.ottoq_sim_run_scenario
--   (what otto-twin-control's POST /scenarios/start calls) and
--   twin.ottoq_sim_start_run -- so a run started from the UI arms itself. Before
--   0323 nothing did: across 1,147 sim runs, no database function and no edge
--   function had ever called ottoq_agentic_arm. Hop 1 is the receipt, and it is
--   the hop that distinguishes "armed" from "we believe it arms".
--
--   The call is skipped when p_run_by = 'cert_harness', because arming sets
--   proposer_frame_facts=1 and that changes the decision frame every canon was
--   measured against. ottoq_agentic_arm refuses such a run by RAISING anyway.
--
-- USAGE  psql ... -v run="'<sim_run_id>'" -f scripts/watch-run.sql
--
-- ---------------------------------------------------------------------------
-- READ THE note COLUMN, NOT JUST THE COUNT. Five hops are known to read higher
-- than they deserve, and this file is useless if it flatters:
--
--   hop 1  A RECEIPT IS NOT A FIRING. 'armed' means the three dials were set
--          (proposer_frame_facts, proposer_hold_enabled,
--          cuopt_first_refusal_max_defers -- all three have live decide-path
--          readers, db/checks/0244). It does not mean a proposer ran. Read it
--          with hop 8.
--
--   hop 5  N/N IS NOT "THE FORECAST IS RIGHT", it is "every active dispatch
--          carries a number". Before 0321 the measured baseline was 0 of 68 --
--          every active dispatch had a NULL ETA -- so 0/N here means the
--          per-tick refresh never ran and 0321 did not take. Whether the number
--          is any good is hop 6's question, not this one. AND 0/0 IS NOT 0/N:
--          a completed run has no active dispatch left, so this hop reads 0/0
--          on every finished run and can only be read while a run is live.
--
--   hop 6  THE DISTINCT COUNT IS THE POINT. 0320 exists because four functions
--          wrote return_eta_minutes and exactly one wrote eta_source, so the
--          label described a write that had been superseded. A label reading
--          'computed:*' with 1 distinct value is a constant wearing a
--          computation's name; a label reading 'policy_constant:*' with many
--          distinct values is the reverse. Either is the same defect class.
--          A '(NO LABEL)' line is legacy: 73,589 such rows predate 0322, and
--          of the 746 dispatch rows written since it applied, 746 carry an ETA
--          and 0 are missing either the label or the stamp.
--
--   hop 8  ARMED IS NOT FIRED. Arming opens the door; it does not make a
--          proposer walk through it. A run can be correctly armed and still
--          show 0 proposals because no proposer is pointed at it -- cuOpt
--          reaches an external endpoint, and the CP-SAT bridge is a dispatched
--          job. 0 here means NOBODY PROPOSED, not "the agent layer is broken"
--          and not "the agent layer works". Note also that
--          ottoq_external_proposals is a WORKING SET, not a ledger: both
--          proposers DELETE their own rows for the run before writing
--          (db/checks/0242, 97.5% of rows ever inserted have been deleted), so
--          a low count late in a run is expected. Proposer INFLUENCE is
--          counted from ottoq_decisions.l2_engine at hop 10, never from here.
--
--   hop 10 THE SOURCE BREAKDOWN IS THE POINT, not the total. A decision whose
--          enacted_action carries no 'source' cannot be attributed to a
--          proposer OR to the kernel, so it is evidence for neither. G67
--          measured ~87% source-less fleet-wide. Read that line before quoting
--          the count above it.
--
--   hop 14 A TWIN RUN CANNOT PASS THIS HOP, and that is the finding, not a bug
--          in the watcher. The twin executes a command in-process and never
--          takes delivery, so delivered_at stays NULL through a perfect run.
--          The hop is here so the outbound half of the hub is visible in the
--          same view as the rest of the chain rather than only in a check file:
--          OTTO-Q is closed IN and THROUGH, and open OUT (G70). Read 0/N as
--          "no consumer is wired yet", never as "the run failed".
--
--   hop 11 0 refusals is ambiguous. It means either the shield refused nothing
--          or the shield was not asked. Compare the evaluation count against
--          the decision count at hop 10; db/checks/0146 convicted baseline
--          policies that evaluated NO rules at all while looking productive.
-- ---------------------------------------------------------------------------
WITH R AS (SELECT :run::uuid AS id)
SELECT * FROM (
  SELECT 0 AS hop, 'RUN' AS stage,
    (SELECT tick_count::text FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id) AS n,
    (SELECT scenario_code||' seed='||random_seed||' '||status||' clock='||
            to_char(sim_clock_current,'MM-DD HH24:MI')||' by='||COALESCE(run_by,'(null)')
       FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id) AS note

  UNION ALL SELECT 1,'ARM: agentic layer armed at the door (0323)',
    (SELECT CASE WHEN payload->'agentic_arm' IS NULL THEN '(NO RECEIPT)'
                 WHEN payload->'agentic_arm'->>'ok' = 'true' THEN 'armed'
                 ELSE 'REFUSED' END
       FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id),
    (SELECT CASE
       WHEN payload->'agentic_arm' IS NULL AND COALESCE(run_by,'')='cert_harness'
         THEN 'certification arm -- arming is skipped BY DESIGN (it would move the frame every canon was measured against)'
       WHEN payload->'agentic_arm' IS NULL
         THEN 'NO RECEIPT: this run predates 0323, or was started by a path 0323 did not patch'
       WHEN payload->'agentic_arm'->>'ok' = 'true'
         THEN 'dials set: proposer_frame_facts=1, proposer_hold_enabled=1, cuopt_first_refusal_max_defers=1'
       ELSE 'ARMING REFUSED: '||COALESCE(payload->'agentic_arm'->>'error','(no error recorded)') END
       FROM public.ottoq_sim_runs, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 2,'world: telemetry packets',
    (SELECT count(*)::text FROM public.ottoq_telemetry_packets, R WHERE sim_run_id=R.id),
    (SELECT count(*) FILTER (WHERE current_lat IS NOT NULL)||' positioned, '||
            count(DISTINCT vehicle_id)||' vehicles'
       FROM public.ottoq_telemetry_packets, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 3,'world: energy commands',
    (SELECT count(*)::text FROM public.ottoq_energy_commands, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT command_type,', '),'(none)')
       FROM public.ottoq_energy_commands, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 4,'need: visit needs',
    (SELECT count(*)::text FROM public.ottoq_visit_needs, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(status||'='||n,' '),'(none)') FROM
       (SELECT vn.status, count(*) n FROM public.ottoq_visit_needs vn, R
         WHERE vn.sim_run_id=R.id GROUP BY 1 ORDER BY 2 DESC) t)

  UNION ALL SELECT 5,'FORECAST: return ETA coverage (0320/0321)',
    (SELECT count(*) FILTER (WHERE return_eta_minutes IS NOT NULL)||'/'||count(*)
       FROM public.ottoq_vehicle_dispatches, R WHERE sim_run_id=R.id AND status='active'),
    (SELECT CASE WHEN count(*)=0 THEN 'NOT A FAILURE: no dispatch is active -- this hop only speaks while a run is live'
            ELSE count(*) FILTER (WHERE eta_refreshed_at IS NOT NULL)||' stamped, newest stamp '||
                 COALESCE(to_char(max(eta_refreshed_at),'MM-DD HH24:MI'),'(none)')||
                 ' -- pre-0321 baseline was 0 of 68 active forecast' END
       FROM public.ottoq_vehicle_dispatches, R WHERE sim_run_id=R.id AND status='active')

  UNION ALL SELECT 6,'FORECAST: eta_source provenance (0321)',
    (SELECT count(DISTINCT COALESCE(eta_source,'(no label)'))::text
       FROM public.ottoq_vehicle_dispatches, R
      WHERE sim_run_id=R.id AND return_eta_minutes IS NOT NULL),
    (SELECT COALESCE(string_agg(src||'='||n||'('||d||' distinct min)',' '),'(no forecast written)') FROM
       (SELECT COALESCE(vd.eta_source,'(NO LABEL -- legacy row; 0322 refuses this on any write since 2026-09-14)') src,
               count(*) n, count(DISTINCT vd.return_eta_minutes) d
          FROM public.ottoq_vehicle_dispatches vd, R
         WHERE vd.sim_run_id=R.id AND vd.return_eta_minutes IS NOT NULL
         GROUP BY 1 ORDER BY 2 DESC LIMIT 6) t)

  UNION ALL SELECT 7,'recall: decisions',
    (SELECT count(*)::text FROM public.ottoq_recall_decisions, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT implementation,', '),'(none)')
       FROM public.ottoq_recall_decisions, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 8,'AGENT: proposals (working set, not a ledger)',
    (SELECT count(*)::text FROM public.ottoq_external_proposals, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(source||'/'||status||'='||n,' '),'(NO AGENT PROPOSED)') FROM
       (SELECT ep.source, ep.status, count(*) n FROM public.ottoq_external_proposals ep, R
         WHERE ep.sim_run_id=R.id GROUP BY 1,2) t)

  UNION ALL SELECT 9,'AGENT: deferrals (right of first refusal)',
    (SELECT count(*)::text FROM public.ottoq_cuopt_deferrals, R WHERE sim_run_id=R.id),
    'ticks the kernel waited for a proposer before deciding itself'

  UNION ALL SELECT 10,'KERNEL: decisions disposed',
    (SELECT count(*)::text FROM public.ottoq_decisions, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(src||'='||n,' '),'(none)') FROM
       (SELECT COALESCE(d.enacted_action->>'source','(no source)') src, count(*) n
          FROM public.ottoq_decisions d, R WHERE d.sim_run_id=R.id
         GROUP BY 1 ORDER BY 2 DESC LIMIT 5) t)

  UNION ALL SELECT 11,'SHIELD: rule evaluations',
    (SELECT count(*)::text FROM public.ottoq_rule_evaluations, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(count(*) FILTER (WHERE NOT passed)::text,'0')||' refusals'
       FROM public.ottoq_rule_evaluations, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 12,'ASSET: stall bookings',
    (SELECT count(*)::text FROM public.ottoq_stall_bookings, R WHERE sim_run_id=R.id),
    'the EXCLUDE constraint makes an overlap physically impossible'

  UNION ALL SELECT 13,'ASSET: commands emitted',
    (SELECT count(*)::text FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id),
    (SELECT COALESCE(string_agg(DISTINCT command_type,', '),'(none)')
       FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 14,'OUTBOUND: commands taken delivery of',
    (SELECT count(*) FILTER (WHERE delivered_at IS NOT NULL)||'/'||count(*)
       FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id),
    (SELECT CASE
       WHEN count(*) = 0 THEN 'no commands issued'
       WHEN count(*) FILTER (WHERE delivered_at IS NOT NULL) = 0
         THEN 'NOBODY CLAIMED THEM: 0 of '||count(*)||'. Fleet-wide that is 0 of 822,887 (db/checks/0243).'
       ELSE count(*) FILTER (WHERE confirmed_at IS NOT NULL)||' also confirmed, '||
            count(DISTINCT delivered_to)||' distinct consumers' END
       FROM public.ottoq_vehicle_commands, R WHERE sim_run_id=R.id)

  UNION ALL SELECT 15,'OUTCOME: service detail records',
    (SELECT count(*)::text FROM public.ottoq_service_detail_records, R WHERE sim_run_id=R.id),
    'CLAUDE.md 2.6: every completed operation must terminate in an SDR'
) x ORDER BY hop;
