-- migration-version: 20260909003956
-- migration-name:    a_session_may_only_be_closed_on_its_own_timeline
--
-- G36 / db/checks/0152. Fixes ONE of four sites in a single defect family, and
-- deliberately leaves the other three alone. Read §"WHY ONLY ONE" before
-- extending this.
--
-- THE FAMILY, in one sentence: a charge session is force-closed with a
-- timestamp taken from somebody else's clock, so it ends before it began.
-- Measured: benchmark-crn 55 of 88 sessions (63%), nashville-flagship 1,386 of
-- 49,174 (2.8%).
--
-- WHY IT HAPPENS AT ALL. Every sim run sets sim_clock_start = now() and then
-- advances its own clock independently -- six sim hours over a 12-tick arm. So
-- each run's sim clock is a SEPARATE TIMELINE anchored at its own wall-clock
-- start, and two runs minutes apart in real time produce sim timestamps that
-- overlap and disagree about ordering. Those run-relative instants are stored in
-- one shared column, ocpp_sessions.started_at/.ended_at, as though absolute.
-- Closing session S with run X's clock is therefore only meaningful when S
-- belongs to X.
--
-- THE RULE THIS ENCODES, and the one to apply at the remaining sites:
--
--   A SESSION MAY ONLY BE CLOSED WITH A TIMESTAMP FROM ITS OWN RUN'S TIMELINE,
--   AND NEVER EARLIER THAN ITS OWN START.
--
-- ---------------------------------------------------------------------------
-- THE FOUR SITES
-- ---------------------------------------------------------------------------
--   1  public.ottoq_benchmark_reset               <- THIS MIGRATION
--      Closes depot-wide with ended_at=now() -- the WALL clock, against a
--      started_at in sim time -- and marks the row status='completed' with no
--      stopped_reason, no soc_end and no avg_power_kw. The only function in the
--      database that closes a session with a literal now(). Not in the tick
--      path: called only by the six cert-arm procedures.
--
--   2  public.ottoq_sim_release_depot, lines 39-41    <- NOT THIS MIGRATION
--      Takes ended_at from p_sim_run_id -- the run being released -- and then
--      applies it WHERE depot_id = v_depot AND status='active', i.e. to EVERY
--      run's sessions on that depot. Correct clock, wrong scope. This is the
--      1,378 'sim_reset' rows. Nine lines below, the booking release does it
--      correctly (WHERE sim_run_id = p_sim_run_id) with a comment noting that
--      leaking bookings across runs was the 171717/24t carrier (0127) -- the
--      same defect, in the same function, fixed for bookings and missed for
--      sessions.
--      IN THE TICK PATH: public.ottoq_sim_advance_tick calls it.
--
--   3  twin.ottoq_sim_advance_charge_sessions, line 52  <- NOT THIS MIGRATION
--      ended_at = COALESCE(s.ended_at, p_sim_clock_now) applied to sessions
--      explicitly selected as belonging to ANOTHER run
--      (s.sim_run_id IS DISTINCT FROM p_sim_run_id). The comment directly above
--      it warns that "dressing that up as a physical event is how one run's arm
--      records came to describe another run's vehicles" -- the author had the
--      exact insight and then used the caller's clock anyway. Has produced 0
--      rows to date (stopped_reason='orphaned_run', 0 in the table), so it is
--      also a never-executed path.
--      IN THE TICK PATH.
--
--   4  public.ottoq_reconcile_charger_states            <- NOT THIS MIGRATION
--      stopped_reason='vehicle_departed_orphan_sweep', 8 negative rows. Its
--      expression is COALESCE(cs.ended_at, ...) and was not read closely enough
--      to convict. Unexamined, not exonerated.
--
-- ---------------------------------------------------------------------------
-- WHY ONLY ONE
-- ---------------------------------------------------------------------------
-- Site 1 is not in the certified tick path, so it cannot move a canon:
-- forces_recert FALSE, provable. Sites 2 and 3 ARE in the tick path -- an
-- advance_tick that finishes a run calls release_depot, and
-- advance_charge_sessions runs every tick -- so changing either is
-- forces_recert TRUE and must be applied with a recertification round
-- scheduled behind it. That is a deliberate, planned piece of work, not
-- something to bolt onto the end of an unrelated migration at 6pm.
--
-- Site 1 is also the one that matters right now: it is what corrupted the first
-- CRN policy pair this system has ever produced (db/checks/0152 §1) and it is
-- what blocks the A/B.
--
-- ---------------------------------------------------------------------------
-- WHY NO CHECK CONSTRAINT, having considered one
-- ---------------------------------------------------------------------------
-- The obvious guard is
--   ALTER TABLE ocpp_sessions ADD CONSTRAINT ... CHECK (ended_at IS NULL OR
--     ended_at >= started_at) NOT VALID
-- which would leave the 1,386 historical rows alone and stop any future writer.
-- It is NOT added, for two reasons, and both are worth stating because the
-- constraint looks obviously correct:
--
--   i.  Sites 2 and 3 are still live and still in the tick path. A hard CHECK
--       would turn their next occurrence into an aborted certification round
--       rather than a bad row. Adding a tripwire in front of a defect you have
--       not yet fixed is how a proof harness stops running.
--   ii. ocpp_sessions is a PROTOCOL INGEST table. Real OCPP hardware can and
--       does report a StopTransaction timestamped before its StartTransaction
--       (clock skew, retried meter values). A CHECK would reject that row
--       outright -- losing real telemetry to enforce a rule about our own
--       simulator. CLAUDE.md 2.6's boundary applies: adapters translate, they
--       do not decide what reality is allowed to say.
--
-- So the invariant is enforced where WE write, structurally, via GREATEST --
-- and monitored, not enforced, at the table. db/checks/0152 §4 carries the
-- monitoring query.
--
-- forces_recert: FALSE. ottoq_benchmark_reset is called only by
-- ottoq_cert_arm, ottoq_cert_arm_start, ottoq_cert_arm_wave,
-- ottoq_cert_arm_finish, ottoq_fr1_cert_arm and ottoq_safety_cert_arm -- all
-- benchmark-lane procedures, none in the flagship tick path -- and no verdict
-- atom reads ocpp_sessions (ottoq_world_fingerprint, ottoq_boot_state_
-- fingerprint, ottoq_calibration_fingerprint and ottoq_determinism_pair all
-- return false for a 'ocpp_sessions' match). The floor is checked anyway.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

