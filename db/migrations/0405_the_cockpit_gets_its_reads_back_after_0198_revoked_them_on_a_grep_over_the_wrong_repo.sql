-- migration-version: 20260921190250
-- migration-name:    the_cockpit_gets_its_reads_back_after_0198_revoked_them_on_a_grep_over_the_wrong_repo
--
-- 0405  **Ten read-only twin RPCs get `anon` EXECUTE back. Three mutating ones deliberately do not.**
--
-- ══ WHAT BROKE, AND IT WAS AN ACCIDENT WITH A WRITTEN CAUSE ════════════════
--
-- Migration `0198` (applied 2026-09-06 03:21:56 UTC) revoked `anon` EXECUTE from **331 SECURITY
-- DEFINER functions**. Its written premise was that no anon client called them — derived from a grep
-- over **`ottoyard-OTTO-Q`**, which is not the repo that hosts the twin cockpit. The cockpit lives in
-- **`ottoyarddepot-sim`**, and it calls fifteen RPCs directly with the anon key. Twelve of them have
-- been returning `42501 permission denied` ever since.
--
-- **The cockpit's own source records the intent that was broken.** `src/lib/ottoQClient.ts`:
-- *"Reads are open on the private link; no session is persisted."* And `src/lib/ottoTwin.ts:638`, in
-- the doc comment directly above the helper that makes these calls: *"The RPC is granted to `anon`."*
-- That sentence is false for all six RPCs beneath it, and has been for fifteen days. This migration
-- makes it true again rather than deleting it.
--
-- **Why no session rescues this.** 18 of the 22 denied functions still hold `authenticated` EXECUTE,
-- so a logged-in client would work. But `ottoQClient.ts` constructs its client with
-- `persistSession: false, autoRefreshToken: false`, and **there is no `signIn` call anywhere in the
-- repo**. The cockpit is permanently anon by construction, so the `authenticated` grant is
-- unreachable and is not an alternative to this migration.
--
-- ══ THE CENSUS THIS GRANTS FROM — MEASURED, NOT ASSUMED ════════════════════
--
-- Fifteen direct-anon call sites, from `.rpc("…")` and `rest/v1/rpc/…` across `ottoyarddepot-sim/src`:
--
--   ALREADY WORKING (2) — untouched here:
--     ottoq_activity_feed · ottoq_intelligence_stack
--
--   GRANTED HERE (10) — every one read-only:
--     ottoq_blackbox_latest_run · ottoq_hw_vehicle_status · ottoq_twin_appointments
--     ottoq_twin_boot_manifest · ottoq_twin_events_window · ottoq_twin_fleet_condition
--     ottoq_twin_labor_window · ottoq_twin_offsite_window · ottoq_twin_run_context
--     ottoq_twin_wear_window
--
--   DELIBERATELY NOT GRANTED (3) — all three MUTATE:
--     ottoq_hw_recall_vehicle        issues a recall against a live vehicle
--     ottoq_hw_set_return_threshold  writes a policy parameter
--     ottoq_sim_jump_forward         advances the simulation clock
--
-- **The three are not an oversight and must not be "finished" later.** The cockpit already has the
-- correct pattern for exactly this, and says so in its own words at `ottoTwin.ts`'s `setPlayback`:
-- *"The service-role control edge owns the write because direct anonymous execution is intentionally
-- revoked."* `start`, `stop`, `tick`, `pause`, `resume` and `setTimeScale` all route through the
-- `otto-twin-control` edge function and therefore work today. **`jumpForward` is the inconsistency**
-- — it bypasses the helper and fetches `ottoq_sim_jump_forward` straight from the browser with the
-- anon key. The fix for that is to route it through the edge like its five siblings, NOT to widen
-- this grant. Same for the two `hw_*` writers. Tracked as the repo-side half of this change.
--
-- ══ WHY GRANTING THESE TEN IS SAFE, AND HOW THAT IS ENFORCED RATHER THAN CLAIMED ══
--
-- All ten are SECURITY DEFINER, so `anon` executes them as the owner. That is precisely the
-- configuration where a careless grant becomes a hole, so read-only is **asserted at apply time and
-- again by a standing check**, not argued in a comment:
--
--   · nine of ten are declared STABLE; the tenth, `ottoq_twin_appointments`, is VOLATILE **by
--     omission** — PL/pgSQL functions are VOLATILE unless marked otherwise — and contains
--     **zero** write statements. Volatility is a declaration, not a guarantee, which is why the
--     source test below is the real gate and volatility is not used as one.
--   · a source scan for `INSERT INTO` / `UPDATE … SET` / `DELETE FROM` / `TRUNCATE` / `nextval`
--     returns **0 matches across all ten**.
--
-- An earlier, looser version of that scan flagged `ottoq_twin_events_window`. It was a false
-- positive from bare `ALTER`/`GRANT` alternations matching inside prose — the same
-- comment-matching mistake `db/checks/0310` had to retract. The tightened pattern used below
-- matches statement shapes with surrounding context, and returns nothing.
--
-- **`forces_recert` FALSE, measurably.** This migration issues GRANTs. It creates no table, alters
-- no function body, and changes no engine behaviour. Nothing in the fourteen-atom verdict reads a
-- function's ACL, and no hashed artefact can observe a privilege bit.

