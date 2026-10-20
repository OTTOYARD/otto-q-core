-- 0456  **A service a robot or a technician reports done in production ends in no itinerary leg, no service record and no
--        completion check.** -> G466, fixed under 0750's dial by db/migrations/0752.
--        G464's last gap, measured. Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-18 between 12:37 and 1:11 AM CT
--        (05:37 and 06:11 UTC), bounded by clock reads, inside the sweep window (catalog reads only). Every claim names its
--        query.
--
-- ══ §1 THE SEAM (reproduce: (1)) ══════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_ingest_service_complete (prosrc md5 e64f5376, 4,649 characters; SECURITY DEFINER) is the door the OEM
--   integration contract gives a robot or a technician: with no list it marks the car's bay "done" (config.service_done)
--   and the service flow's STEP 1 completes the seat on the next tick, in both feed modes; with a list it is the
--   atom-level report "from any in-depot state". On the list branch it counts the visit's outstanding atoms among the
--   reported services, calls ottoq_mark_visit_atoms_done, credits each service's wear (ottoq_wear_mark_serviced), records
--   ops.services_completed_reported and returns. It names no leg, no SDR and no probe, (1).
--
-- ══ §2 WHERE THE SAME WORK ENDS IN THE TWIN (reproduce: (2), (3)) ════════════════════════════════════════════════════
--
--   An SDR is issued only when an itinerary leg turns done (trg_0043_leg_done_sdr) or a schedule task completes. The leg of
--   work done in place is closed by ottoq_close_atom_leg (efd2dbb8), whose only caller is
--   twin.ottoq_sim_advance_visit_atoms (three sites), (2). The branch there that completes an atom, closes its leg,
--   credits its wear and probes task_completion begins
--     ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
--   the twin's timer, which runs only where the depot's feed mode is 'sim'; its readiness-check branch closes that leg in
--   both modes and probes nothing. At a depot a real feed drives, an atom started there is completed only by the seam's
--   list, (3). ottoq_mark_visit_atoms_done (be7dc4f2) rewrites the visit's atoms and nothing else.
--   In the twin, where that timer runs, the work done in place is 94-100% covered by an SDR (db/checks/0454 (1):
--   software_update 94.1%, remote_diagnostics 99.3%, item_retrieval 100%, sensor_clean and interior_tidy above 100%).
--   At a real depot it would be 0%: every SDR of work done in place comes from the timer's close.
--
-- ══ §3 WHAT IT COSTS, AND WHAT IT DOES NOT ════════════════════════════════════════════════════════════════════════════
--
--   The SDR is the kernel's record of a completed operation, signed and tariffed: the settlement row an OEM is billed
--   from (CLAUDE.md 2.6). A sensor clean or software update a robot did at a real depot would be done, credited and
--   unbillable. The planned leg would stay planned until the car deployed and then be skipped, the phantom 0750 removes
--   from the bay legs, re-timed by the flow contract meanwhile (G464 §2). And the shield's task_completion rules (sensor
--   liveness at the end of the work among them) would never see real work finish. Not rule 9: the departure test reads
--   the atoms, not legs or SDRs, so no car would leave early or stay because of it.
--   Not live (G465 §4): no production tick is scheduled, no production run is running, and no real depot is in external
--   mode.
--
-- ══ §4 THE FIX AND WHAT IT LEAVES (0752) ══════════════════════════════════════════════════════════════════════════════
--
--   Under 0750's dial bay_exit_closes_its_leg, so one setting governs both doors: before the seam marks the atoms, each
--   reported service done in place closes its leg through ottoq_close_atom_leg with the atom's start (none if it never
--   started) and the report's clock, so the trigger issues its SDR, and is probed at task_completion; the readiness check
--   closes its leg unprobed. Executed on the scratch PostgreSQL against the live seam and helpers
--   (tests/test_reported_work_closes_its_leg_sql.py, 11 tests). Testing found one defect before it shipped: LEAST ignores
--   a NULL, so a start read as LEAST(start, clock) put a never-started atom's start at the report's own clock, a record of
--   work that took no time; the start is now none.
--   Left, and named in G466: a bay service reported in the list while the car is still in its bay is marked done before
--   the exit, so the exit's credit no longer names it, 0750 records the seat as a leg of its own, and the service's
--   planned leg stays planned; and a green-light an atom requires is raised by nothing here, nor anywhere for a bay
--   repair (G467).
--   APPLIED 2026-10-18 at 6:24 AM CT (ledger 20261018112438), after 0750 and its dry run on live at 6:23, whose V3 put a
--   probe run at the twin depot inside a block rolled back by its own raise. Under 0750's dial, default 0: in production
--   it applies once a person sets bay_exit_closes_its_leg (rule 10), and in the twin on bayexit_normal's arm.

-- (1) the seam's list branch names no leg, SDR or probe
SELECT md5(p.prosrc) AS md5, length(p.prosrc) AS len,
       p.prosrc ~ 'ottoq_mark_visit_atoms_done' AS marks_atoms, p.prosrc ~ 'ottoq_wear_mark_serviced' AS credits_wear,
       p.prosrc ~ 'itinerary_legs|itin_leg|close_atom_leg' AS names_a_leg,
       p.prosrc ~ 'service_detail_records|emit_sdr' AS names_an_sdr,
       p.prosrc ~ 'probe_task_completion|shield_probe' AS probes
  FROM pg_proc p WHERE p.oid = 'public.ottoq_ingest_service_complete(uuid,text,text,text[])'::regprocedure;

-- (2) who closes the leg of work done in place, and the SDR's only issuers
SELECT n.nspname || '.' || p.proname AS fn,
       (length(p.prosrc) - length(replace(p.prosrc, 'ottoq_close_atom_leg', ''))) / length('ottoq_close_atom_leg') AS close_atom_leg_sites,
       p.prosrc ~ 'ottoq_emit_sdr' AS emits_sdr
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ '(ottoq_close_atom_leg|ottoq_emit_sdr)'
   AND p.proname NOT IN ('ottoq_close_atom_leg', 'ottoq_emit_sdr')
 ORDER BY 1;

-- (3) the twin's completion branch is its timer, gated on the feed
WITH f AS (SELECT p.prosrc AS d FROM pg_proc p
            WHERE p.oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure)
SELECT md5(d) AS md5,
       (regexp_matches(d, 'ELSIF v_feed_sim AND v_a->>''status'' = ''in_progress'' AND \(v_a->>''ends_at''\)::timestamptz <= p_clock THEN.{0,200}', 'g'))[1] AS completion_branch
  FROM f;

-- (4) the seven leg types of the work done in place issue SDRs
SELECT leg_type, operation_code, svc_code, emits_sdr FROM public.ottoq_operation_catalog
 WHERE leg_type IN ('inspect', 'interior_tidy', 'item_retrieval', 'remote_diagnostics', 'sensor_clean', 'software_update',
                    'triage_check')
 ORDER BY leg_type;