-- ---------------------------------------------------------------------------
-- P-  NEVER APPLY WHILE A CERTIFICATION PAIR IS IN FLIGHT.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n; END IF;
END $P$;

-- ---------------------------------------------------------------------------
-- P1  The body is byte-for-byte what the anchor was measured on.
-- ---------------------------------------------------------------------------
DO $P1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure));
  IF h <> 'f2014058b6e1c07530a7db0203efbfc1' THEN
    RAISE EXCEPTION 'P1 REFUSED: benchmark_reset md5 is %, pinned f2014058b6e1c07530a7db0203efbfc1', h;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- P2  Site 1 really is outside the flagship tick path. If a tick-path caller
--     ever appears, this migration's forces_recert FALSE is no longer true and
--     the apply must stop rather than quietly mis-classify.
-- ---------------------------------------------------------------------------
DO $P2$
DECLARE bad text;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prosrc ~* 'ottoq_benchmark_reset'
     AND p.proname <> 'ottoq_benchmark_reset'
     AND p.proname NOT IN ('ottoq_cert_arm','ottoq_cert_arm_start','ottoq_cert_arm_wave',
                           'ottoq_cert_arm_finish','ottoq_fr1_cert_arm','ottoq_safety_cert_arm');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'P2 REFUSED: unexpected caller(s) of ottoq_benchmark_reset: % -- '
                    'forces_recert FALSE was justified by the caller set', bad;
  END IF;