BEGIN;

DO $preflight$
DECLARE
  v_targets text[] := ARRAY[
    'ottoq_blackbox_latest_run','ottoq_hw_vehicle_status','ottoq_twin_appointments',
    'ottoq_twin_boot_manifest','ottoq_twin_events_window','ottoq_twin_fleet_condition',
    'ottoq_twin_labor_window','ottoq_twin_offsite_window','ottoq_twin_run_context',
    'ottoq_twin_wear_window'];
  v_forbidden text[] := ARRAY[
    'ottoq_hw_recall_vehicle','ottoq_hw_set_return_threshold','ottoq_sim_jump_forward'];
  v_n int;
  v_bad text;
BEGIN
  -- (1) Every target still exists in public. A renamed function must not be silently skipped.
  SELECT count(DISTINCT p.proname) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets);
  IF v_n <> array_length(v_targets, 1) THEN
    RAISE EXCEPTION '0405 P1: expected % target functions in public, found % -- re-census before granting',
      array_length(v_targets, 1), v_n;
  END IF;

  -- (2) THE SAFETY GATE. Not one target may contain a write statement. This is the check that
  --     makes the grant defensible; if a future edit adds a write to one of these readers, a
  --     re-run of this file refuses rather than re-granting.
  SELECT string_agg(DISTINCT p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets)
     AND p.prosrc ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\()';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0405 P2: these targets contain write statements and must NOT be granted to anon: %', v_bad;
  END IF;

  -- (3) The three mutating RPCs must still be denied to anon when we start. If one already has
  --     anon EXECUTE, something else granted it and that is a finding, not a precondition to ignore.
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_forbidden)
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0405 P3: mutating RPC(s) already granted to anon, investigate before proceeding: %', v_bad;
  END IF;

  -- (4) The premise: these are currently denied. If they are already granted, 0198 has been undone
  --     by something else and this file should be re-read rather than re-applied in ignorance.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets)
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v_n > 0 THEN
    RAISE WARNING '0405 P4: % of the target overloads already hold anon EXECUTE; grant is idempotent but the premise has moved', v_n;
  END IF;
END
$preflight$;

-- The grants themselves, by oid rather than by hand-written signature, so an overload cannot be
-- missed and a signature change cannot silently turn this into a no-op.
DO $grant$
DECLARE
  r record;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('ottoq_blackbox_latest_run','ottoq_hw_vehicle_status','ottoq_twin_appointments',
                         'ottoq_twin_boot_manifest','ottoq_twin_events_window','ottoq_twin_fleet_condition',
                         'ottoq_twin_labor_window','ottoq_twin_offsite_window','ottoq_twin_run_context',
                         'ottoq_twin_wear_window')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE '0405: granted anon EXECUTE on % overload(s)', v_count;
END
$grant$;

