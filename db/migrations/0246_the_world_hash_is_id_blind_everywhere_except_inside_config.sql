-- migration-version: 20260909094627
-- migration-name: 0246_the_world_hash_is_id_blind_everywhere_except_inside_config
-- ===========================================================================
-- 0246  THE WORLD HASH IS ID-BLIND EVERYWHERE EXCEPT INSIDE config
-- ===========================================================================
-- probe:          db/checks/0161
-- forces_recert:  TRUE
-- REPAIRS:        0244, which round 33 proved wrong three hours after it landed
--
-- WHAT WENT WRONG
--
-- 0244 gave ottoq_boot_state_fingerprint a 'world' key holding
-- ottoq.ottoq_world_fingerprint(p_depot), so endst -- previously blind to the
-- assets and the service points -- would finally cover them. The gap was real.
-- The instrument chosen to close it was not sound for the job:
--
--   ottoq.ottoq_world_fingerprint hashes vehicles.config nearly whole,
--     COALESCE((v.config - 'condition_drawn_run')::text,'{}'),
--   stripping exactly one key. That is correct at BOOT, where the reset leaves
--   config carrying no run-scoped identifiers. It is wrong at END-OF-RUN, where
--   config has gained service_manifest, service_manifest_meta, charge_plan,
--   deploy_gate, svc_step and sometimes bay_eviction -- several of which hold
--   freshly generated uuids.
--
-- MEASURED on round 33's 08:10 pair, from the two arms' own event streams:
--
--   distinct config.service_manifest_meta.visit_id, arm A     116
--   distinct config.service_manifest_meta.visit_id, arm B     116
--   shared between the arms                                     0
--
-- One per vehicle, disjoint by construction. endst could not agree, on any
-- column, ever. Round 33 failed six of six on endst alone.
--
-- THE DEEPER ERROR WAS DOCTRINAL, AND IT IS THE PART WORTH REMEMBERING.
-- CLAUDE.md 2.9a requires an atom to be added MEASURED first and ENFORCED only
-- after a flagship round shows the arms agree. 0244 added a new COMPONENT to
-- endst, which was already enforced, so it entered the equality list with no
-- measured round in between. The reasoning that made this feel safe -- "I am
-- reusing a fingerprint that already exists and is already probe-justified" --
-- is exactly the reasoning the doctrine exists to interrupt. A start-relevant
-- hash reused at end-of-run is a different measurement wearing the same name.
--
-- THE FIX
--
--   COALESCE((v.config - 'condition_drawn_run')::text,'{}')
--   ->
--   COALESCE(public.ottoq_scrub_ids((v.config - 'condition_drawn_run')::text),'{}')
--
-- ottoq_scrub_ids is IMMUTABLE, replaces every uuid with '<uuid>' and every bare
-- 8-hex token with '<id8>', and is already how this codebase makes a jsonb blob
-- id-blind before hashing it: ottoq_boot_state_fingerprint's bookings CTE
-- hashes jsonb_build_object('why', public.ottoq_scrub_ids(t.why)). This makes
-- the config term consistent with the rest of the instrument rather than an
-- exception to it.
--
-- WHAT IT COSTS, STATED RATHER THAN GLOSSED. fp and endst can no longer tell
-- WHICH uuid a config value holds -- a different stall id inside bay_eviction
-- now hashes the same. That discrimination is not lost from the verdict, only
-- from this term: h_bkg hashes the calendar including stall_id, and 0139 already
-- established that the end-state fingerprint is supposed to be id-blind.
--
-- No explicit BEGIN/COMMIT: apply_migration supplies the transaction.
-- ===========================================================================

DO $mig$
DECLARE
  v_fp_sig constant text := 'ottoq.ottoq_world_fingerprint(uuid)';
  d text; a text; nd text; n int; v_before text; v_after text;
