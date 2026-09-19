-- ============================================================================
-- db/checks/0247 — THE PRIMARY SOLVER WAS STARVED BY A CONTRACT SIGNED FORTY
--                 MINUTES BEFORE THE VEHICLE ARRIVED.
--
-- Measured 2026-09-19 against otto-q-core (gxdrcyphqjzjsuhxuqtg).
-- Closed by migration 0339. Evidence below is the live A/B that proved it.
-- ============================================================================
--
-- THE CLAIM UNDER TEST. 0335 (2026-09-16) made `forward_lex` -- deterministic
-- CP-SAT -- the rank-0 primary assignment proposer that CLAUDE.md 2.5 names.
--
-- THE MEASUREMENT. It has submitted nothing since, and "nothing" is literal.
--
--   SELECT declared_source, status, count(*), sum(n_submitted), max(fired_at)
--     FROM ottoq_proposer_fire_log
--    WHERE fired_at > now() - interval '6 days' GROUP BY 1,2;
--
--   forward_lex | empty     | 75 |   0 | 2026-09-17 00:29:33
--   forward_lex | submitted | 33 | 118 | 2026-09-14 09:23:34
--
-- Every fire since 2026-09-14 09:23 -- two days BEFORE it became primary -- came
-- back empty. Over the same window `source='cuopt'` produced 2,578 proposals and
-- 92 enactments. 100% of enacted assignment proposals came from the fallback and
-- none from the declared primary.
--
-- WHY, AND IT IS NOT THE SOLVER. Decomposing the 75 empty fires:
--
--   SELECT sim_run_id, count(*) fires, max(n_in_serviceable_state) serviceable,
--          max((fire->>'n_vehicles_held')::int) held,
--          sum(CASE WHEN n_in_serviceable_state
--                        > COALESCE((fire->>'n_vehicles_held')::int,0)
--                   THEN 1 ELSE 0 END) headroom
--     FROM ottoq_proposer_fire_log
--    WHERE declared_source='forward_lex' AND status='empty' GROUP BY 1;
--
--   e87e7389 | 12 | 11 | 11 | 0     91139ad8 | 15 | 22 | 22 | 0
--   5712f828 | 10 | 18 | 18 | 0     36e5cc68 |  3 | 16 | 16 | 0
--   c288555a |  7 | 13 | 13 | 0     97769e7e |  5 | 18 | 18 | 0
--   a2b246ed | 12 |  0 |  0 | 0     1bd41105 | 11 | 16 | 16 | 1
--
-- In 74 of 75 fires `serviceable` equals `held` EXACTLY. Every vehicle in a
-- plannable state already held a charge place, so proposer/forward_proposer.py's
-- `_plannable_in` dropped the entire population and returned "no plannable
-- vehicles in frame". The solver was never asked a question.
--
-- THE WRITER. ottoq.ottoq_sim_prearrival_contracts BACKSTOP 2 reserves a dcfc or
-- l2 stall for every `en_route_to_depot` vehicle carrying an unfinished charge
-- atom, with a TTL of eta+40 minutes, choosing by `ORDER BY` a CASE on urgency
-- and SoC. It is called from ottoq_sim_advance_tick_world -- the WORLD beat, not
-- the decide beat -- so it runs before the proposer fire on every tick.
--
-- By the time a vehicle reaches `arrived_at_gate`, which is the only state the
-- fire declares serviceable and the only state ottoq_decide_tick's assignment
-- cursors read (lines 197, 366), the scarcest resource on the site is allocated.
-- Three consequences, all measured:
--   * the frame marks it holds_charge_place and skips it (0265/0287);
--   * ottoq_cuopt_first_refusal_arm declines to open a seat, by the SAME dcfc/l2
--     predicate -- so 0337's "first refusal before greedy dispatch" window cannot
--     catch it, because the reservation predates the window rather than racing it;
--   * the L1 shield never probes the choice, because no decision row is made.
--
-- 0337 IS THEREFORE NOT A FIX, and this is the useful part. It armed the hold
-- earlier in the beat, which is the right move against a RACE. This was never a
-- race. A reservation taken forty minutes ahead cannot be outrun by moving one
-- statement up a few lines.
--
-- SECOND OFFENCE, SAME FUNCTION. BACKSTOP 2's own comment records the first: the
-- staging ORDER BY was ASC, which "handed every inbound car a perimeter stall
-- before it had even arrived" and "beat decide_tick's correct temp-first picker
-- every time". That was fixed for STAGING and left standing for CHARGE.
--
-- ── THE FIX, AND ITS PROOF ──────────────────────────────────────────────────
--
-- 0339 adds run-scoped `prearrival_charge_yields_to_solver`, DEFAULT 0 =
-- unchanged. At 1, BACKSTOP 2 skips the dcfc/l2 branch and falls through to the
-- staging branch it already has. ottoq_agentic_arm grants it; ottoq_agentic_arming
-- went from six required keys to seven so a run cannot read "armed" while the
-- primary proposer is starved.
--
-- It composes with 0287 instead of working around it: ottoq_reserve_stall on a
-- STAGING stall yields reserved_stall_type='staging', which 0287 already taught
-- the frame not to count as a charge place. A yielded vehicle is plannable by
-- construction -- no change to the frame, the hold, the selector or the disposer.
--
-- PROVEN BY CONTROLLED A/B ON THE LIVE FUNCTION, 2026-09-19, depot
-- 22222222-2222-2222-2222-222222222222, run 340efd05, both arms in ONE
-- transaction that was then aborted so nothing persisted:
--
--   23 en_route_to_depot vehicles, 24 offerable charge stalls
--   ARM dial=1 (yield)   ->  charge reserved  0   staging reserved 23
--   ARM dial=0 (default) ->  charge reserved 23   staging reserved  0
--
-- All 23 charge decisions survive to the gate under the fix, and all 23 vehicles
-- still get a place to wait. The staging fallback is not weakened; it is the only
-- thing the pre-arrival contract does now.
--
-- TWO FIXTURES WERE REQUIRED, AND THE FIRST ONE IS A FINDING OF ITS OWN. A first
-- probe showed charge=0 under BOTH arms and would have read as "the dial does
-- nothing". The charge branch also demands a live charger --
-- `c.station_state='Available' AND c.last_heartbeat_at >= p_clock - 35 min` -- and
-- in a world quiesced since 2026-09-17 every heartbeat is 1.7 days old, so the
-- branch was blocked for a reason unrelated to the dial. A probe against a
-- quiesced world can prove a gate closed that was never open. The second fixture
-- refreshed the heartbeats and pre-seeded a charge need for every en_route
-- vehicle, so BACKSTOP 1 was a no-op in both arms and the counts were comparable.
--
-- NOT CLAIMED. This is the mechanism proven at full population on the live
-- function; it is NOT yet an end-to-end run showing forward_lex submitting and
-- the kernel enacting. That needs a Twin Start, and ottoq_start_demo_run could
-- not be driven from this session: it calls ottoq_purge_prior_runs over 1,246
-- accumulated runs and exceeds a 60-second client window every time (filed G63 --
-- the purge is all-or-nothing over an unbounded doomed set, so it gets slower as
-- the backlog it exists to clear grows). The next run started from the OTTO-Twin
-- button is the outstanding evidence, and the query that settles it is the same
-- decomposition above: `headroom` must become non-zero and `n_submitted` must
-- leave 0.
-- ============================================================================