-- The standing check. This is a GATE, not a disclosure: it is expected to return zero rows forever.
-- A non-empty result means either a reader granted to anon has grown a write, or a mutating RPC has
-- been granted to anon -- both of which are security regressions rather than hygiene.
CREATE OR REPLACE FUNCTION public.ottoq_assert_anon_rpc_surface()
RETURNS TABLE (proname text, problem text)
LANGUAGE sql STABLE AS $$
  SELECT p.proname::text,
         'granted to anon but contains a write statement'
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND has_function_privilege('anon', p.oid, 'EXECUTE')
     AND p.prosecdef
     AND p.prosrc ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\()'
  UNION ALL
  SELECT p.proname::text,
         'mutating cockpit RPC must stay behind the otto-twin-control edge function'
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_hw_recall_vehicle','ottoq_hw_set_return_threshold','ottoq_sim_jump_forward',
                       'ottoq_start_demo_run','ottoq_sim_stop_and_reset','ottoq_set_playback','ottoq_decide_tick')
     AND has_function_privilege('anon', p.oid, 'EXECUTE')
$$;

COMMENT ON FUNCTION public.ottoq_assert_anon_rpc_surface() IS
'GATE, expected empty forever. Returns a row when a SECURITY DEFINER function reachable by anon '
'contains a write statement, or when a known-mutating cockpit RPC has been granted to anon. The '
'twin cockpit is permanently anonymous -- ottoQClient.ts sets persistSession:false and the repo has '
'no signIn call -- so anon EXECUTE is the whole authorization story for a direct RPC, and every '
'write it could reach must instead go through the otto-twin-control edge function under '
'service_role. 0405. See db/checks/0313 and 0315 for how 0198 revoked the read side by accident.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0405_the_cockpit_gets_its_reads_back_after_0198_revoked_them_on_a_grep_over_the_wrong_repo',
        FALSE,
        'Restores anon EXECUTE on TEN read-only twin RPCs that migration 0198 revoked on 2026-09-06 '
        'as part of a 331-function sweep whose written premise came from a grep over the WRONG REPO '
        '(ottoyard-OTTO-Q rather than ottoyarddepot-sim, which is where the cockpit lives). Measured '
        'fifteen direct-anon call sites: 2 already worked, 10 are granted here, 3 are deliberately '
        'left denied because they MUTATE -- ottoq_hw_recall_vehicle, ottoq_hw_set_return_threshold '
        'and ottoq_sim_jump_forward. Those three must be routed through the otto-twin-control edge '
        'function instead, which is the pattern the cockpit already uses for start/stop/tick/pause/ '
        'resume/setTimeScale and documents at setPlayback; jumpForward bypassing that helper is the '
        'inconsistency, not a missing grant. An authenticated session is NOT an alternative fix: 18 '
        'of the 22 denied functions hold authenticated EXECUTE, but ottoQClient.ts sets '
        'persistSession:false with no signIn call anywhere in the repo, so the cockpit is '
        'permanently anon by construction. Safety is enforced rather than argued: preflight (2) '
        'refuses the grant if ANY target contains INSERT/UPDATE SET/DELETE/TRUNCATE/nextval (0 of 10 '
        'do), preflight (3) refuses if a mutating RPC already holds anon, and '
        'ottoq_assert_anon_rpc_surface() is a standing gate expected empty forever. NOTE on '
        'ottoq_twin_appointments: it is VOLATILE while the other nine are STABLE, but that is '
        'declaration-by-omission (PL/pgSQL defaults to VOLATILE) and it contains zero write '
        'statements -- volatility is deliberately NOT used as the safety test, because it is a '
        'declaration and not a guarantee. An earlier looser scan flagged ottoq_twin_events_window; '
        'that was a false positive from bare ALTER/GRANT alternations matching prose, the same '
        'comment-matching error db/checks/0310 had to retract, and the tightened statement-shaped '
        'pattern returns nothing. forces_recert FALSE, measurably: this issues GRANTs only -- no '
        'table, no function body, no engine behaviour -- and nothing in the fourteen-atom verdict '
        'can observe a privilege bit.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
