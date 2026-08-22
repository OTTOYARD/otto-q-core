-- migration-version: 20260822020000
-- migration-name:    proposer_never_reuses_another_vehicles_hold
-- 0068 -- THE ISOLATION EXPERIMENT, and (if it lands as predicted) the repair of the
-- throughput regression 0067 introduced.
--
-- WHAT HAPPENED. 0067 did two things to public.ottoq_l2_optimize_assignments:
--   (1) a run-stable tiebreak on the stall pick, and
--   (2) moved the reservation-expiry test from now() to p_sim_clock.
-- (1) WON THE CERTIFICATION: re-cert #20 is 20/20, deterministic = TRUE, and the two arms
-- agree on throughput as well (523/523 commands, 41/41 sessions, 41/41 vehicles charged).
-- (2) COST ROUGHLY A THIRD OF THE DEPOT'S THROUGHPUT. The #19 -> #20 comparison is the first
-- valid cross-round comparison this series has ever been able to make (same seed, same pinned
-- sim clock, courtesy of 0065), and on arm A it reads:
--   charge sessions 62 -> 41 · vehicles charged 60 -> 41 · DCFC 18 -> 13
--   refusals 155 -> 310 · begin_charge/target_occupied 80 -> 219 · reactor backlog 0 -> 68
--
-- WHY IT IS (2) AND NOT (1). A tiebreak only orders candidates whose score was already
-- identical; it cannot change which score wins, so it cannot move throughput. Only the
-- candidate SET changed, and only (2) changed it.
--
-- THE MECHANISM, AND THE UNCOMFORTABLE PART. Before 0067 the test compared a SIM-stamped
-- column against the REAL clock, which since 0065 sits ~21 hours behind the sim clock. It was
-- therefore effectively always false, and the proposer skipped EVERY stall carrying any
-- reservation. That was a genuine bug -- and it was accidentally protective: by never reusing
-- a reserved stall it never handed away a hold that a vehicle was still travelling toward.
-- 0067 corrected the domain and removed that protection without replacing it. The proposer now
-- offers stalls whose sim reservation has lapsed -- precisely the contended ones -- its own
-- filter passes at propose time (current_vehicle_id IS NULL, reservation expired), and the
-- confirm walk runs a tick later (30 sim-min) to find the stall gone. This is the same failure
-- 0064 fixed on the command-issuing path, reintroduced one layer up on the proposal path.
--
-- THE FIX IS NOT TO RESTORE now(). That comparison is wrong on its own terms and would break
-- again the moment the two clocks diverge. Instead the protection is made EXPLICIT and the
-- clock is removed from the test entirely: the proposer declines any stall still reserved to a
-- DIFFERENT vehicle, expired or not. That is exactly what the old code did by accident, said
-- deliberately, with no domain hazard left to trip over.
--
-- WHAT THIS MIGRATION IS ALSO FOR: it is the isolation experiment I owe the record. It changes
-- ONLY (2) and leaves (1) untouched, so re-cert #21 answers both open questions at once:
--   * determinism should REMAIN true  -> confirms the tiebreak owns the certification
--   * throughput should recover toward #19's 60-62 sessions -> confirms (2) owned the regression
-- Either result is informative and both will be recorded. If throughput does NOT recover, the
-- attribution above is wrong and must be rewritten rather than defended.
--
-- KNOWN TRADE-OFF, STATED UP FRONT. A stall reserved to a vehicle that never arrives is now
-- never re-offered BY THIS PROPOSER until something else clears the reservation. That is the
-- pre-0067 behaviour under which re-cert #19 ran with a reactor backlog of ZERO, so it is not
-- expected to reintroduce the livelock -- but it is the thing to watch in #21, and the reason
-- the reactor drain-rate change stays on the shelf rather than being deleted. A middle option
-- exists if #21 shows stalls leaking: reclaim on expiry plus a one-tick grace period, so a
-- lapsed hold is not given away while its vehicle is still in transit. That is deliberately
-- NOT bundled here -- one variable per run is the whole point of this migration.
--
-- Same self-verifying in-place mechanism as 0054-0067. Pre-image pin:
--   public.ottoq_l2_optimize_assignments 3d7fa12fec5fe860854d8416dd8e4840
-- Anchor pre-verified read-only: exactly one occurrence.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_sim_clock)\n       AND c.station_state = ''Available''';
  v_new text := E'       /* 0068: NEVER REUSE ANOTHER VEHICLE''S HOLD. 0067 moved this test into the sim\n          domain, which was correct, and in doing so removed a protection the buggy version\n          had been providing by accident: while the comparison was against the real clock it\n          was effectively always false, so the proposer skipped every reserved stall and\n          therefore never handed away a hold a vehicle was still travelling toward. Correcting\n          the domain re-opened exactly the contended stalls, and the confirm walk -- a full\n          tick (30 sim-min) later -- kept finding them taken: measured #19 -> #20 on arm A,\n          begin_charge/target_occupied 80 -> 219 and charge sessions 62 -> 41.\n          The clock is now out of this test altogether: a stall held for a DIFFERENT vehicle is\n          not a candidate, expired or not. Same principle as 0064 (a hold outlives the command\n          it serves), applied to the proposal path. Trade-off accepted and recorded: a hold\n          belonging to a vehicle that never arrives is not re-offered by this proposer until\n          something else clears it -- the pre-0067 behaviour, under which re-cert #19 ran with\n          a reactor backlog of zero. */\n       AND (s.reserved_by IS NULL OR s.reserved_by = v_veh.id)\n       AND c.station_state = ''Available''';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_l2_optimize_assignments';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '3d7fa12fec5fe860854d8416dd8e4840' THEN
    RAISE EXCEPTION '0068: pre-image md5 % != pinned 3d7fa12fec5fe860854d8416dd8e4840', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0068: reservation anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_old, v_new);

  /* Post-conditions. 0067's tiebreak -- the change that actually won the certification --
     must survive this migration completely untouched; that is what makes re-cert #21 a
     one-variable experiment. And no clock may remain in the reservation test. */
  IF position('s.distance_from_entrance ASC, s.stall_code ASC, s.id ASC' in v_src) = 0 THEN
    RAISE EXCEPTION '0068: 0067''s stall-pick tiebreak did not survive -- #21 would no longer isolate one variable';
  END IF;
  /* Check the PREDICATE form, not the bare identifier: 0067's explanatory comment survives in
     the body and legitimately names reservation_expires_at in prose. Matching '<=' keeps this
     a code-level assertion. (The first draft of this migration failed here for exactly that
     reason -- the same trap 0067's now() count hit.) */
  IF position('reservation_expires_at <=' in v_src) <> 0 THEN
    RAISE EXCEPTION '0068: a reservation-expiry clock comparison is still present in the proposer';
  END IF;
  IF position('s.reserved_by IS NULL OR s.reserved_by = v_veh.id' in v_src) = 0 THEN
    RAISE EXCEPTION '0068: the hold-protection predicate is not present';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0068 patched public.ottoq_l2_optimize_assignments -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_l2_optimize_assignments');
END
$do$;