BEGIN
  IF md5(pg_get_functiondef(v_fp_sig::regprocedure)) <> '0da0c0d1bba07c95386b58b4f1e75dc1' THEN
    RAISE EXCEPTION '0246 PRECONDITION: world_fingerprint md5 is %, expected 0245''s 0da0c0d1bba07c95386b58b4f1e75dc1',
      md5(pg_get_functiondef(v_fp_sig::regprocedure));
  END IF;

  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_before
    USING '11111111-1111-1111-1111-111111111111'::uuid;

  d := pg_get_functiondef(v_fp_sig::regprocedure);
  a := 'COALESCE((v.config - ''condition_drawn_run'')::text,''{}'')';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0246 SITE: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a,
        'COALESCE(public.ottoq_scrub_ids((v.config - ''condition_drawn_run'')::text),''{}'') '
     || '/* 0246: config carries per-run uuids once a run has started -- 116 disjoint '
     || 'service_manifest_meta.visit_id values per arm, measured in db/checks/0161 -- so '
     || 'hashing it raw made endst unable to agree at end-of-run once 0244 put this '
     || 'fingerprint inside it. Harmless at boot, where config holds no run ids. */');
  EXECUTE nd;

  d := pg_get_functiondef(v_fp_sig::regprocedure);
  IF md5(d) = '0da0c0d1bba07c95386b58b4f1e75dc1' THEN
    RAISE EXCEPTION '0246 A1: world_fingerprint definition did not change';
  END IF;
  IF d NOT LIKE '%ottoq_scrub_ids((v.config%' THEN
    RAISE EXCEPTION '0246 A1: the config term is not scrubbed';
  END IF;

  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_after
    USING '11111111-1111-1111-1111-111111111111'::uuid;
  IF v_after !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION '0246 A2: world_fingerprint returned %, not an md5', v_after;
  END IF;

  -- A3: the scrubber must actually be doing something to a config-shaped blob,
  -- or the fix is inert and endst would still fail.
  IF public.ottoq_scrub_ids('{"visit_id": "3610518b-e1ea-40ac-9e0b-a51dc71b7512"}')
     NOT LIKE '%<uuid>%' THEN
    RAISE EXCEPTION '0246 A3: ottoq_scrub_ids did not replace a uuid';
  END IF;

  -- A4: 0244's world key is still present on the boot/end fingerprint.
  IF NOT ((SELECT public.ottoq_boot_state_fingerprint(
             '11111111-1111-1111-1111-111111111111'::uuid,
             '00000000-0000-0000-0000-000000000000'::uuid)) ? 'world') THEN
    RAISE EXCEPTION '0246 A4: the world key vanished from the boot/end fingerprint';
  END IF;

  RAISE NOTICE '0246 OK: fp % -> % (clean world)', v_before, v_after;
END
$mig$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note)
VALUES ('0246_the_world_hash_is_id_blind_everywhere_except_inside_config',
        TRUE,
        'Repairs 0244 / probe db/checks/0161. ottoq_world_fingerprint hashed vehicles.config '
        'stripping only condition_drawn_run, which is sound at boot and unsound at end-of-run: '
        'config gains service_manifest_meta.visit_id and friends during a run, 116 per arm and '
        'disjoint between arms. Once 0244 put this fingerprint inside endst -- an ENFORCED atom '
        '-- round 33 failed six of six on endst alone. The config term is now passed through '
        'ottoq_scrub_ids. The underlying error was doctrinal: a new component was added to an '
        'already-enforced atom without a MEASURED round first (CLAUDE.md 2.9a).');

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-09 09:46:27 UTC (4:46 AM CT) as version 20260909094627
-- ---------------------------------------------------------------------------
-- Dry-run first inside a deliberately aborted transaction (anchor unique, the
-- rewritten body compiled, fp moved), then applied on a quiet database: 0 busy
-- client backends, round 33 finished at 09:31.
--
--   ottoq.ottoq_world_fingerprint  md5  0da0c0d1bba07c95386b58b4f1e75dc1
--                                   ->  125a8cb1baf8f51dadb70619739c8956
--   fp, flagship, clean world           e30f4ca0bfb8723d4296bb696465ebef
--   recert floor                        2026-09-09 09:46:27.088143
--
-- VERIFIED AGAINST THE EXPERIMENT THAT CONVICTED IT. The 0153 grid fixture
-- reproduces the whole defect in seconds and isolates it to one sub-key, so the
-- fix was checked there rather than by waiting eighty minutes for a round:
--
--   ottoq_determinism_pair(239001, 6, 'grid_smoke', 'aacd0bb0-...', ...)
--
--                     BEFORE 0246                        AFTER 0246
--   outcome           failed                             PASSED
--   endst.world  A    3d6d645a8a397b478faec1c8f3018d90   4926be34f0e995a3f1180021baab0349
--   endst.world  B    80b55a0c4099b70ae5e178a49bbdebdf   4926be34f0e995a3f1180021baab0349
--   endst agrees      no                                 yes
--   fp agrees         yes                                yes
--
-- Same fixture, same seed, same function, one migration apart. The prediction in
-- db/checks/0161 -- "the grid pair passes, with endst.world equal across arms" --
-- is confirmed, and the alternative it named ("if it still fails, config is not
-- the only end-of-run term that differs") did not occur.
--
-- Round 34 re-earns the flagship canons above the new floor. This is the third
-- recert in one night; two of the three were bought by 0244's mistake, and that
-- is the honest cost of having enforced a component before measuring it.
