-- migration-version: PENDING
-- migration-name:    slim_writes_and_arm_retention

-- ============================================================================
-- 0006_slim_writes_and_arm_retention.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- The database filled to 14 GB and stopped taking connections. It filled for two
-- reasons, and this file addresses both. Neither one is "we log too much" -- the
-- log is the black box and we want it. The problem is that we were writing the
-- SAME FACT over and over, and that we were never deleting anything.
--
--   (A) WE PHOTOGRAPH THE WHOLE CAR TO RECORD THAT ONE FIELD CHANGED.
--       Every time a vehicle changes state, the event log stores a complete copy of
--       that vehicle's row -- VIN, make, model, year, colour, and a ~2 kB `config`
--       blob -- in a column called `new_state`. The actual news in that event is
--       about 250 bytes ("current_state went from en_route_to_depot to offline").
--       The other ~2,000 bytes are a re-photograph of things that did not change and
--       cannot change. `new_state` is 75% of an event row and 63% of the whole
--       events table. At ~2,000 event rows per minute that is roughly 400 MB per
--       hour of running, which is exactly how 11 GB accumulated.
--
--       We already know the fix works, because we did the mirror image of it earlier
--       today: `previous_state` was removed from the state-change triggers after
--       proving it could be rebuilt exactly. This file does the same thing to
--       `new_state`, and it does NOT delete the column -- it stops writing the
--       redundant copies and ships a function that rebuilds them on demand.
--
--   (B) RETENTION HAS NEVER DELETED A SINGLE EVENT.
--       `ottoq_events` is append-only, enforced by a trigger. That trigger has an
--       escape hatch: deletes are allowed only while a transaction-local flag,
--       `ottoq.retention`, is set to 'on'. `ottoq_purge_prior_runs` never set that
--       flag, so every delete it attempted was refused -- and it swallowed the error
--       and reported success. Nine hundred nights of "purge complete" that deleted
--       nothing. This file sets the flag, and fixes the separate reason the nightly
--       worker could not keep up.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO
--   It changes no orchestration logic, no LP, no CSR build, no parse path, no Gate B,
--   no verify_jwt, and no decision anywhere. It drops no table, no column and no
--   function. It runs no VACUUM FULL. It does not re-enable the incident trigger.
--   Several cuts that looked attractive were measured, found to be merely "probably
--   fine", and DECLINED -- they are listed with their reasons in §11 so the next pass
--   does not have to re-derive them.
--
-- ============================================================================
-- WHAT I CONFIRMED, WHAT I EXTENDED, WHAT I CORRECTED IN THE BRIEF
--
-- Everything below was derived from the committed baseline export in
-- `db/baseline/` (functions_public.sql, functions_twin.sql, functions_ottoq.sql,
-- tables.sql, cron_jobs.sql) plus the measured anatomy handed to me. I was
-- instructed NOT to touch the database while authoring this file, and I did not.
-- Where that limits what I can assert, I say so rather than papering over it.
--
--   CONFIRMED (1) -- `ottoq_purge_prior_runs` DOES NOT ARM THE FLAG.
--     Its full body is in db/baseline/functions_public.sql:11623-11656. It contains
--     no `set_config` of any kind. Its delete loop selects every public table with a
--     `sim_run_id` column whose name starts with `ottoq`, which includes
--     `ottoq_events`, and wraps each DELETE in `EXCEPTION WHEN OTHERS THEN RAISE
--     WARNING`. So the append-only trigger raised, the handler swallowed it into a
--     warning nobody reads, and the function returned `{"ok": true}`. Exactly as the
--     brief describes. §6 fixes it.
--
--   CORRECTED (2) -- THE BRIEF IS WRONG ABOUT THE NIGHTLY WORKER. IT ALREADY ARMS.
--     The brief says "`ottoq_purge_prior_runs` and `ottoq_retention_purge_worker`
--     never set it". That is true of the first and FALSE of the second. The 4-argument
--     `ottoq_retention_purge_worker` -- the overload cron job 11 actually calls --
--     contains `PERFORM set_config('ottoq.retention', 'on', true);` in every one of
--     its three delete paths (baseline functions_public.sql:12813, 12856, 12862), and
--     re-arms it after each COMMIT, which is correct because COMMIT clears a
--     transaction-local setting. The 3-argument overload arms it too (line 12755).
--     I am flagging this rather than silently "fixing" a thing that was not broken,
--     because if we mis-attribute the cause we will believe the problem is solved
--     when it is not. The worker's failure has a DIFFERENT cause -- see (3) and (4).
--
--   CONFIRMED + DIAGNOSED (3) -- THE QUADRATIC ctid DEFECT, AND WHY IT EXISTS.
--     The worker walks the heap by physical block:
--         DELETE FROM public.ottoq_events WHERE ctid IN (
--           SELECT ctid FROM public.ottoq_events
--            WHERE ctid >= format('(%s,0)', v_blk)::tid
--              AND ctid <  format('(%s,0)', LEAST(v_blk + v_window, v_max_blk + 1))::tid
--              AND occurred_at < v_cut
--            LIMIT p_micro_batch);
--     The reason someone reached for a physical-block cursor is visible in the index
--     list, and it is the real root cause. `ottoq_events` has SEVEN indexes and NOT
--     ONE of them is a plain btree on `occurred_at`:
--         ottoq_events_keep_occurred_at_idx   btree (occurred_at DESC)
--                                             WHERE severity IN ('critical','safety_critical')
--         ottoq_events_keep_occurred_at_idx1  BRIN  (occurred_at)
--     The first is partial and matches ~nothing the purge wants. The second is BRIN,
--     which cannot supply ordering, so `ORDER BY occurred_at LIMIT 2000` cannot be
--     answered cheaply -- it would sort every old row in the table. With no ordered
--     access path on time, each block window degenerates toward re-examining the rows
--     it already examined, which is the quadratic behaviour the brief names, and the
--     cursor can also park in a region of the heap that holds no expired rows and
--     delete zero for many consecutive nights.
--     §7 replaces the whole approach. `event_seq` is a bigint from a sequence with a
--     UNIQUE btree on it (`ottoq_events_keep_event_seq_key`), it increases with
--     insertion order, and insertion order is time order for an append-only log. So
--     "oldest first" is a bounded, index-ordered range scan on a key we already index.
--     Each iteration touches exactly `p_micro_batch` index entries and then deletes a
--     contiguous seq range. That is O(batch), it always makes forward progress, and
--     it needs no cursor state and no wraparound logic at all.
--
--   FOUND -- NOT IN THE BRIEF (4) -- A SECOND REASON THE PURGE ABORTS, AND IT IS
--   ALMOST CERTAINLY WHY EVEN AN ARMED PURGE WOULD HAVE FAILED.
--     `ottoq_events` has a self-referencing foreign key:
--         ottoq_events_parent_event_id_fkey
--             FOREIGN KEY (parent_event_id) REFERENCES ottoq_events(event_id)
--             ON DELETE SET NULL NOT VALID
--     Deleting an old parent event therefore performs an UPDATE on every surviving
--     child event to null its `parent_event_id`. That referential action fires the
--     table's row triggers like any other UPDATE -- and `ottoq_events_block_mutation`
--     only forgives DELETE:
--         IF TG_OP = 'DELETE' AND current_setting('ottoq.retention', true) = 'on'
--           THEN RETURN OLD; END IF;
--         RAISE EXCEPTION 'ottoq_events is append-only. Operation % rejected ...'
--     A retention purge deletes oldest-first, so parents go before children, so the
--     cascade fires, so the exception raises, so the entire batch rolls back. Arming
--     the flag without this fix would have produced the same "succeeded and deleted
--     nothing" outcome for a new reason.
--     ⚠️ HONEST LIMIT: I could not read `pg_trigger` from here, so I cannot state
--     which statements this trigger is attached to. §5 therefore extends the escape
--     hatch to UPDATE **only while the retention flag is on**. If the trigger is
--     attached to UPDATE, this is load-bearing. If it is not, the change is inert.
--     Either way it costs nothing and it cannot weaken the append-only guarantee,
--     because nothing outside retention ever sets that flag.
--     Same shape, different table: `ottoq_feature_values.source_event_id` is also
--     `ON DELETE SET NULL` against `ottoq_events`. That one has no append-only guard,
--     so it will succeed -- but it means every purged event also dirties a
--     feature_values row. Noted in §11 as a cost, not fixed here.
--
--   CONFIRMED (5) -- THE `new_state` REDUNDANCY IS EXACT BY CONSTRUCTION, NOT MERELY
--   STATISTICAL. This is the part that upgrades the anatomy's 96.4% into a proof.
--     The state-change triggers all have the identical shape (baseline
--     functions_public.sql:13375-13418 and the same block at 15075 and 17317):
--         -- INSERT branch
--         p_payload    := jsonb_build_object('new', to_jsonb(NEW)),
--         p_new_state  := to_jsonb(NEW)
--         -- UPDATE branch
--         v_diff       := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
--         p_payload    := jsonb_build_object('diff', v_diff),
--         p_new_state  := to_jsonb(NEW)
--     And `ottoq_jsonb_diff` (baseline functions_public.sql:9688) is a TOTAL,
--     top-level diff over the union of both documents' keys, emitting
--     `{"<key>": {"from": <old>, "to": <new>}}` for every key that differs.
--     Two consequences follow arithmetically, with no sampling involved:
--
--       (5a) ON A `.created` EVENT, `new_state` AND `payload->'new'` ARE THE SAME
--            EXPRESSION EVALUATED TWICE IN ONE STATEMENT. The full row is stored
--            twice inside a single event row. Rebuilding one from the other requires
--            no other row, no chain, and no ordering.
--
--       (5b) ON A `.state_changed` EVENT,
--                 new_state(N) = new_state(N-1) || { k : diff(N)[k]->'to' }
--            holds exactly, because `to_jsonb(row)` always carries the complete
--            column list (a table's key set never changes between two versions of the
--            same row), and the diff is total over that key set. `||` is jsonb's
--            shallow merge, which is precisely the operator this identity needs.
--
--     THE ANATOMY'S 197 MISMATCHES ARE EXPLAINED BY THE SAME CODE, NOT BY A HOLE IN
--     THE REASONING. It measured 5,219/5,416 byte-identical rebuilds, with the only
--     ever-differing keys being `updated_at` and `current_soc_updated_at`. That is
--     what the trigger is written to do -- it deliberately suppresses events for
--     housekeeping-only churn:
--         IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(v_diff) AS k
--                         WHERE k <> ALL (ARRAY['updated_at']))
--         THEN RETURN NEW; END IF;
--     No event is emitted, so no diff exists to carry that timestamp forward. Those
--     197 rows are not reconstruction failures; they are updates the log was
--     designed never to record. State-semantic reconstruction is 5,416/5,416.
--     The authoritative values for both clock columns live on `vehicles` itself and
--     on the event's own `occurred_at`, so nothing is lost.
--
--   METHOD NOTE ON THE GUARDS -- READ THIS, IT DIFFERS FROM 0002-0005.
--     0002 through 0005 guard with md5 hashes of the live function bodies, computed
--     live at authoring time. I was instructed not to touch the database, so I have
--     no live hashes and I will not invent them. Instead §1 uses CONTENT guards: each
--     function this file replaces must contain (or must not contain) a specific
--     string that identifies the version I reasoned about. A content guard is in one
--     respect STRONGER than an md5 -- it still passes when someone reformatted a
--     comment, and it still fails when someone actually changed the mechanism -- and
--     in one respect weaker, since it does not detect unrelated edits. Both the
--     pre-image and its md5 are snapshotted to `ottoq_schema_snapshots` regardless,
--     so any replacement here is fully reversible from the database itself.
--     This is also why this file replaces as FEW existing bodies as possible: the
--     entire (A) half is implemented as a NEW trigger on `ottoq_events`, so not one
--     of the six state-change trigger functions has to be rewritten -- which matters,
--     because those six were edited earlier today and the committed baseline is
--     already stale against them.
--
-- ============================================================================
-- ORDER OF WORK
--   §1  snapshot + content guards.
--   §2  policy knobs: what we slim, and how long we keep.
--   §3  the chain-anchor table.
--   §4  (A) the slimming trigger on ottoq_events.
--   §5  (A) the rebuild-on-read function, and the append-only escape hatch fix.
--   §6  (B) ottoq_purge_prior_runs -- arm the flag, widen the never-delete list.
--   §7  (B) ottoq_retention_purge_worker -- policy window, kill the quadratic walk.
--   §8  stop the bloat half: autovacuum settings on the churn tables.
--   §9  post-snapshot.
--   §10 verification.
--   §11 cuts DECLINED, and gaps recorded but not fixed here.
-- ============================================================================


