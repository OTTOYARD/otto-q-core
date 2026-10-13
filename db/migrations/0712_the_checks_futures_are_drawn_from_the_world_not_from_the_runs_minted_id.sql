-- migration-version: 20261013181932
-- migration-name:    the_checks_futures_are_drawn_from_the_world_not_from_the_runs_minted_id
--
-- 0712  **The check's futures are drawn from the world, not from the run's minted id.** The kernel's check on an agent's
--        charge order (0620) samples its futures from a seed of `sim_run_id : tick : chain_id`. Both ids are random UUIDs
--        minted at run start and at the agent's claim, so the same world, at the same tick, with the same order, drew
--        different futures on every run and every pass. The verdict on an order therefore depended on two coin flips
--        nobody could repeat. The seed is now `world : random_seed : tick`: what defines the world and the instant, and
--        nothing minted. (The study's DC-7; G427.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Measured in the study (scratchpad lane on determinism, adversarially re-run): replaying stored snapshots under
--   today's functions, order 382 with its recorded seed is taken, 10 futures won of 12; with only the run id in the seed
--   changed it is refused, 4 won, 5 tied, 3 lost. Order 385: taken 11 of 12, then refused 8 of 12. Both taken orders
--   tested flip, and 41 of 416 post-0620 orders are seed-sensitive, every take among them.
--
--   Two consequences, both against what 2.9a sells:
--     a. No replay and no paired arm can reproduce a verdict. Two arms of one seed meet the same world at the same tick
--        and draw different futures, because their run ids differ. The research wing's agent-on/off replay -- the
--        harness every further agent has to pass (docs/AGENT_ARCHITECTURE.md) -- cannot exist until this holds.
--     b. Candidates are not compared on common random numbers. Inside one check the kernel's order and the agent's
--        share futures (0620's rollout pairs them). But a second agent pass at the same tick has a different chain id,
--        so its order meets different futures than the first one's, and so would a deterministic candidate generator.
--
--   What this does NOT fix, said so nobody reads it as fixed: the check still cannot tell a better order from a worse
--   one (G389; G427: on run 176b2912 the 5 missed wins scored p_win 0.367, the 6 right refusals 0.431). With 12
--   futures, a verdict near the 0.8 bar still turns on the draw. A fixed draw makes that repeatable; it does not make it
--   right. The comparison itself is the next work.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_charge_order_record (md5 66576edf, after 0627; the only function that builds the seed -- the
--   grader, the attribution and the regrade read `seed` from ottoq_charge_order_snapshots), by SUBSTITUTION, two anchors
--   each asserted to occur exactly once:
--     a. the run row also reads random_seed;
--     b. v_seed := 'world:' || COALESCE(random_seed::text, sim_run_id::text) || ':' || tick.
--        A run with no random_seed (a production session) falls back to its id, as before: production has no replica.
--
--   The snapshot keeps storing the seed it used, so every order recorded before this file replays exactly as it was
--   decided, and the prefix `world:` says which scheme drew it. code_md5 is unchanged: it hashes the simulator, not
--   the seed's recipe.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   The check runs only when an agent sends a charge order. The agent is quiesced in certification arms and switched
--   off in the A/B, dial and sweep harnesses (the study: 0 of 169 harness runs in 14 days ran it). No atom hashes it.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_agent_charge_order_record definition snapshotted under label '0712_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0712 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_md5 text := md5(pg_get_functiondef('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure));
        v_other text;
BEGIN
  IF v_md5 IS DISTINCT FROM '66576edf15e404aab2c948e52e36e7cb' THEN
    RAISE EXCEPTION '0712 P1: ottoq_agent_charge_order_record is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  --: no other function builds a seed for the check; the readers read the stored one
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_other
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind = 'f'
     AND p.proname <> 'ottoq_agent_charge_order_record'
     AND pg_get_functiondef(p.oid) ~ 'ottoq_charge_line_(rollout|simulate|schedule)\('
     AND pg_get_functiondef(p.oid) ~ 'sim_run_id::text \|\| '':''';
  IF v_other IS NOT NULL THEN
    RAISE EXCEPTION '0712 P1: another function builds a run-id seed for the check: %', v_other;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0712_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_charge_order_record';

DO $rec$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure);
  v_old_run  constant text := E'SELECT r.sim_run_id, r.depot_id, r.tick_count, r.sim_clock_current, r.status INTO v_run';
  v_new_run  constant text := E'SELECT r.sim_run_id, r.depot_id, r.tick_count, r.sim_clock_current, r.status, r.random_seed INTO v_run';
  v_old_seed constant text :=
    E'      v_seed := p_sim_run_id::text || '':'' || COALESCE(v_run.tick_count, 0) || '':'' || COALESCE(p_chain_id, '''');\n';
  v_new_seed constant text :=
       E'      --: 0712: the futures are drawn from the world and the instant, never from an id minted at random (a run''s\n'
    || E'      --: id, a pass''s chain id): the same world at the same tick draws the same futures for every candidate\n'
    || E'      v_seed := ''world:'' || COALESCE(v_run.random_seed::text, p_sim_run_id::text) || '':'' || COALESCE(v_run.tick_count, 0);\n';
  v_n int; v_m int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_old_run, ''))) / length(v_old_run);
  v_m := (length(v_def) - length(replace(v_def, v_old_seed, ''))) / length(v_old_seed);
  IF v_n <> 1 OR v_m <> 1 THEN
    RAISE EXCEPTION '0712: anchors found % and % times in ottoq_agent_charge_order_record, expected exactly 1 each', v_n, v_m;
  END IF;
  EXECUTE replace(replace(v_def, v_old_run, v_new_run), v_old_seed, v_new_seed);
END $rec$;

DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure);
        v_old text := (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0712_pre' AND s.object_name = 'ottoq_agent_charge_order_record' LIMIT 1);
BEGIN
  --: V1 the seed names neither minted id, and reads the run's seed
  IF strpos(v_def, 'v_seed := ''world:'' || COALESCE(v_run.random_seed::text, p_sim_run_id::text)') = 0
     OR strpos(v_def, 'COALESCE(p_chain_id, '''')') > 0 THEN
    RAISE EXCEPTION '0712 V1 FAILED: the seed is not as written';
  END IF;
  --: V2 nothing else moved: undoing the two substitutions gives the old definition back
  IF replace(replace(v_def, ', r.random_seed INTO v_run', ' INTO v_run'),
             E'      --: 0712: the futures are drawn from the world and the instant, never from an id minted at random (a run''s\n'
             || E'      --: id, a pass''s chain id): the same world at the same tick draws the same futures for every candidate\n'
             || E'      v_seed := ''world:'' || COALESCE(v_run.random_seed::text, p_sim_run_id::text) || '':'' || COALESCE(v_run.tick_count, 0);\n',
             E'      v_seed := p_sim_run_id::text || '':'' || COALESCE(v_run.tick_count, 0) || '':'' || COALESCE(p_chain_id, '''');\n')
     <> v_old THEN
    RAISE EXCEPTION '0712 V2 FAILED: the function changed by more than the seed';
  END IF;
  RAISE NOTICE '0712 V1-V2 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0712_the_checks_futures_are_drawn_from_the_world_not_from_the_runs_minted_id', false, false,
  'The study''s DC-7 (G427): the charge-order check seeded its futures with the run''s and the pass''s minted ids, so '
  'both taken orders tested flipped to refused on a change of run id alone. The seed is now world:random_seed:tick. The '
  'check runs only on an agent order; the agent is quiesced in certification arms and off in the harnesses: FALSE/FALSE.',
  now());

COMMIT;