END $P2$;

-- ---------------------------------------------------------------------------
-- THE CHANGE. Catalog-derived, one anchored substitution, uniqueness asserted
-- before use.
--
-- The replacement does three things the original did not:
--   * takes the clock from the SESSION'S OWN run, not the wall and not the
--     resetting caller -- the correlated subselect on o.sim_run_id;
--   * floors it at the session's own started_at with GREATEST, so ended_at can
--     never precede started_at even if that run's row is gone or its clock is
--     behind. This is the invariant made structural rather than hoped for;
--   * tells the truth: 'cancelled' (a value the enum already carries and
--     ottoq_sim_release_depot already uses) with stopped_reason='benchmark_reset',
--     instead of 'completed' with no reason. A force-killed session that claims
--     to have completed is what made peak_concurrent_kw read 0.0 on a run that
--     delivered 128.79 kWh.
--
-- The function's OTHER ended_at=now(), on ottoq_sim_runs, is deliberately
-- untouched: a run's ended_at is the real-world instant it stopped, and the
-- wall clock is the correct clock for it. Only ocpp_sessions.ended_at lives on
-- a sim timeline. (Found by the dry run, which failed a first version of A1
-- that asserted the token was absent from the whole function.)
--
-- soc_end and avg_power_kw are deliberately left NULL. They were never
-- measured, and inventing them would be worse than the lie this removes;
-- 0231's soc_measured_sessions field exists precisely so a NULL is counted
-- rather than hidden.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE d text; a text; rep text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);

  a := 'UPDATE ocpp_sessions SET status=''completed'', ended_at=now() WHERE depot_id=p_depot AND status=''active'';';

  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: anchor occurs % times, expected 1', n; END IF;

  rep := E'UPDATE ocpp_sessions o\n'
      || E'     SET status=''cancelled'',\n'
      || E'         -- 0233 / G36: the session''s OWN run''s clock, floored at its own start.\n'
      || E'         ended_at = GREATEST(o.started_at,\n'
      || E'                      COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r\n'
      || E'                                 WHERE r.sim_run_id = o.sim_run_id), o.started_at)),\n'
      || E'         stopped_reason=''benchmark_reset'',\n'
      || E'         updated_at=now()\n'
      || E'   WHERE o.depot_id=p_depot AND o.status=''active'';';

  EXECUTE replace(d, a, rep);
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  The wall clock is gone from this function's session close.
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);
  -- NOTE ON THIS ASSERTION. It originally read
  --     IF d ~ 'ended_at\s*=\s*now\(\)' THEN RAISE ...
  -- i.e. "no ended_at=now() anywhere in this function", and the dry run
  -- returned FALSE -- it would have aborted the apply. The function contains a
  -- SECOND ended_at=now(), on a different table:
  --     UPDATE ottoq_sim_runs SET status='aborted', ended_at=now(), ...
  -- and that one is CORRECT and is deliberately left alone. A run's ended_at is
  -- the real-world instant the run stopped; the wall clock is the right clock
  -- for it. Only ocpp_sessions.ended_at lives on a sim timeline. Asserting on
  -- the specific statement instead of on the token is the difference between a
  -- test of the change and a test of the file.
  IF position('UPDATE ocpp_sessions SET status=''completed''' in d) > 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the old wall-clock session close is still present';
  END IF;
  IF position('GREATEST(o.started_at' in d) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the GREATEST floor is not present';
  END IF;
  IF position('r.sim_run_id = o.sim_run_id' in d) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the per-session run scope is not present';
  END IF;
  IF position('stopped_reason=''benchmark_reset''' in d) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: stopped_reason is not set';
  END IF;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  It no longer claims a force-killed session completed.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);
  IF position('status=''completed''' in d) > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: the function still marks a reaped session ''completed''';
  END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  The floor expression does what it claims, on values shaped like the ones
--     that caused the defect: a sim-time start six hours AHEAD of a wall-clock
--     candidate end. NOT a call to the function -- ottoq_benchmark_reset RESETS
--     A DEPOT and must never be invoked from an assertion.
-- ---------------------------------------------------------------------------
DO $A3$
DECLARE v_start timestamptz := '2026-09-09 04:37:07.598566+00';  -- sim, as observed
        v_wall  timestamptz := '2026-09-08 22:48:10.290243+00';  -- wall, as observed
        v_out   timestamptz;
BEGIN
  v_out := GREATEST(v_start, COALESCE(NULL::timestamptz, v_start));
  IF v_out <> v_start THEN
    RAISE EXCEPTION 'A3 FAILED: missing-run fallback returned %, expected the start %', v_out, v_start;
  END IF;
  v_out := GREATEST(v_start, v_wall);
  IF v_out <> v_start THEN
    RAISE EXCEPTION 'A3 FAILED: floor returned %, expected % -- the exact -05:59:28 case', v_out, v_start;
  END IF;
END $A3$;

-- ---------------------------------------------------------------------------
-- A4  Signature and volatility unchanged; the six cert-arm callers still
--     resolve it.
-- ---------------------------------------------------------------------------
DO $A4$
DECLARE t text;
BEGIN
  SELECT pg_get_function_result('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure) INTO t;
  IF t IS NULL THEN RAISE EXCEPTION 'A4 FAILED: function no longer resolves'; END IF;
END $A4$;

-- ---------------------------------------------------------------------------
-- LINEAGE.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_session_may_only_be_closed_on_its_own_timeline',
  now(),
  false,
  'G36 / db/checks/0152. ottoq_benchmark_reset closed every active session on a '
  'depot with ended_at=now() -- the wall clock against a started_at in sim time -- '
  'and marked them status=''completed'' with no stopped_reason and no meters. 55 of '
  'benchmark-crn''s 88 sessions ended up to six hours before they started, which is '
  'why the first CRN policy pair scored peak_concurrent_kw 0.0 on a run that '
  'delivered 128.79 kWh. Now takes the clock from each session''s OWN run, floors it '
  'at that session''s own started_at with GREATEST so the invariant is structural, '
  'and records ''cancelled'' + stopped_reason=''benchmark_reset''. forces_recert '
  'FALSE: called only by the six cert-arm procedures, none in the flagship tick '
  'path (asserted in P2), and no verdict atom reads ocpp_sessions. THREE SITES IN '
  'THE SAME FAMILY REMAIN OPEN and are named in the header: '
  'ottoq_sim_release_depot (right clock, depot-wide scope, 1,378 rows), '
  'twin.ottoq_sim_advance_charge_sessions (caller''s clock on a foreign run''s '
  'session, 0 rows so far), and ottoq_reconcile_charger_states (8 rows, '
  'unexamined). Both of the first two are in the tick path and are forces_recert '
  'TRUE.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 19:39:56 CT (2026-09-09 00:39:56 UTC). Three preconditions,
-- four assertions, first attempt.
--
--   benchmark_reset md5  f2014058b6e1c07530a7db0203efbfc1
--                     -> ae412097c7b1b7cca8d110b9b91733a8
--   P2: caller set is exactly the six cert-arm procedures
--   A1: old wall-clock close gone; floor, run scope and stopped_reason present
--   A2: no 'completed' anywhere in the function
--   A3: the floor returns the sim start for both the missing-run case and the
--       exact -05:59:28 case
--   ottoq_decide_tick md5 ae98f71b879a0a11bdf366d21ff5b4eb UNCHANGED
--   THE FLOOR DID NOT MOVE: 2026-09-07 21:36:53.363037 before and after.
--
-- ***  NOT YET VERIFIED IN BEHAVIOUR, AND THIS MATTERS  ***
--
-- The verification attempt did NOT verify anything, and it would have been easy
-- to report that it did. The plan was: run arm A, snapshot its sessions, run arm
-- B, and prove arm A's records survived arm B's reset.
--
--   arm A  bc760291-eef0-481c-989b-6f2dc8cce9b1  otto_q, 12 ticks
--          BEFORE arm B: 56 sessions, 26 still open, 0 negative, 1280.67 kWh
--          AFTER  arm B: 56 sessions,               0 negative, 1280.67 kWh
--                        0 rows with stopped_reason='benchmark_reset'
--
-- That looks like a pass and is not one. Arm B CRASHED, and a CALL is one
-- transaction, so arm B's ottoq_benchmark_reset rolled back with it and never
-- touched arm A at all. Zero rows reaped is the tell: had the fix run, arm A's
-- 26 open sessions would have been closed WITH stopped_reason='benchmark_reset'
-- and 0 negative. Instead nothing ran. The evidence is consistent with the fix
-- working and equally consistent with the fix doing nothing.
--
-- 0233 IS THEREFORE APPLIED AND UNPROVEN. What would prove it, exactly: a
-- SUCCESSFUL arm B, after which arm A shows
--     stopped_reason='benchmark_reset' on its previously-open sessions
--     AND ended_at >= started_at on every one of them.
-- Both conditions, or it is not proven.
--
-- WHY ARM B CRASHED -- a new finding, not this migration's business, written up
-- as db/checks/0153 / G37:
--
--   ERROR: duplicate key value violates unique constraint
--          "idx_stalls_one_vehicle_per_stall"
--   CONTEXT: sync_stall_occupancy() -> ottoq_fifo_tick line 24
--
-- Two triggers on public.vehicles disagree about what "tethered" means.
-- ottoq_arm_interlock_guard compares robotic_tether_until against a clock, so it
-- PERMITS moving a vehicle whose tether has expired. sync_stall_occupancy tests
-- only "robotic_tether_until IS NOT NULL", so for that same vehicle it REFUSES
-- to vacate the old stall. The vehicle then occupies two stalls and the unique
-- index on stalls.current_vehicle_id fires. Every successful move of an
-- expired-but-non-NULL tether leaks a stall. Confirmed by reading both trigger
-- bodies (expiry-aware: true / false).

-- ---------------------------------------------------------------------------
-- *** PROVEN 2026-09-08 20:0x PM CT ***, replacing the "APPLIED AND UNPROVEN"
-- note above. That note stands as written; this is the evidence it asked for.
--
-- WHY THE FIRST TWO ATTEMPTS PROVED NOTHING, and it is structural rather than
-- bad luck: a cert arm is ONE transaction, so when arm B failed at any tick its
-- ottoq_benchmark_reset rolled back with it. The fix could never be observed
-- through a failing arm B. Both attempts showed "0 rows reaped", which reads as
-- a pass and means the code never ran.
--
-- The route that works is to call the reset DIRECTLY, in its own transaction,
-- against a finished arm -- which is the function's own purpose:
--
--   SELECT public.ottoq_benchmark_reset('22222222-...'::uuid, 30, 80);
--
-- Judged on arm A, run 5e7a6a91-b936-45f1-af7d-1734e5804928 (otto_q, 12 ticks,
-- 51 sessions, 26 of them still open at the time of the reset):
--
--                      BEFORE          AFTER
--   still_active         26              0
--   stopped_reason=      --             26      <- 0233's first condition
--     'benchmark_reset'
--   ended_at < started_at 0              0      <- 0233's second condition
--   status='cancelled'   --             26      <- no longer claims 'completed'
--   shortest duration    --        00:00:00
--
-- Both conditions the footer demanded, met. And shortest_duration = 00:00:00 is
-- the most informative number here: it is the GREATEST floor ENGAGING. At least
-- one session's own run's sim_clock_current had not advanced past that session's
-- own started_at, so the floor pinned it to exactly zero. Without GREATEST those
-- rows would have been negative -- which is to say the run-scoped clock alone
-- was not sufficient, and the floor was not belt-and-braces.
-- ---------------------------------------------------------------------------