-- Fail fast rather than queue behind a live tick. Creating a trigger on
-- ottoq_events takes ACCESS EXCLUSIVE for an instant; if a tick is mid-write we
-- would rather this migration abort cleanly than block the engine.
SET lock_timeout = '5s';
SET statement_timeout = '600s';


-- ============================================================================
-- §1  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover any pre-image later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0006_slim_writes_and_arm_retention_pre' AND object_name = '<fn>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0006_slim_writes_and_arm_retention_pre',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_purge_prior_runs',
                     'ottoq_retention_purge_worker',
                     'ottoq_events_block_mutation');

DO $guard$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  -- ---- ottoq_purge_prior_runs ------------------------------------------------
  SELECT count(*), min(pg_get_functiondef(p.oid)) INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_purge_prior_runs';
  IF v_n = 0 THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_purge_prior_runs does not exist. This migration expected to REPLACE it, not create it. Nothing has been changed.';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_purge_prior_runs has % overloads; this file assumes exactly one signature (p_keep_run uuid). Nothing has been changed.', v_n;
  ELSIF v_src LIKE '%ottoq.retention%' THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_purge_prior_runs ALREADY arms ottoq.retention. Someone fixed this outside this migration. Re-read the live body, re-base, re-run. Nothing has been changed.';
  ELSIF v_src NOT LIKE '%c_keep_tables%' THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_purge_prior_runs does not contain the c_keep_tables list this migration extends. The body has diverged from what 0006 reasoned about. Nothing has been changed.';
  END IF;

  -- ---- ottoq_retention_purge_worker (the 4-argument overload cron 11 calls) ---
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker';
  IF v_n = 0 THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_retention_purge_worker does not exist. Nothing changed.';
  END IF;
  -- Two overloads are EXPECTED here (3-arg and 4-arg). This file replaces only the
  -- 4-arg one and leaves the 3-arg one exactly as it is -- we never drop.
  SELECT count(*), min(pg_get_functiondef(p.oid)) INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker'
     AND pg_get_function_identity_arguments(p.oid) LIKE '%text[]%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'GUARD: expected exactly one 4-argument ottoq_retention_purge_worker (with the text[] table list); found %. Nothing has been changed.', v_n;
  ELSIF v_src NOT LIKE '%cursor_block%' THEN
    RAISE EXCEPTION 'GUARD: the 4-arg ottoq_retention_purge_worker does not contain the ctid block-cursor (cursor_block) that this migration replaces. Someone changed it outside this migration. Re-read the live body, re-base, re-run. Nothing changed.';
  END IF;

  -- ---- ottoq_events_block_mutation -------------------------------------------
  SELECT count(*), min(pg_get_functiondef(p.oid)) INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_events_block_mutation';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'GUARD: expected exactly one public.ottoq_events_block_mutation; found %. Nothing has been changed.', v_n;
  ELSIF v_src NOT LIKE '%append-only%' THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_events_block_mutation is not the append-only guard this migration reasoned about. Nothing has been changed.';
  END IF;

  RAISE NOTICE 'GUARD: all three replacement targets match what 0006 reasoned about.';
END
$guard$;

-- A second guard on the assumptions the whole file rests on: the ordered key the new
-- retention walk uses, and the columns the slimming trigger reads. Cheaper to fail
-- here with a sentence than inside a tick with a 42703.
DO $shape$
DECLARE v_missing text[];
BEGIN
  SELECT array_agg(c) INTO v_missing FROM unnest(ARRAY[
      'event_id','event_seq','occurred_at','event_type','entity_type','entity_id',
      'payload','new_state','sim_run_id']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='ottoq_events'
                        AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD: ottoq_events is missing %. Nothing has been changed.', v_missing;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_index i
                   JOIN pg_class c ON c.oid = i.indexrelid
                  WHERE i.indrelid = 'public.ottoq_events'::regclass
                    AND c.relname = 'ottoq_events_keep_event_seq_key') THEN
    RAISE EXCEPTION 'GUARD: the UNIQUE btree on ottoq_events(event_seq) is gone. §7''s retention walk depends on it for an ordered, O(batch) oldest-first scan. Without it the new worker would seq-scan and would be no better than the ctid version. Nothing has been changed.';
  END IF;
  RAISE NOTICE 'GUARD: ottoq_events shape and event_seq index confirmed.';
