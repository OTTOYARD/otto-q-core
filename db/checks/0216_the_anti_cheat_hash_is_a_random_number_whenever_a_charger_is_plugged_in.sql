-- 0216  THE CONTENT-HASHED ANTI-CHEAT SUBSTRATE IS A RANDOM NUMBER WHENEVER
--       ANYTHING IS PLUGGED IN
--
-- Measured 2026-09-14. Read-only. Every query below re-runs.
--
-- ---------------------------------------------------------------------------
-- WHAT WAS CLAIMED, AND BY WHOM
--
-- CLAUDE.md rule 6 names `ottoq_decision_snapshots` "the content-hashed
-- anti-cheat substrate", and 2.9a leans on the reproducibility apparatus as a
-- product property -- "same inputs, byte-identical outputs, verified
-- continuously" -- explicitly because R-12 established that the leading GPU
-- solver in this space cannot promise byte-identical output at all.
--
-- An adversarial review of the agentic-loop designs REPORTED that this
-- particular hash is not deterministic. A report is not a measurement, and the
-- standing rule is not to take an agent's result at face value. So it was
-- re-measured here, from scratch, against the live engine.
--
-- THE REPORT WAS RIGHT, and the mechanism is provable rather than inferred.
--
-- ---------------------------------------------------------------------------
-- SECTION 1 -- A PASSING CERTIFICATION PAIR DISAGREES WITH ITSELF ON 44 OF 48
--              TICKS
--
-- Pair: seed 171717, busy_day, 48 ticks, run_by cert_harness, started
-- 2026-09-13 16:36:00 UTC. BOTH arms carry validation_status = 'passed'.
--
--   arm A  665b6437-cb1d-4819-bb03-878e97d6aed7
--   arm B  45132bcf-aa31-41da-92f2-c38932e4de36
--
--   ticks compared   48
--   identical         4
--   DIFFERING        44
WITH a AS (SELECT tick_seq, content_hash FROM public.ottoq_decision_snapshots
            WHERE sim_run_id='665b6437-cb1d-4819-bb03-878e97d6aed7'),
     b AS (SELECT tick_seq, content_hash FROM public.ottoq_decision_snapshots
            WHERE sim_run_id='45132bcf-aa31-41da-92f2-c38932e4de36')
SELECT count(*) AS ticks_compared,
       count(*) FILTER (WHERE a.content_hash = b.content_hash)  AS identical,
       count(*) FILTER (WHERE a.content_hash <> b.content_hash) AS differing
  FROM a JOIN b USING (tick_seq);

-- ---------------------------------------------------------------------------
-- SECTION 2 -- THE CAUSE, PROVEN BY A CLEAN SEPARATION
--
-- The four agreeing ticks are EXACTLY the ticks with zero active charging
-- sessions, and the forty-four differing ticks are EXACTLY the ticks with at
-- least one. 4 of 4 and 44 of 44, no exceptions either way.
--
--   hashes_agree | zero_sessions | ticks
--   -------------+---------------+------
--   false        | false         |   44
--   true         | true          |    4
--
-- That is not a correlation to argue about. The hash is deterministic precisely
-- when the array carrying a random value is empty.
WITH a AS (SELECT tick_seq, content_hash, (frame_counts->>'sessions')::int AS sess
             FROM public.ottoq_decision_snapshots
            WHERE sim_run_id='665b6437-cb1d-4819-bb03-878e97d6aed7'),
     b AS (SELECT tick_seq, content_hash FROM public.ottoq_decision_snapshots
            WHERE sim_run_id='45132bcf-aa31-41da-92f2-c38932e4de36')
SELECT (a.content_hash = b.content_hash) AS hashes_agree,
       (a.sess = 0)                      AS zero_sessions,
       count(*)                          AS ticks
  FROM a JOIN b USING (tick_seq)
 GROUP BY 1,2 ORDER BY 1,2;