\echo '── 0247 §1 the starvation, as it stood before 0339 ──'
SELECT declared_source, status, count(*) AS fires,
       COALESCE(sum(n_submitted),0) AS submitted, max(fired_at) AS last_fire
  FROM public.ottoq_proposer_fire_log
 WHERE declared_source = 'forward_lex'
 GROUP BY 1,2 ORDER BY 2;

\echo '── 0247 §2 serviceable == held, per run: the starvation signature ──'
SELECT sim_run_id, count(*) AS fires,
       max(n_in_serviceable_state) AS serviceable,
       max((fire->>'n_vehicles_held')::int) AS held,
       sum(CASE WHEN n_in_serviceable_state
                     > COALESCE((fire->>'n_vehicles_held')::int,0)
                THEN 1 ELSE 0 END) AS fires_with_headroom
  FROM public.ottoq_proposer_fire_log
 WHERE declared_source='forward_lex' AND status='empty'
 GROUP BY 1 ORDER BY 2 DESC;

\echo '── 0247 §3 the gate exists, defaults to the old behaviour, and is armed ──'
SELECT (SELECT prosrc LIKE '%IF v_has_charge AND v_yield_to_solver = 0 THEN%'
          FROM pg_proc
         WHERE oid='ottoq.ottoq_sim_prearrival_contracts(uuid,timestamptz)'::regprocedure)
         AS charge_branch_gated,
       (SELECT default_value FROM public.ottoq_policy_param_catalog
         WHERE param_key='prearrival_charge_yields_to_solver') AS dial_default,
       (SELECT prosrc LIKE '%(''prearrival_charge_yields_to_solver'', 1::numeric)%'
          FROM pg_proc WHERE oid='public.ottoq_agentic_arm(uuid,text)'::regprocedure)
         AS armed_runs_yield,
       (SELECT (public.ottoq_agentic_arming(sim_run_id)->>'required')::int
          FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1)
         AS attestation_required_keys;

\echo '── 0247 §4 the outstanding evidence: does forward_lex leave zero? ──'
SELECT count(*) AS fires_since_0339,
       COALESCE(sum(n_submitted),0) AS submitted_since_0339,
       count(*) FILTER (WHERE n_in_serviceable_state
                              > COALESCE((fire->>'n_vehicles_held')::int,0))
         AS fires_with_headroom
  FROM public.ottoq_proposer_fire_log
 WHERE declared_source='forward_lex'
   AND fired_at > (SELECT classified_at FROM public.ottoq_cert_lineage
                    WHERE name LIKE '0339%');