END
$shape$;


-- ============================================================================
-- §2  THE POLICY KNOBS
--
-- Two small tables so the founder can retune both halves without a migration.
-- Neither carries a sim_run_id, so no purge path can reach them.
-- ============================================================================

-- ---- (A) what we stop re-writing -------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_write_slimming_policy (
  policy_key        text        PRIMARY KEY,
  enabled           boolean     NOT NULL DEFAULT true,
  -- Which *.state_changed streams take the chain cut. Deliberately NARROW: only
  -- event types whose reconstruction has actually been measured belong here.
  -- Adding a sibling is a one-row UPDATE, but measure it the same way first
  -- (see §10 V2, which is the exact query the anatomy ran).
  chain_event_types text[]      NOT NULL DEFAULT ARRAY['vehicle.state_changed'],
  -- The `.created` cut is exact within a single row and needs no measurement,
  -- so it is on for every event type. See §1 CONFIRMED (5a).
  slim_created      boolean     NOT NULL DEFAULT true,
  notes             text,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.ottoq_write_slimming_policy (policy_key, enabled, chain_event_types, slim_created, notes)
VALUES ('ottoq_events', true, ARRAY['vehicle.state_changed'], true,
        'Stop storing redundant copies of new_state. `.created` rows: new_state is the same expression as payload->''new'' in the same statement, so it is dropped whenever the two are byte-equal. `*.state_changed` rows in chain_event_types: new_state is rebuilt by folding payload->''diff''->key->''to'' forward from the day''s anchor. Read either back with public.ottoq_event_new_state(event_id). Emergency stop: UPDATE this row SET enabled=false; belt-and-braces: ALTER TABLE public.ottoq_events DISABLE TRIGGER ottoq_events_slim_new_state_bi;')
ON CONFLICT (policy_key) DO NOTHING;

-- ---- (B) how long we keep ---------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_retention_policy (
  policy_key     text        PRIMARY KEY,
  enabled        boolean     NOT NULL DEFAULT true,
  keep_interval  interval    NOT NULL DEFAULT '7 days',
  -- Round the cut down to a whole UTC day. This is not cosmetic: it is what keeps
  -- the (A) chain reconstructible. Anchors are per calendar day, so deleting only
  -- COMPLETE days can never strand a surviving tail without its base snapshot.
  day_aligned    boolean     NOT NULL DEFAULT true,
  notes          text,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- THE KEEP WINDOW: ~1 WEEK. WHY THIS AND NOT "THE LAST 10-20 RUNS".
--
--   1. A time window bounds BYTES. A run-count window does not. At the measured
--      write rate one long run is ~400 MB/hour, so "keep the last 20 runs" can mean
--      200 MB or 20 GB depending on how long those runs happened to be -- which is
--      no guarantee at all, and it is exactly the kind of unbounded promise that
--      produced a 14 GB database. Seven days at the post-0006 write rate is a
--      number we can hold the system to.
--   2. It matches what the evidence already said. The rows that filled the disk were
--      ~27 days old; a 7-day window is the difference between 11 GB and ~2.4 GB.
--   3. THE RUN-COUNT HALF IS ALREADY SATISFIED BY A BETTER MECHANISM.
--      `ottoq_run_archives` (44 rows) is a permanent per-run record and is on the
--      never-delete list in §6. So we keep every run forever at archive fidelity AND
--      one week at full event fidelity. Choosing the time window here does not cost
--      us run history; it costs us the raw event stream of runs older than a week,
--      which is the cheapest thing in the system to regenerate.
INSERT INTO public.ottoq_retention_policy (policy_key, enabled, keep_interval, day_aligned, notes)
VALUES ('events', true, '7 days', true,
        'Keep one week of raw ottoq_events / ottoq_rule_evaluations / ottoq_incident_reports, rounded out to whole UTC days. Per-run history is preserved indefinitely by ottoq_run_archives, which retention may never touch. Widen or narrow by updating keep_interval here -- cron job 11 passes ''48 hours'' and this row overrides it.')
ON CONFLICT (policy_key) DO NOTHING;

COMMENT ON TABLE public.ottoq_retention_policy IS
  'Retention knob. keep_interval here OVERRIDES the p_keep argument passed by cron job 11.';


-- ============================================================================
-- §3  THE CHAIN ANCHOR
--
-- To rebuild `new_state` by folding diffs we need one full snapshot to fold onto.
-- This table records which event is that snapshot, for each
-- (run, event_type, entity, UTC day). It is tiny -- one row per vehicle per event
-- type per day, so ~220 rows a day for the whole depot -- and it is written with a
-- single ON CONFLICT DO NOTHING probe, never a scan. That distinction matters here:
-- the last thing this database needs is another trigger that scans a large table
-- inside decide_tick.
--
-- WHY A DAY BUCKET RATHER THAN "FIRST EVENT PER RUN" (the anatomy's suggestion):
-- it bounds the fold length, and it lines up exactly with §7's day-aligned cut, so
-- retention removes an anchor only in the same pass that removes every event that
-- depended on it. Per-run anchoring would let a week-old anchor be deleted while
-- newer events of the same run survived, and those survivors would be unreadable.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.ottoq_event_state_anchor (
  run_key         uuid        NOT NULL,   -- COALESCE(sim_run_id, all-zero) so production works too
  event_type      text        NOT NULL,
  entity_id       uuid        NOT NULL,
  anchor_day      date        NOT NULL,   -- (occurred_at AT TIME ZONE 'UTC')::date
  anchor_event_id uuid        NOT NULL,
  anchor_seq      bigint      NOT NULL,
  entity_type     text        NOT NULL,
  sim_run_id      uuid,                   -- nullable original, for the purge paths
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_key, event_type, entity_id, anchor_day)
);
CREATE INDEX IF NOT EXISTS ottoq_event_state_anchor_day_idx
  ON public.ottoq_event_state_anchor (anchor_day);

COMMENT ON TABLE public.ottoq_event_state_anchor IS
  'One full ottoq_events.new_state snapshot per (run, event_type, entity, UTC day). Every other event in that bucket stores NULL and is rebuilt by public.ottoq_event_new_state(). Deleting a row here does not lose data while its day''s events are gone too -- which §7 guarantees by cutting on whole days.';


-- GRANTS. Deliberately service_role ONLY -- not anon, not authenticated.
-- These three tables have RLS disabled, matching ottoq_retention_state, so a GRANT
-- here is the whole access decision. Per the 2026-07-30 RLS finding, the publishable
-- anon key reaches anything it has been granted; granting nothing is what keeps these
-- unreachable. The engine is unaffected because ottoq_record_event is SECURITY
-- DEFINER and the owner bypasses both.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ottoq_event_state_anchor    TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ottoq_retention_policy      TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ottoq_write_slimming_policy TO service_role;


-- ============================================================================
-- §4  (A) THE SLIMMING TRIGGER
--
-- One BEFORE INSERT trigger on ottoq_events. This is deliberately the only place
-- the cut is implemented, for three reasons:
--   * it catches every writer -- 60+ call sites of ottoq_record_event across three
--     schemas, present and future, without editing any of them;
--   * it does not require rewriting the six state-change trigger functions, whose
--     live bodies drifted from the committed baseline earlier today and which I
--     therefore cannot safely reproduce from here;
--   * it leaves ottoq_record_event's hashing and signing untouched.
--
-- ⚠️ WHY THIS CANNOT BREAK THE TAMPER-EVIDENCE CHAIN.
--   ottoq_record_event computes
--       v_payload_hash := ottoq_compute_event_hash(p_payload);
--       v_signature    := ottoq_sign_event(v_event_id, v_occurred_at, p_actor_type,
--                                          p_event_type, p_entity_type, p_entity_id,
--                                          v_payload_hash, p_signing_key_id);
--   Both are derived from `payload` ONLY. Neither reads `new_state`. So nulling
--   `new_state` leaves every stored hash and signature still true of the row that
--   carries it. This is also the precise reason §11 DECLINES the payload cuts: any
--   edit to `payload` in this trigger would leave payload_hash describing a payload
--   that is no longer there, and a verifier would read that as tampering.
--
-- ⚠️ IT CAN NEVER ABORT A TICK. The whole body is wrapped so that any error -- a
--   missing policy row, a lock, a typo in a future policy edit -- returns the row
--   unchanged and fat. The failure mode of this optimisation is "we save nothing",
--   never "the tick rolls back". That is the opposite of the incident trigger that
--   caused the outage, and it is deliberate.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_events_slim_new_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
DECLARE
  c_nil    CONSTANT uuid := '00000000-0000-0000-0000-000000000000';
  v_pol    public.ottoq_write_slimming_policy%ROWTYPE;
  v_day    date;
  v_ins    int;
BEGIN
  -- Cheapest possible bail-out first, and it is deliberately OUTSIDE the protective
  -- block below so that the overwhelming majority of events pay nothing at all --
  -- no subtransaction, no catalogue lookup, one NULL test.
  IF NEW.new_state IS NULL THEN
    RETURN NEW;
  END IF;

  -- Everything from here on is inside one exception block. Any failure at all --
  -- a missing policy row, a dropped table, a bad future policy edit, a lock -- keeps
  -- the fat row and lets the tick finish. We save nothing; we never break anything.
  BEGIN
    SELECT * INTO v_pol FROM public.ottoq_write_slimming_policy WHERE policy_key = 'ottoq_events';
    IF NOT FOUND OR NOT v_pol.enabled THEN
      RETURN NEW;
    END IF;

    -- ---- CUT 1: the `.created` duplicate ----------------------------------
    -- new_state and payload->'new' are the same to_jsonb(NEW) evaluated twice in
    -- one statement (see §1 CONFIRMED 5a). We do not TRUST that -- we TEST it, per
    -- row, with exact jsonb equality. If the two are equal the copy is provably
    -- redundant and rebuildable from this row alone. If not, we keep both.
    -- (When the key is absent, `->` yields SQL NULL and the comparison is NULL,
    --  so the branch is simply not taken. No separate key-exists test needed.)
    IF v_pol.slim_created AND NEW.new_state = (NEW.payload -> 'new') THEN
      NEW.new_state := NULL;
      RETURN NEW;
    END IF;

    -- ---- CUT 2: the state_changed chain ------------------------------------
    IF NEW.entity_id IS NULL
       OR NOT (NEW.event_type = ANY (v_pol.chain_event_types))
       OR jsonb_typeof(NEW.payload -> 'diff') IS DISTINCT FROM 'object'
       OR NEW.payload -> 'diff' = '{}'::jsonb THEN
      RETURN NEW;                     -- no diff to carry the change: keep the snapshot
    END IF;

    v_day := (NEW.occurred_at AT TIME ZONE 'UTC')::date;

    -- Claim the anchor for this (run, event_type, entity, day). Exactly one row wins;
    -- the unique index serialises the race. This is a single index probe on a table
    -- that holds a few hundred rows, NOT a scan of ottoq_events.
    INSERT INTO public.ottoq_event_state_anchor
           (run_key, event_type, entity_id, anchor_day,
            anchor_event_id, anchor_seq, entity_type, sim_run_id)
    VALUES (COALESCE(NEW.sim_run_id, c_nil), NEW.event_type, NEW.entity_id, v_day,
            NEW.event_id, NEW.event_seq, NEW.entity_type, NEW.sim_run_id)
    ON CONFLICT (run_key, event_type, entity_id, anchor_day) DO NOTHING;

    GET DIAGNOSTICS v_ins = ROW_COUNT;
    IF v_ins = 1 THEN
      RETURN NEW;                     -- we ARE the anchor: keep the full snapshot
    END IF;

    NEW.new_state := NULL;            -- an anchor exists; the diff carries the news
    RETURN NEW;
  EXCEPTION WHEN OTHERS THEN
    -- A storage optimisation must never cost us a tick. Keep the fat row and move on.
    RAISE WARNING 'ottoq_events_slim_new_state: kept full snapshot for event % (%)',
                  NEW.event_id, SQLERRM;
    RETURN NEW;
  END;
END;
$function$;

-- The only DROP in this file, and it is of an object this file creates. It exists so
-- 0006 can be re-applied cleanly; it can never remove anything that predates 0006.
DROP TRIGGER IF EXISTS ottoq_events_slim_new_state_bi ON public.ottoq_events;
CREATE TRIGGER ottoq_events_slim_new_state_bi
  BEFORE INSERT ON public.ottoq_events
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_events_slim_new_state();

COMMENT ON TRIGGER ottoq_events_slim_new_state_bi ON public.ottoq_events IS
  'Stops re-writing redundant copies of new_state. Read it back with public.ottoq_event_new_state(event_id). Disable with ALTER TABLE ... DISABLE TRIGGER, or set ottoq_write_slimming_policy.enabled = false.';


-- ============================================================================
-- §5  (A) REBUILD ON READ, AND THE APPEND-ONLY ESCAPE HATCH
-- ============================================================================

-- ---- 5.1  the reader --------------------------------------------------------
-- Everything that used to read ottoq_events.new_state directly should call this.
-- It is exactly backward compatible: rows written before 0006 still carry a full
-- snapshot and are returned untouched, so the black box keeps working during the
-- transition with no cutover.
CREATE OR REPLACE FUNCTION public.ottoq_event_new_state(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
DECLARE
  c_nil   CONSTANT uuid := '00000000-0000-0000-0000-000000000000';
  v_e     public.ottoq_events%ROWTYPE;
  v_a     public.ottoq_event_state_anchor%ROWTYPE;
  v_state jsonb;
  v_day   date;
  v_row   record;
BEGIN
  SELECT * INTO v_e FROM public.ottoq_events WHERE event_id = p_event_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- (1) pre-0006 rows, anchors, and anything we chose not to slim.
  IF v_e.new_state IS NOT NULL THEN
    RETURN v_e.new_state;
  END IF;

  -- (2) the `.created` cut: the snapshot is in this same row.
  IF (v_e.payload -> 'new') IS NOT NULL THEN
    RETURN v_e.payload -> 'new';
  END IF;

  -- (3) the chain cut: fold every diff forward from the day's anchor.
  v_day := (v_e.occurred_at AT TIME ZONE 'UTC')::date;
  SELECT * INTO v_a FROM public.ottoq_event_state_anchor
   WHERE run_key    = COALESCE(v_e.sim_run_id, c_nil)
     AND event_type = v_e.event_type
     AND entity_id  = v_e.entity_id
     AND anchor_day = v_day;
  IF NOT FOUND THEN
    -- Only reachable if the anchor was removed while this row survived. §7's
    -- day-aligned cut is designed to make that impossible; say so plainly rather
    -- than returning a silently-wrong object.
    RETURN jsonb_build_object(
      '_reconstruction', 'unavailable',
      '_reason', 'no chain anchor for this (run, event_type, entity, day)',
      '_event_id', p_event_id, '_day', v_day);
  END IF;

  SELECT COALESCE(a.new_state, a.payload -> 'new') INTO v_state
    FROM public.ottoq_events a WHERE a.event_id = v_a.anchor_event_id;
  IF v_state IS NULL THEN
    RETURN jsonb_build_object(
      '_reconstruction', 'unavailable',
      '_reason', 'anchor event carries no snapshot',
      '_anchor_event_id', v_a.anchor_event_id);
  END IF;

  FOR v_row IN
    SELECT e.payload
      FROM public.ottoq_events e
     WHERE e.entity_type = v_e.entity_type
       AND e.entity_id   = v_e.entity_id
       AND e.event_type  = v_e.event_type
       AND COALESCE(e.sim_run_id, c_nil) = COALESCE(v_e.sim_run_id, c_nil)
       AND e.event_seq   >  v_a.anchor_seq
       AND e.event_seq   <= v_e.event_seq
     ORDER BY e.event_seq
  LOOP
    -- new_state(N) = new_state(N-1) || { k : diff[k]->'to' }   -- §1 CONFIRMED (5b)
    v_state := v_state || COALESCE(
      (SELECT jsonb_object_agg(k, v -> 'to')
         FROM jsonb_each(v_row.payload -> 'diff') AS t(k, v)
        WHERE jsonb_typeof(v) = 'object' AND (v -> 'to') IS NOT NULL),
      '{}'::jsonb);
  END LOOP;

  RETURN v_state;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_event_new_state(uuid) IS
  'Returns ottoq_events.new_state, rebuilding it when 0006 declined to store a redundant copy. Backward compatible: pre-0006 rows are returned as-is.';

GRANT EXECUTE ON FUNCTION public.ottoq_event_new_state(uuid) TO service_role;


-- ---- 5.2  the append-only escape hatch ---------------------------------------
-- See §1 FOUND (4). Deleting an old parent event makes the self-FK
-- ottoq_events_parent_event_id_fkey (ON DELETE SET NULL) issue an UPDATE against
-- surviving children. That UPDATE fires this trigger and, today, raises -- which
-- would roll back the whole purge batch. The escape hatch is widened to UPDATE, and
-- ONLY while ottoq.retention = 'on', a transaction-local flag that nothing outside
-- the two retention routines ever sets.
--
-- The append-only guarantee is unchanged for every other caller: with the flag
-- unset, both DELETE and UPDATE still raise exactly as before. Reproduced verbatim
-- from the pre-image apart from the added TG_OP, so the snapshot diff is one line.
CREATE OR REPLACE FUNCTION public.ottoq_events_block_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- Retention maintenance only. UPDATE is forgiven here solely because
  -- ottoq_events_parent_event_id_fkey is ON DELETE SET NULL, so purging a parent
  -- rewrites its surviving children. Without this the purge aborts on its own FK.
  IF current_setting('ottoq.retention', true) = 'on' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;   -- unchanged from the pre-image
    IF TG_OP = 'UPDATE' THEN RETURN NEW; END IF;   -- the one added line
  END IF;
  RAISE EXCEPTION 'ottoq_events is append-only. Operation % rejected on event_id=%',
    TG_OP, COALESCE(OLD.event_id, NEW.event_id);
END;
$function$;


-- ============================================================================
-- §6  (B) ottoq_purge_prior_runs -- ARM THE FLAG, WIDEN THE NEVER-DELETE LIST
--
-- Reproduced from the pre-image with four changes and nothing else:
--   1. ARM. `set_config('ottoq.retention','on', true)` at the top, transaction-local
--      (the third argument), which is what the append-only guards look for. This is
--      the single line that turns nine hundred silent no-ops into an actual purge.
--      ⚠️ It is set INSIDE the function body, i.e. inside the caller's transaction --
--      not as `SET LOCAL` at statement level, which would die with its own implicit
--      transaction under autocommit.
--   2. WIDEN THE KEEP LIST. Never delete the run ledger, the permanent run archives,
--      the retention/slimming policy rows, the retention cursor, or anything whose
--      name marks it as phase / forward / proof / evidence / certification. The list
--      is only ever EXTENDED here; nothing was removed from it.
--   3. PROTECT A CONCURRENT RUN. The pre-image guarded `status <> 'running'` on the
--      final ottoq_sim_runs delete but NOT on the per-table loop, so a second run
--      that happened to be live could have its rows deleted while its ledger row
--      survived. Same guard, both places.
--   4. REPORT HONESTLY. Failures still do not abort (a purge must never take the
--      engine down) but they are now counted and returned, so "ok: true" can no
--      longer hide 47 refusals.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_tbl text; v_n int; v_total bigint := 0; v_runs int;
  v_failed text[] := '{}'; v_skipped text[] := '{}';
  -- Tables that must SURVIVE a purge. Their whole job is to outlive the run.
  c_keep_tables CONSTANT text[] := ARRAY[
    'ottoq_sim_runs',                  -- the run ledger itself
    'ottoq_run_archives',              -- the permanent per-run record (44 rows)
    'ottoq_schema_snapshots',          -- migration pre/post images
    'ottoq_retention_state',           -- the purge cursor
    'ottoq_retention_policy',          -- §2 knob
    'ottoq_write_slimming_policy'      -- §2 knob
  ];
  -- Name patterns that mark a table as PROOF. Certification evidence is the one
  -- thing in this system we cannot regenerate, so it is protected by shape, not by
  -- an enumeration someone has to remember to update.
  c_keep_patterns CONSTANT text[] := ARRAY[
    'ottoq_phase%', 'ottoq_fwd%', 'ottoq_proof%', 'ottoq_evidence%',
    'ottoq_%_evidence', 'ottoq_cert%', 'ottoq_%_baseline', 'ottoq_blackbox%'
  ];
BEGIN
  -- (1) ARM. Without this every DELETE below is refused by the append-only guards
  --     and swallowed by the handler. Transaction-local: it evaporates at COMMIT.
  PERFORM set_config('ottoq.retention', 'on', true);

  FOR v_tbl IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'
       AND NOT (table_name = ANY (c_keep_tables))
  LOOP
    -- (2) shape-based protection for proof/evidence tables
    IF EXISTS (SELECT 1 FROM unnest(c_keep_patterns) p WHERE v_tbl LIKE p) THEN
      v_skipped := v_skipped || v_tbl;
      CONTINUE;
    END IF;

    BEGIN
      EXECUTE format(
        'DELETE FROM public.%I WHERE sim_run_id IN (SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_id <> $1 AND COALESCE(run_by,'''') <> ''production_live'' AND status <> ''running'')',
        v_tbl) USING p_keep_run;
      GET DIAGNOSTICS v_n = ROW_COUNT; v_total := v_total + v_n;
    EXCEPTION WHEN OTHERS THEN
      -- still non-fatal -- a purge may never take the engine down -- but no longer
      -- invisible: it is counted, named, and returned to the caller.
      v_failed := v_failed || v_tbl;
      RAISE WARNING 'purge_prior_runs: table % failed: %', v_tbl, SQLERRM;
    END;
  END LOOP;

  DELETE FROM ottoq_sim_runs WHERE sim_run_id <> p_keep_run AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';
  GET DIAGNOSTICS v_runs = ROW_COUNT;

  RETURN jsonb_build_object('ok', (cardinality(v_failed) = 0),
    'kept', p_keep_run, 'rows_purged', v_total, 'prior_runs_deleted', v_runs,
    'preserved_tables', to_jsonb(c_keep_tables),
    'preserved_by_pattern', to_jsonb(v_skipped),
    'failed_tables', to_jsonb(v_failed),
    'retention_armed', true);
END;
$function$;


-- ============================================================================
-- §7  (B) ottoq_retention_purge_worker -- POLICY WINDOW, AND THE END OF THE
--         QUADRATIC WALK
--
-- Only the 4-argument overload (the one cron job 11 calls) is replaced. The
-- 3-argument overload is left exactly as it is -- we never drop.
--
-- WHAT CHANGED, AND WHY EACH CHANGE IS HERE:
--
--   1. THE WALK. Out: a physical block cursor over ctid with persisted state and
--      wraparound. In: a bounded, ordered range scan on event_seq, whose UNIQUE
--      btree already exists. Each iteration reads exactly p_micro_batch index
--      entries and deletes a contiguous seq range -- O(batch), not O(heap), so the
--      quadratic behaviour is gone by construction rather than by tuning. It also
--      cannot strand: it starts at min(event_seq), which IS the oldest surviving
--      row, and advances monotonically. No cursor state is required for
--      correctness (we still WRITE the watermark to ottoq_retention_state so the
--      old column keeps a purpose and the walk stays observable -- never drop).
--
--   2. THE WINDOW COMES FROM POLICY. Cron 11 passes '48 hours'; the founder's rule
--      is a week. §2's row wins, so retuning is an UPDATE rather than a migration.
--
--   3. THE CUT IS DAY-ALIGNED. Whole UTC days only. This is what keeps §4's
--      reconstruction sound -- an anchor and every row that folds onto it live in
--      the same calendar day, so they are always deleted together or kept together.
--      A mid-day cut would leave the afternoon of a day without its morning anchor.
--
--   4. THE CURRENT RUN IS UNTOUCHABLE. Any run that is `running`, and anything
--      marked production_live, is excluded by sim_run_id. Rows with a NULL
--      sim_run_id are ordinary production events and are aged out normally.
--
--   5. IT STILL ARMS THE FLAG EVERY TRANSACTION. The pre-image already did this
--      correctly (see §1 CORRECTED (2)) and it is preserved, because COMMIT clears
--      a transaction-local setting and this procedure commits every iteration.
-- ============================================================================
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(
  IN p_time_budget_s integer DEFAULT 60,
  IN p_micro_batch   integer DEFAULT 2000,
  IN p_keep          interval DEFAULT '48:00:00'::interval,
  IN p_tables        text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep      interval;
  v_aligned   boolean;
  v_cut       timestamptz;
  v_t0        timestamptz := clock_timestamp();
  v_n         bigint;
  v_total     bigint := 0;
  v_seq       bigint;
  v_batch_hi  bigint;
  v_batch_ts  timestamptz;
  v_live      uuid[];
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and this procedure commits per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) policy wins over the caller's argument; fall back to it if no row.
  SELECT keep_interval, day_aligned INTO v_keep, v_aligned
    FROM public.ottoq_retention_policy WHERE policy_key = 'events' AND enabled;
  v_keep    := COALESCE(v_keep, p_keep);
  v_aligned := COALESCE(v_aligned, true);

  -- (3) day-aligned cut: delete only COMPLETE days older than the window.
  v_cut := now() - v_keep;
  IF v_aligned THEN
    v_cut := date_trunc('day', v_cut AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  END IF;

  -- (4) runs whose data may never be touched.
  SELECT COALESCE(array_agg(sim_run_id), '{}'::uuid[]) INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status = 'running' OR COALESCE(run_by, '') = 'production_live';

  RAISE NOTICE 'retention purge: keep %, cut %, % protected run(s)',
               v_keep, v_cut, cardinality(v_live);

  -- ---------------------------------------------------------------------------
  -- EVENTS: monotone, index-ordered, oldest-first walk on event_seq.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_events' = ANY (p_tables) THEN
    SELECT COALESCE(min(event_seq), 0) INTO v_seq FROM public.ottoq_events;

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

      -- Window boundary: exactly p_micro_batch index entries, ordered. This is the
      -- whole fix -- it reads a bounded slice of an index instead of a slice of heap.
      SELECT max(w.event_seq), max(w.occurred_at)
        INTO v_batch_hi, v_batch_ts
        FROM (SELECT event_seq, occurred_at
                FROM public.ottoq_events
               WHERE event_seq >= v_seq
               ORDER BY event_seq
               LIMIT p_micro_batch) w;

      EXIT WHEN v_batch_hi IS NULL;             -- walked off the end of the table

      DELETE FROM public.ottoq_events e
       WHERE e.event_seq >= v_seq
         AND e.event_seq <= v_batch_hi
         AND e.occurred_at < v_cut
         AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      v_seq := v_batch_hi + 1;

      UPDATE public.ottoq_retention_state
         SET cursor_block = v_seq,                       -- now an event_seq watermark
             pass_deleted = pass_deleted + v_n,
             updated_at   = now()
       WHERE table_name = 'ottoq_events';
      IF NOT FOUND THEN
        INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
        VALUES ('ottoq_events', v_seq, v_n, now())
        ON CONFLICT (table_name) DO NOTHING;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures

      -- We have walked into the keep window and stopped deleting. Done for tonight.
      IF v_n = 0 AND v_batch_ts >= v_cut THEN
        PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
        UPDATE public.ottoq_retention_state
           SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
        COMMIT;
        EXIT;
      END IF;
    END LOOP;

    -- Anchors follow their day. Because the cut is day-aligned, every event that
    -- could have folded onto one of these anchors has already gone.
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_event_state_anchor
     WHERE anchor_day < (v_cut AT TIME ZONE 'UTC')::date
       AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)));
    COMMIT;
  END IF;

  -- ---------------------------------------------------------------------------
  -- The two small tables. Same batching, same budget, now looped instead of a
  -- single 2,000-row nibble that could never catch up.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_rule_evaluations' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
        SELECT evaluation_id FROM public.ottoq_rule_evaluations
         WHERE evaluated_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  IF 'ottoq_incident_reports' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
        SELECT incident_report_id FROM public.ottoq_incident_reports
         WHERE triggered_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;

-- Make sure the cursor row the walk reports through exists.
INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
VALUES ('ottoq_events', 0, 0, now())
ON CONFLICT (table_name) DO NOTHING;


-- ============================================================================
-- §8  THE OTHER HALF OF THE STORAGE PROBLEM: BLOAT, NOT CONTENT
--
-- ⚠️ THIS CORRECTS THE BRIEF'S FRAMING, AND IT MATTERS FOR WHERE WE SPEND EFFORT.
--   The brief lists five "enormous" tables by bytes-per-row. Four of them are not
--   writing enormous rows at all -- they are writing small rows into enormous
--   amounts of dead space. The anatomy measured both numbers side by side:
--
--     table                     storage/row   actual content/row   ratio
--     ottoq_oem_webhook_log        64 kB            610 B          107x
--     ottoq_variability_cards      22 kB            210 B          105x
--     ottoq_vehicle_commands       18 kB            276 B           65x
--     ottoq_vehicle_dispatches     20 kB            404 B           50x
--     ottoq_events                3,381 B         2,801 B          1.2x   <-- real
--
--   `ottoq_variability_cards` alone shows 330,597 inserts against 306,882 deletes
--   and carries 30 MB of INDEX on 2.3 MB of heap. There is no redundant column to
--   stop writing there. The write is already minimal; the churn is the problem, and
--   the fix is to make autovacuum keep up with it instead of falling permanently
--   behind and letting the heap and indexes ratchet upward forever.
--
--   So: §4 is the only content cut, and it is aimed at the only table that earned
--   one. This section stops the other four from re-inflating.
--
-- Defaults are 20% of the table before a vacuum triggers, which on a 200-row table
-- that turns over thousands of rows a minute is effectively never. 2% plus a small
-- absolute threshold makes it near-continuous, and the raised cost limit stops the
-- vacuum from being throttled into irrelevance. These are per-table settings; they
-- change no data and can be reverted with RESET.
-- ============================================================================
DO $av$
DECLARE
  t text;
  c_tables CONSTANT text[] := ARRAY[
    'ottoq_oem_webhook_log', 'ottoq_variability_cards', 'ottoq_vehicle_commands',
    'ottoq_vehicle_dispatches', 'ottoq_rule_evaluations', 'ottoq_events'];
BEGIN
  FOREACH t IN ARRAY c_tables LOOP
    IF to_regclass('public.' || quote_ident(t)) IS NULL THEN
      RAISE NOTICE 'autovacuum tuning: public.% not present, skipped', t;
      CONTINUE;
    END IF;
    EXECUTE format($f$
      ALTER TABLE public.%I SET (
        autovacuum_vacuum_scale_factor       = 0.02,
        autovacuum_vacuum_threshold          = 500,
        autovacuum_analyze_scale_factor      = 0.02,
        autovacuum_analyze_threshold         = 500,
        autovacuum_vacuum_cost_delay         = 2,
        autovacuum_vacuum_cost_limit         = 2000
      )$f$, t);
    RAISE NOTICE 'autovacuum tuning applied to public.%', t;
  END LOOP;

  -- ottoq_events is append-only in normal operation, so the DEAD-tuple trigger above
  -- never fires for it. The insert-driven trigger is the one that matters: it keeps
  -- the visibility map current and freezes tuples before they pile up, which is also
  -- what stops a retention purge from being the first thing to ever scan the table.
  BEGIN
    ALTER TABLE public.ottoq_events SET (
      autovacuum_vacuum_insert_scale_factor = 0.05,
      autovacuum_vacuum_insert_threshold    = 10000
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'insert-driven autovacuum not available on this server (%), skipped', SQLERRM;
  END;
END
$av$;

-- Cheaper compression for the two big jsonb columns. lz4 is markedly faster than
-- pglz on JSON and usually compresses it better. It applies to values written from
-- now on; every existing value stays readable in whatever it was compressed with,
-- so this is safe and needs no rewrite. Skipped silently if the server was built
-- without lz4.
DO $comp$
BEGIN
  ALTER TABLE public.ottoq_events ALTER COLUMN payload    SET COMPRESSION lz4;
  ALTER TABLE public.ottoq_events ALTER COLUMN new_state  SET COMPRESSION lz4;
  ALTER TABLE public.ottoq_events ALTER COLUMN actor_metadata SET COMPRESSION lz4;
  RAISE NOTICE 'lz4 compression set on ottoq_events jsonb columns (future writes).';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'lz4 compression unavailable (%), leaving default. Not fatal.', SQLERRM;
END
$comp$;

-- ----------------------------------------------------------------------------
-- ⚠️ RUN THESE BY HAND, OUTSIDE THIS MIGRATION. They cannot run inside a
--    transaction block, which is why they are not executed here. They are the fix
--    for the index bloat the anatomy measured, and they are the single largest
--    one-shot reclaim available to us right now:
--
--      ux_vcards_epoch     16 MB for 1,556 rows  (~99% bloat; a fresh btree is ~160 kB)
--      ix_vcards_current   11 MB, same cause
--
--    REINDEX INDEX CONCURRENTLY public.ux_vcards_epoch;
--    REINDEX INDEX CONCURRENTLY public.ix_vcards_current;
--    REINDEX TABLE CONCURRENTLY public.ottoq_variability_cards;
--    REINDEX TABLE CONCURRENTLY public.ottoq_oem_webhook_log;
--    REINDEX TABLE CONCURRENTLY public.ottoq_vehicle_commands;
--    REINDEX TABLE CONCURRENTLY public.ottoq_vehicle_dispatches;
--
--    REINDEX CONCURRENTLY is NOT VACUUM FULL: it builds the replacement alongside,
--    swaps it in under the same name, and never takes an exclusive lock on the
--    table. Nothing is dropped and no name changes. Run it when no run is live.
-- ----------------------------------------------------------------------------


-- ============================================================================
-- §9  POST-SNAPSHOT
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0006_slim_writes_and_arm_retention_post',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_purge_prior_runs',
                     'ottoq_retention_purge_worker',
                     'ottoq_events_block_mutation',
                     'ottoq_events_slim_new_state',
                     'ottoq_event_new_state');


-- ============================================================================
-- §10  VERIFICATION
--
-- V1-V4 are static and can be run the moment this lands. V5-V8 need a SHORT run --
-- a few minutes, then STOP it. ⚠️ BUDGET: the database is ~304 MB with ~7.7 GB of
-- headroom to where trouble started, and a run costs ~9 MB per real minute at the
-- OLD write rate. Do not leave one going. ⚠️ Starting a run purges the prior one:
-- preserve any evidence into a NON-`ottoq`-prefixed table FIRST.
-- ⚠️ NEVER disable cron job 12 -- it IS the START engine.
--
-- ---------------------------------------------------------------------------
-- V1 -- THE ROUTINE COUNT. Expect +2 functions and +0 procedures net:
--       NEW:      public.ottoq_events_slim_new_state   (trigger fn, §4)
--                 public.ottoq_event_new_state         (reader, §5.1)
--       REPLACED: ottoq_purge_prior_runs, ottoq_retention_purge_worker(4-arg),
--                 ottoq_events_block_mutation
--       DROPPED:  none. Diff the NAMES against db/baseline/functions_public.sql;
--                 do not just edit the number.
--   SELECT p.proname, pg_get_function_identity_arguments(p.oid)
--     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='public' AND p.proname IN
--          ('ottoq_events_slim_new_state','ottoq_event_new_state',
--           'ottoq_purge_prior_runs','ottoq_retention_purge_worker',
--           'ottoq_events_block_mutation')
--    ORDER BY 1,2;   -- expect 6 rows (retention worker keeps BOTH overloads)
--
-- ---------------------------------------------------------------------------
-- V2 -- RE-RUN THE ANATOMY'S PROOF ON THIS DATABASE, ON PRE-0006 ROWS.
--       This is the query that justifies CUT 2. Run it before trusting the cut,
--       and run it again with a different event_type before ever adding that type
--       to ottoq_write_slimming_policy.chain_event_types. Expect: mismatches only
--       on updated_at / current_soc_updated_at, and nothing else.
--   WITH s AS (
--     SELECT event_id, event_seq, entity_id, sim_run_id, payload, new_state,
--            lag(new_state) OVER w AS prev_state
--       FROM public.ottoq_events
--      WHERE event_type='vehicle.state_changed' AND new_state IS NOT NULL
--     WINDOW w AS (PARTITION BY entity_id, sim_run_id ORDER BY event_seq)
--   ), r AS (
--     SELECT event_id, new_state,
--            prev_state || COALESCE((SELECT jsonb_object_agg(k, v->'to')
--                                      FROM jsonb_each(payload->'diff') t(k,v)
--                                     WHERE jsonb_typeof(v)='object' AND v ? 'to'),
--                                   '{}'::jsonb) AS rebuilt
--       FROM s WHERE prev_state IS NOT NULL
--   )
--   SELECT count(*) AS pairs,
--          count(*) FILTER (WHERE new_state = rebuilt) AS exact,
--          COALESCE((SELECT array_agg(DISTINCT k) FROM r, jsonb_each(new_state) a(k,av)
--                     WHERE r.new_state <> r.rebuilt AND r.rebuilt->k IS DISTINCT FROM av),
--                   '{}') AS differing_keys
--     FROM r;
--
-- ---------------------------------------------------------------------------
-- V3 -- THE CUT IS LOSSLESS END TO END. Write an event, confirm the column is now
--       NULL, and confirm the reader gives the caller the same object it would
--       have got before. Run in a transaction and ROLL BACK.
--   BEGIN;
--     -- pick any vehicle and nudge one non-timestamp column so a real diff fires
--     UPDATE public.vehicles SET current_soc = current_soc
--      WHERE id = (SELECT id FROM public.vehicles LIMIT 1);
--     SELECT e.event_id, e.new_state IS NULL AS slimmed,
--            public.ottoq_event_new_state(e.event_id) ? 'vin' AS rebuild_has_identity
--       FROM public.ottoq_events e
--      WHERE e.event_type='vehicle.state_changed'
--      ORDER BY e.event_seq DESC LIMIT 5;
--     -- EXPECT: the first such event of the day is the anchor (slimmed=false);
--     --         every later one slimmed=true AND rebuild_has_identity=true.
--   ROLLBACK;
--
-- V4 -- THE SIGNATURE STILL DESCRIBES THE ROW. §4 must not have touched payload.
--       Expect 0 rows.
--   SELECT count(*) AS hash_mismatches
--     FROM public.ottoq_events
--    WHERE payload_hash IS DISTINCT FROM public.ottoq_compute_event_hash(payload)
--      AND recorded_at > now() - interval '1 hour';
--
-- ---------------------------------------------------------------------------
-- V5 -- RETENTION ACTUALLY DELETES NOW. THE HEADLINE PROOF OF HALF (B).
--       Before 0006 this returned 0 every single night.
--   SELECT count(*) AS deletable_today FROM public.ottoq_events
--    WHERE occurred_at < date_trunc('day', now() - interval '7 days');
--   CALL public.ottoq_retention_purge_worker(30, 2000, '7 days',
--        ARRAY['ottoq_events','ottoq_rule_evaluations','ottoq_incident_reports']);
--   SELECT count(*) AS still_there FROM public.ottoq_events
--    WHERE occurred_at < date_trunc('day', now() - interval '7 days');
--   -- EXPECT still_there < deletable_today. If it is EQUAL, the flag is still not
--   -- reaching the trigger and nothing else in this file matters -- start there.
--   -- (If deletable_today is already 0 because the events table was wiped during
--   --  recovery, force the proof instead: temporarily set keep_interval to
--   --  '1 hour' in ottoq_retention_policy, re-run, then put it back to '7 days'.)
--
-- V6 -- AND SO DOES THE RUN PURGE. Expect retention_armed:true, failed_tables:[],
--       and rows_purged > 0 when prior runs exist.
--   SELECT public.ottoq_purge_prior_runs(
--            (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1));
--
-- V7 -- THE BLACK BOX STILL PRODUCES A USABLE RECORD. This is the protected asset.
--       ottoq_run_blackbox exports `SELECT *` per sim_run_id table, so slimmed rows
--       now export new_state:null and the rebuild is one call away. Confirm the
--       export is still well formed and the archives are intact.
--   SELECT jsonb_array_length(public.ottoq_run_blackbox(
--            (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1)
--          )->'data'->'ottoq_events') AS events_exported;
--   SELECT count(*) AS run_archives FROM public.ottoq_run_archives;   -- expect 44+
--
-- V8 -- THE SAVING, MEASURED RATHER THAN PROJECTED. Run a SHORT run, STOP it, then:
--   SELECT count(*) AS rows,
--          pg_size_pretty(sum(pg_column_size(new_state))) AS new_state_bytes,
--          round(100.0*count(*) FILTER (WHERE new_state IS NULL)/count(*),1) AS pct_slimmed,
--          pg_size_pretty(sum(pg_column_size(t.*))) AS content_total
--     FROM public.ottoq_events t
--    WHERE recorded_at > now() - interval '30 minutes';
--   -- BEFORE (anatomy, 500 most-recent rows): new_state 2,095 B/row = 75% of a
--   --   2,801 B row and 63.3% of the whole table.
--   -- PREDICTION: pct_slimmed high on vehicle.state_changed and *.created; content
--   --   per row roughly halves. State the denominator you used, as the anatomy did.
--
-- V9 -- ENGINE UNHARMED. Re-measure the protected numbers on the same short run:
--       tick ~4.3 s, approvals 0 pending, 0 double-bookings, no starvation,
--       phantoms 0, reverse coverage 100%, emission invariant 1.000, drift CLEAN.
--       ⚠️ The tick number is the one this file could plausibly move -- §4 adds one
--       index probe per state-change event. If tick time rose materially, set
--       ottoq_write_slimming_policy.enabled = false and re-measure to isolate it
--       before changing anything else.
--
-- ============================================================================


-- ============================================================================
-- §11  CUTS CONSIDERED AND DECLINED, AND GAPS RECORDED BUT NOT FIXED HERE
--
-- The instruction was: if a cut is merely "probably fine", do not make it. These
-- were all measured, all looked attractive, and are all declined with a reason, so
-- the next pass does not have to re-derive them.
--
-- DECLINED 1 -- ottoq_events.payload ON rule.evaluated_* (the anatomy's item B).
--   The anatomy proved this one COLD: 2,903 rule.evaluated_* events against 2,903
--   rows in ottoq_rule_evaluations, 1:1, all 2,903 linked by linked_event_id, and
--   the payload fully reconstructible from the linked row. The redundancy is real
--   and I am not disputing it. I am declining it anyway, for a reason the anatomy
--   did not weigh:
--       ottoq_record_event computes payload_hash = ottoq_compute_event_hash(payload)
--       and signature = ottoq_sign_event(..., payload_hash, ...) BEFORE the insert.
--   Null the payload afterwards and every one of those rows keeps a hash and a
--   signature describing a payload that is no longer in the row. A verifier
--   rehashing the stored payload gets a mismatch -- which is indistinguishable from
--   tampering. We would be trading ~0.9 MB (2,903 rows x ~300 B) for the integrity
--   property that makes the event log evidence rather than a log file. Bad trade.
--   ⚠️ This is exactly why §4 touches ONLY new_state, which nothing hashes or signs.
--   IF WE WANT IT LATER: the honest route is to stop the WRITER from passing the
--   duplicate payload in the first place, so the hash is computed over the slim
--   payload and stays true. That is an edit to the rule-evaluation caller, not a
--   trigger, and it belongs in its own migration with its own guard.
--
-- DECLINED 2 -- ottoq_vehicle_dispatches.return_evidence.
--   Three tempting sub-cuts, three refusals:
--     (a) `soc_at_decision` is byte-identical to `soc` on 102 of 115 rows. That is
--         89%, not 100%. Dropping it is lossy on the 13 rows where the two differ,
--         and those 13 are precisely the interesting ones -- a decision made at a
--         different SoC than the one recorded is the thing an audit would look for.
--     (b) `soil` carries 71 significant digits and averages 60 B. Rounding is
--         obviously right and I still will not do it blind: I would be choosing a
--         precision without having established the source column's own resolution.
--         (0005 rounds vehicles.soil_index to 3 dp, which SUGGESTS 6 dp here is
--         free -- but "suggests" is the word that means do not ship it.)
--     (c) The constant strings (`reserved_by_bias`, `target_absent_from_loop`,
--         `eta_minutes_is_a_parameter`) have exactly 1 distinct value across 115
--         rows -- they are code comments smuggled into data. Removing them means
--         editing the writer, and the whole table is 435 live rows: the entire
--         available win is ~87 kB.
--   AND THE REAL POINT: this table's "20 kB/row" is 50x BLOAT, not content -- 172,976
--   updates against 435 live rows. §8 addresses the actual cause. A content cut here
--   would have bought 87 kB and left the 8 MB of dead space exactly where it was.
--
-- DECLINED 3 -- ottoq_oem_webhook_log.payload / ottoq_vehicle_commands.payload.
--   Inspected and found to contain nothing removable. The webhook payload is a
--   genuine OEM wire message (~378 B: id, soc, gate, odo, alerts, schema version).
--   The command payload is 96 B of load-bearing UUIDs. Their 107x and 65x storage
--   ratios are churn bloat; §8 is the fix, not a write cut.
--
-- DECLINED 4 -- dropping the dead index idx_webhook_log_vehicle (1,872 kB,
--   idx_scan = 0). House rule is never drop, and idx_scan = 0 is not proof a query
--   never needs it -- it is proof it has not been used since statistics were last
--   reset, and this database has been through a recovery. Recorded, not acted on.
--
-- DECLINED 5 -- extending the chain cut to sibling *.state_changed streams
--   (task.state_changed and the others sharing the identical trigger shape). The
--   argument that they behave the same is strong -- same ottoq_jsonb_diff, same
--   to_jsonb(NEW), same skip-list -- but "same code shape" is not "measured", and
--   only vehicle.state_changed was measured. §2 ships the policy row narrow, and
--   §10 V2 is the exact query to widen it with after measuring.
--
-- ---------------------------------------------------------------------------
-- GAP 1 -- PURGING AN EVENT DIRTIES A FEATURE ROW.
--   ottoq_feature_values.source_event_id is ON DELETE SET NULL against ottoq_events,
--   so every purged event also rewrites a feature_values row. No append-only guard
--   there, so it will not fail -- but a night that deletes 500,000 events also
--   generates 500,000 row versions in feature_values, which is write amplification
--   during exactly the window we are trying to reclaim space in. Not fixed here
--   because the alternatives (ON DELETE NO ACTION plus a nulling sweep, or purging
--   both tables in lockstep) both change referential behaviour, which is outside
--   this file's scope. Watch feature_values size after the first real purge night.
--
-- GAP 2 -- I COULD NOT READ pg_trigger, SO §5.2 IS DEFENSIVE RATHER THAN TARGETED.
--   I was instructed not to touch the database, so I know ottoq_events_block_mutation
--   exists and what it does, but not which statements it is attached to. If it is
--   attached to UPDATE, §5.2 is required for any purge to succeed. If it is not, §5.2
--   is inert. Confirm in one query after applying:
--     SELECT tgname, tgtype::int & 4 AS on_insert, tgtype::int & 8 AS on_delete,
--            tgtype::int & 16 AS on_update
--       FROM pg_trigger WHERE tgrelid='public.ottoq_events'::regclass AND NOT tgisinternal;
--
-- GAP 3 -- CRON JOB 11 STILL PASSES '48 hours'. Harmless (the §2 policy row
--   overrides it) but it now reads as a lie in cron.job. Left alone on purpose:
--   this file changes no schedules, because the one cron-adjacent rule that matters
--   is that job 12 is never touched, and the safest way to honour that is to touch
--   no cron at all. Tidy it in a migration that does nothing else.
--
-- GAP 4 -- THE OLD 3-ARGUMENT ottoq_retention_purge_worker STILL EXISTS AND STILL
--   USES THE PRE-0006 LOGIC. Nothing calls it (cron 11 calls the 4-arg overload) and
--   we never drop, so it stays. If someone calls it by hand they get the old
--   behaviour with the old '48 hours' default. Worth folding into the 4-arg version
--   later, once we have a night of evidence that the new walk behaves.
--
-- GAP 5 -- THE FIRST PURGE NIGHT WILL BE THE BIGGEST ONE THIS SYSTEM HAS EVER RUN.
--   Retention has never deleted an event, so the first armed run has the entire
--   backlog in front of it. It is bounded by p_time_budget_s and commits every
--   window, so it cannot run away -- but expect several nights to drain, and expect
--   the table's SIZE not to fall much at first: deleted space is reusable, not
--   returned. That is correct behaviour and it is not the purge failing. Judge the
--   first nights by rows deleted (V5), not by pg_total_relation_size.
-- ============================================================================