-- ---------------------------------------------------------------------------
-- SECTION 3 -- THE MECHANISM, READ OFF THE TWO BODIES
--
-- public.ottoq_capture_decision_snapshot hashes the WHOLE frame:
--
--   v_frame := ottoq_build_decision_frame(p_depot_id, p_sim_run_id);
--   -- deterministic content hash over the canonical (key-sorted) frame text
--   v_hash  := encode(digest(jsonb_pretty(v_frame), 'sha256'), 'hex');
--
-- and public.ottoq_build_decision_frame's `sessions` block is:
--
--   'sessions', (SELECT jsonb_agg(jsonb_build_object(
--       'id', cs.id, 'stall_id', ..., 'vehicle_id', ..., 'status', ...,
--       'started_at', cs.started_at, 'power_kw', ...) ORDER BY cs.id)
--      FROM ocpp_sessions cs WHERE cs.depot_id = ... AND cs.status = 'active')
--
-- so `cs.id` is in the hashed payload AND is the array's sort key. And:
--
--   ocpp_sessions.id  column_default = uuid_generate_v4()
--
-- A fresh random uuid per session row, in the digest and in the ordering. Two
-- arms that place identical vehicles on identical stalls at identical sim
-- clocks mint different session ids, so they hash differently -- and the
-- comment one line above the digest call says "deterministic content hash".
SELECT column_name, column_default
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='ocpp_sessions' AND column_name='id';

-- ---------------------------------------------------------------------------
-- WHY A PASSING PAIR STILL PASSED, AND WHAT IS AND IS NOT DAMAGED
--
-- NOT DAMAGED: the fourteen-atom determinism verdict. content_hash is not one
-- of the fourteen. The pair compares fingerprint, commands, decisions, events,
-- bookings, energy, proposals, deferrals, calibration, rules, recalls, SDRs,
-- tick count and end state -- and on this pair all fourteen agreed. The engine
-- really did make byte-identical decisions; that claim stands and is not
-- weakened by this file.
--
-- DAMAGED: the separate claim that `ottoq_decision_snapshots` is a
-- content-hashed anti-cheat substrate. It is not one today. Its hash changes
-- between two runs that did the same thing, so it can neither detect tampering
-- (a real edit is indistinguishable from the noise) nor witness agreement.
-- This is the G25/G28 pattern again -- an artifact treated as evidence while
-- sitting outside the comparison that would have caught it -- and it is the
-- sharper version, because here the artifact is named in the brief.
--
-- THE HONEST SENTENCE, until this is fixed: "fourteen atoms are byte-identical
-- across paired runs, continuously verified" is TRUE and is the claim to make.
-- "Every decision frame is content-hashed so tampering is detectable" is NOT
-- true and must not be said.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS GATES, which is why it was worth stopping to measure
--
-- 1. Arming proposer_frame_facts = 1 anywhere that matters. The facts gate adds
--    reservation_expires_at, charger_heartbeat_at and the selector clock to
--    this same frame, i.e. to this same hash. Adding fields to a hash that is
--    already random makes the substrate worse while looking like progress.
--    db/checks/0215's probe run was deliberately non-cert and deliberately
--    stopped for this reason; ottoq_agentic_arm (0278) refuses a cert_harness
--    run by construction, which is the guard that made it safe.
-- 2. Any frame-staleness design built on content_hash. A freshness comparison
--    over a random number reports "stale" every tick and means nothing. The
--    staleness instrument needs a hash over the DECISION-RELEVANT projection
--    (which points are contested), not over the whole frame.
--
-- ---------------------------------------------------------------------------
-- THE FIX, NOT APPLIED HERE, AND WHY IT IS NOT ONE LINE
--
-- The shape is: hash a projection that excludes minted identifiers and sort by
-- something stable -- (stall_id, vehicle_id, started_at) rather than cs.id --
-- exactly as 0139 did for the end-state fingerprint when it made that atom
-- id-blind, and exactly as 0137 did when the world fingerprint was found to be
-- hashing a write timestamp. This is the same defect class a third time.
--
-- It is NOT applied in this file because changing content_hash changes every
-- future snapshot, and the blind-spot promotion doctrine (0139 / 0206 / 0217 /
-- 0225) says an atom is added MEASURED first and ENFORCED only after a flagship
-- round shows the arms agree. The order is: land the id-blind hash, run a
-- round, show a pair now agrees on 48 of 48, and only then let anything depend
-- on it. That wants its own file and its own cert window.
